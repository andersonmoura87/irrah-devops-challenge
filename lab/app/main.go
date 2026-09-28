package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

var (
	version  = "dev"
	revision = "unknown"
)

var latencyBounds = [...]float64{0.005, 0.025, 0.1, 0.5, 1, 5}

type application struct {
	ready    atomic.Bool
	metrics  metrics
	faultSeq atomic.Uint64
}

type metrics struct {
	mu       sync.Mutex
	requests [4]uint64 // Fixed codes: 200, 404, 405, 503. Never labels from user input.
	buckets  [6]uint64
	count    uint64
	sum      float64
	inFlight int64
}

func newApplication() *application {
	a := &application{}
	a.ready.Store(true)
	return a
}

func (a *application) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Probes and scrapes are excluded from application request metrics.
	switch r.URL.Path {
	case "/healthz":
		writeText(w, http.StatusOK, "alive\n")
	case "/readyz":
		if !a.ready.Load() {
			writeText(w, http.StatusServiceUnavailable, "draining\n")
			return
		}
		writeText(w, http.StatusOK, "ready\n")
	case "/metrics":
		a.writeMetrics(w)
	default:
		a.handleApplication(w, r)
	}
}

// labFaultSettings reads operator-controlled env vars (Deployment patch in the lab).
// Not an HTTP API: activation is kubectl/set env + rollout, not a public chaos endpoint.
func labFaultSettings() (time.Duration, int) {
	ms, _ := strconv.Atoi(strings.TrimSpace(os.Getenv("LAB_FAULT_LATENCY_MS")))
	if ms < 0 {
		ms = 0
	}
	if ms > 30_000 {
		ms = 30_000
	}
	percent, _ := strconv.Atoi(strings.TrimSpace(os.Getenv("LAB_FAULT_ERROR_PERCENT")))
	if percent < 0 {
		percent = 0
	}
	if percent > 100 {
		percent = 100
	}
	return time.Duration(ms) * time.Millisecond, percent
}

func writeText(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_, _ = io.WriteString(w, body)
}

func (a *application) handleApplication(w http.ResponseWriter, r *http.Request) {
	started := time.Now()
	status := http.StatusOK
	a.metrics.mu.Lock()
	a.metrics.inFlight++
	a.metrics.mu.Unlock()
	defer func() { a.metrics.observe(status, time.Since(started).Seconds()) }()

	if r.URL.Path != "/" {
		status = http.StatusNotFound
		writeText(w, status, "not found\n")
		return
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		status = http.StatusMethodNotAllowed
		w.Header().Set("Allow", "GET, HEAD")
		writeText(w, status, "method not allowed\n")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	if r.Method == http.MethodHead {
		w.WriteHeader(status)
		return
	}
	latency, errPercent := labFaultSettings()
	if latency > 0 {
		time.Sleep(latency)
	}
	if errPercent > 0 {
		n := a.faultSeq.Add(1)
		if int(n%100) < errPercent {
			status = http.StatusServiceUnavailable
			writeText(w, status, "service unavailable\n")
			return
		}
	}
	_ = json.NewEncoder(w).Encode(struct {
		Service  string `json:"service"`
		Version  string `json:"version"`
		Revision string `json:"revision"`
	}{"irrah-lab-http", version, revision})
}

func (m *metrics) observe(status int, seconds float64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.inFlight--
	switch status {
	case http.StatusOK:
		m.requests[0]++
	case http.StatusNotFound:
		m.requests[1]++
	case http.StatusMethodNotAllowed:
		m.requests[2]++
	case http.StatusServiceUnavailable:
		m.requests[3]++
	}
	m.count++
	m.sum += seconds
	for i, bound := range latencyBounds {
		if seconds <= bound {
			m.buckets[i]++
		}
	}
}

func (a *application) writeMetrics(w http.ResponseWriter) {
	a.metrics.mu.Lock()
	requests, buckets := a.metrics.requests, a.metrics.buckets
	count, sum, inFlight := a.metrics.count, a.metrics.sum, a.metrics.inFlight
	a.metrics.mu.Unlock()
	ready := 0
	if a.ready.Load() {
		ready = 1
	}
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	fmt.Fprintln(w, "# HELP lab_http_requests_total Completed application requests; probes and metrics excluded.")
	fmt.Fprintln(w, "# TYPE lab_http_requests_total counter")
	for i, code := range [...]int{200, 404, 405, 503} {
		fmt.Fprintf(w, "lab_http_requests_total{code=\"%d\"} %d\n", code, requests[i])
	}
	fmt.Fprintln(w, "# HELP lab_http_request_duration_seconds Application handler duration in seconds.")
	fmt.Fprintln(w, "# TYPE lab_http_request_duration_seconds histogram")
	for i, bound := range latencyBounds {
		fmt.Fprintf(w, "lab_http_request_duration_seconds_bucket{le=\"%g\"} %d\n", bound, buckets[i])
	}
	fmt.Fprintf(w, "lab_http_request_duration_seconds_bucket{le=\"+Inf\"} %d\n", count)
	fmt.Fprintf(w, "lab_http_request_duration_seconds_sum %g\n", sum)
	fmt.Fprintf(w, "lab_http_request_duration_seconds_count %d\n", count)
	fmt.Fprintln(w, "# HELP lab_http_in_flight_requests Active application handlers.")
	fmt.Fprintln(w, "# TYPE lab_http_in_flight_requests gauge")
	fmt.Fprintf(w, "lab_http_in_flight_requests %d\n", inFlight)
	fmt.Fprintln(w, "# HELP lab_ready Whether the application is accepting service membership.")
	fmt.Fprintln(w, "# TYPE lab_ready gauge")
	fmt.Fprintf(w, "lab_ready %d\n", ready)
}

func newServer(handler http.Handler) *http.Server {
	return &http.Server{
		Addr:              ":8080",
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
}

func drainAndShutdown(a *application, server *http.Server, drainDelay, shutdownTimeout time.Duration) error {
	a.ready.Store(false)
	// Keep serving during endpoint propagation. This delay is a lab choice,
	// not proof that every Kubernetes dataplane converges within five seconds.
	log.Print("event=draining readiness=false")
	timer := time.NewTimer(drainDelay)
	defer timer.Stop()
	<-timer.C
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		_ = server.Close()
		return fmt.Errorf("graceful shutdown failed: %w", err)
	}
	log.Print("event=stopped graceful=true")
	return nil
}

func serve() error {
	a := newApplication()
	server := newServer(a)
	listener, err := net.Listen("tcp", server.Addr)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	served := make(chan error, 1)
	go func() { served <- server.Serve(listener) }()
	log.Printf("event=started addr=:8080 version=%q revision=%q", version, revision)
	select {
	case err := <-served:
		return err
	case <-ctx.Done():
		stop() // A second signal may terminate immediately.
		if err := drainAndShutdown(a, server, 5*time.Second, 20*time.Second); err != nil {
			return err
		}
		if err := <-served; !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	}
}

func check(baseURL string, output io.Writer) error {
	base, err := url.Parse(baseURL)
	if err != nil || base.Host == "" || (base.Scheme != "http" && base.Scheme != "https") ||
		base.User != nil || base.RawQuery != "" || base.Fragment != "" || (base.Path != "" && base.Path != "/") {
		return errors.New("check requires an HTTP(S) origin without credentials, query or path")
	}
	client := &http.Client{
		Timeout: 3 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return errors.New("redirect not allowed")
		},
	}
	defer client.CloseIdleConnections()
	for _, path := range []string{"/healthz", "/readyz", "/metrics"} {
		response, err := client.Get(strings.TrimRight(baseURL, "/") + path)
		if err != nil {
			// Do not echo a URL, response body or credentials to smoke-test logs.
			return fmt.Errorf("check %s: request failed", path)
		}
		body, readErr := io.ReadAll(io.LimitReader(response.Body, (64<<10)+1))
		_ = response.Body.Close()
		if readErr != nil || len(body) > 64<<10 {
			return fmt.Errorf("check %s: unreadable or oversized response", path)
		}
		if response.StatusCode != http.StatusOK {
			return fmt.Errorf("check %s: status=%d", path, response.StatusCode)
		}
		if path == "/metrics" {
			if !strings.HasPrefix(response.Header.Get("Content-Type"), "text/plain; version=0.0.4") {
				return errors.New("check /metrics: unexpected content type")
			}
			for _, expected := range []string{
				"# TYPE lab_http_requests_total counter\n",
				"# TYPE lab_http_request_duration_seconds histogram\n",
				"lab_http_request_duration_seconds_count ",
				"lab_ready 1\n",
			} {
				if !strings.Contains(string(body), expected) {
					return errors.New("check /metrics: missing expected metric or readiness")
				}
			}
		}
		fmt.Fprintf(output, "GET %s status=%d\n", path, response.StatusCode)
	}
	return nil
}

func main() {
	log.SetFlags(log.LstdFlags | log.LUTC)
	var err error
	switch {
	case len(os.Args) == 1:
		err = serve()
	case len(os.Args) == 3 && os.Args[1] == "check":
		err = check(os.Args[2], os.Stdout)
	default:
		err = errors.New("usage: lab-http [check <baseURL>]")
	}
	if err != nil {
		log.Printf("error: %v", err)
		os.Exit(1)
	}
}
