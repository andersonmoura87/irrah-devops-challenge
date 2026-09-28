package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func request(a http.Handler, method, path string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	a.ServeHTTP(w, httptest.NewRequest(method, path, nil))
	return w
}

func TestEndpointsAndDrainReadiness(t *testing.T) {
	a := newApplication()
	for _, path := range []string{"/", "/healthz", "/readyz", "/metrics"} {
		if got := request(a, "GET", path).Code; got != http.StatusOK {
			t.Fatalf("%s status=%d", path, got)
		}
	}
	var body map[string]string
	if err := json.Unmarshal(request(a, "GET", "/").Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["service"] != "irrah-lab-http" || body["version"] != version || body["revision"] != revision {
		t.Fatalf("unexpected build metadata: %v", body)
	}
	if got := request(a, "HEAD", "/"); got.Code != http.StatusOK || got.Body.Len() != 0 {
		t.Fatalf("HEAD status=%d body=%q", got.Code, got.Body.String())
	}
	if got := request(a, "POST", "/"); got.Code != http.StatusMethodNotAllowed || got.Header().Get("Allow") != "GET, HEAD" {
		t.Fatalf("POST status=%d allow=%q", got.Code, got.Header().Get("Allow"))
	}
	a.ready.Store(false)
	if got := request(a, "GET", "/readyz").Code; got != http.StatusServiceUnavailable {
		t.Fatalf("draining readiness status=%d", got)
	}
	for _, path := range []string{"/", "/healthz"} {
		if got := request(a, "GET", path).Code; got != http.StatusOK {
			t.Fatalf("drain propagation must keep %s available: status=%d", path, got)
		}
	}
}

func TestMetricsStayBoundedAndExcludeProbes(t *testing.T) {
	a := newApplication()
	const requests = 40
	var done sync.WaitGroup
	for i := range requests {
		done.Add(1)
		go func(i int) {
			defer done.Done()
			request(a, "GET", "/?request=private-query")
			request(a, "GET", fmt.Sprintf("/private-path-%d", i))
			request(a, "CUSTOM-METHOD", "/")
			request(a, "GET", "/healthz")
			request(a, "GET", "/readyz")
			request(a, "GET", "/metrics")
		}(i)
	}
	done.Wait()
	w := request(a, "GET", "/metrics")
	if got := w.Header().Get("Content-Type"); got != "text/plain; version=0.0.4; charset=utf-8" {
		t.Fatalf("content type=%q", got)
	}
	text := w.Body.String()
	for _, forbidden := range []string{"private-query", "private-path", "CUSTOM-METHOD"} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("request-controlled label/content leaked: %s", forbidden)
		}
	}
	for _, expected := range []string{
		`lab_http_requests_total{code="200"} 40`,
		`lab_http_requests_total{code="404"} 40`,
		`lab_http_requests_total{code="405"} 40`,
		"lab_http_request_duration_seconds_count 120",
		"lab_http_in_flight_requests 0",
	} {
		if !strings.Contains(text, expected+"\n") {
			t.Fatalf("missing metric %q in %s", expected, text)
		}
	}
	previous := uint64(0)
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(line, "lab_http_request_duration_seconds_bucket{") {
			parts := strings.Fields(line)
			current, err := strconv.ParseUint(parts[1], 10, 64)
			if err != nil || current < previous || current > 120 {
				t.Fatalf("invalid cumulative histogram bucket: %q", line)
			}
			previous = current
		}
	}
	if previous != 120 {
		t.Fatalf("+Inf bucket=%d, want 120", previous)
	}
}

func startServer(t *testing.T, handler http.Handler) (*http.Server, string, <-chan error) {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := newServer(handler)
	served := make(chan error, 1)
	go func() { served <- server.Serve(listener) }()
	t.Cleanup(func() { _ = server.Close() })
	return server, "http://" + listener.Addr().String(), served
}

func waitFor(t *testing.T, signal <-chan struct{}) {
	t.Helper()
	select {
	case <-signal:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for test request")
	}
}

func TestShutdownCompletesInFlightRequest(t *testing.T) {
	a := newApplication()
	entered, release := make(chan struct{}), make(chan struct{})
	var once sync.Once
	defer once.Do(func() { close(release) })
	// Only this test wraps the handler with a blocking request. The application
	// exposes no delay/fault-injection endpoint or runtime toggle.
	server, baseURL, served := startServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(entered)
		select {
		case <-release:
			a.ServeHTTP(w, r)
		case <-r.Context().Done():
		}
	}))
	client := &http.Client{Timeout: 2 * time.Second}
	defer client.CloseIdleConnections()
	response := make(chan error, 1)
	go func() {
		resp, err := client.Get(baseURL + "/")
		if err == nil {
			defer resp.Body.Close()
			var body map[string]string
			err = json.NewDecoder(resp.Body).Decode(&body)
			if resp.StatusCode != 200 || body["service"] != "irrah-lab-http" {
				err = fmt.Errorf("in-flight response did not complete: status=%d", resp.StatusCode)
			}
		}
		response <- err
	}()
	waitFor(t, entered)
	stopped := make(chan error, 1)
	go func() { stopped <- drainAndShutdown(a, server, 0, time.Second) }()
	deadline := time.Now().Add(time.Second)
	for a.ready.Load() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if a.ready.Load() {
		t.Fatal("shutdown did not clear readiness")
	}
	if got := request(a, "GET", "/readyz").Code; got != 503 {
		t.Fatalf("draining readiness status=%d", got)
	}
	select {
	case err := <-stopped:
		t.Fatalf("shutdown returned before in-flight request finished: %v", err)
	default:
	}
	once.Do(func() { close(release) })
	if err := <-response; err != nil {
		t.Fatal(err)
	}
	if err := <-stopped; err != nil {
		t.Fatal(err)
	}
	if err := <-served; !errors.Is(err, http.ErrServerClosed) {
		t.Fatalf("Serve result=%v", err)
	}
}

func TestShutdownDeadlineClosesBlockedRequest(t *testing.T) {
	a := newApplication()
	entered := make(chan struct{})
	server, baseURL, _ := startServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(entered)
		<-r.Context().Done()
	}))
	client := &http.Client{Timeout: time.Second}
	defer client.CloseIdleConnections()
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		if response, err := client.Get(baseURL + "/"); err == nil {
			_ = response.Body.Close()
		}
	}()
	waitFor(t, entered)
	if err := drainAndShutdown(a, server, 0, 20*time.Millisecond); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("shutdown error=%v, want deadline exceeded", err)
	}
	waitFor(t, finished)
}

func TestCheck(t *testing.T) {
	server := httptest.NewServer(newApplication())
	defer server.Close()
	var output bytes.Buffer
	if err := check(server.URL, &output); err != nil {
		t.Fatal(err)
	}
	if strings.Count(output.String(), "status=200") != 3 {
		t.Fatalf("unexpected smoke output: %s", output.String())
	}
	for _, scenario := range []string{"unready", "metrics-type", "metrics-body", "oversized", "redirect"} {
		t.Run(scenario, func(t *testing.T) {
			a := newApplication()
			bad := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch {
				case scenario == "unready":
					a.ready.Store(false)
				case scenario == "metrics-type" && r.URL.Path == "/metrics":
					writeText(w, 200, "not metrics\n")
					return
				case scenario == "metrics-body" && r.URL.Path == "/metrics":
					w.Header().Set("Content-Type", "text/plain; version=0.0.4")
					_, _ = io.WriteString(w, "unexpected_body\n")
					return
				case scenario == "oversized":
					_, _ = io.WriteString(w, strings.Repeat("x", (64<<10)+1))
					return
				case scenario == "redirect":
					http.Redirect(w, r, "/other", http.StatusTemporaryRedirect)
					return
				}
				a.ServeHTTP(w, r)
			}))
			defer bad.Close()
			if err := check(bad.URL, io.Discard); err == nil {
				t.Fatal("invalid smoke response was accepted")
			}
		})
	}
	if err := check("http://user:private@localhost:8080", io.Discard); err == nil {
		t.Fatal("URL with credentials was accepted")
	}
}

func TestLabFaultEnvLatencyAndErrors(t *testing.T) {
	t.Setenv("LAB_FAULT_LATENCY_MS", "0")
	t.Setenv("LAB_FAULT_ERROR_PERCENT", "100")
	a := newApplication()
	if got := request(a, "GET", "/").Code; got != http.StatusServiceUnavailable {
		t.Fatalf("expected injected 503, got %d", got)
	}
	w := request(a, "GET", "/metrics")
	if !strings.Contains(w.Body.String(), `lab_http_requests_total{code="503"} 1`) {
		t.Fatalf("503 counter missing: %s", w.Body.String())
	}
	t.Setenv("LAB_FAULT_ERROR_PERCENT", "0")
	t.Setenv("LAB_FAULT_LATENCY_MS", "50")
	start := time.Now()
	if got := request(a, "GET", "/").Code; got != http.StatusOK {
		t.Fatalf("latency-only fault should still return 200, got %d", got)
	}
	if time.Since(start) < 40*time.Millisecond {
		t.Fatal("expected artificial latency to affect handler duration")
	}
}
