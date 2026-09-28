package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
)

// LabSLOTargets are demonstrative objectives for the local lab only — not production SLAs.
type LabSLOTargets struct {
	MinSuccessRatio float64
	Max503Rate      float64
	MaxP95Seconds   float64
	MinReadySum     float64
}

type labSLOConfigFile struct {
	MinSuccessRatio float64 `json:"minSuccessRatio"`
	Max503Rate      float64 `json:"max503Rate"`
	MaxP95Seconds   float64 `json:"maxP95Seconds"`
	MinReadySum     float64 `json:"minReadySum"`
}

func labSLOConfigPath() string {
	if p := strings.TrimSpace(os.Getenv("LAB_SLO_CONFIG")); p != "" {
		return p
	}
	for _, candidate := range []string{
		filepath.Join("..", "config", "slo.json"),
		filepath.Join("config", "slo.json"),
	} {
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return filepath.Join("..", "config", "slo.json")
}

// LoadLabSLOTargets reads thresholds from lab/config/slo.json (or LAB_SLO_CONFIG).
func LoadLabSLOTargets() (LabSLOTargets, error) {
	path := labSLOConfigPath()
	raw, err := os.ReadFile(path)
	if err != nil {
		return LabSLOTargets{}, fmt.Errorf("read SLO config %s: %w", path, err)
	}
	var file labSLOConfigFile
	if err := json.Unmarshal(raw, &file); err != nil {
		return LabSLOTargets{}, fmt.Errorf("parse SLO config %s: %w", path, err)
	}
	return LabSLOTargets{
		MinSuccessRatio: file.MinSuccessRatio,
		Max503Rate:      file.Max503Rate,
		MaxP95Seconds:   file.MaxP95Seconds,
		MinReadySum:     file.MinReadySum,
	}, nil
}

// DefaultLabSLOTargets loads configured thresholds for verify-slo-lab and tests.
func DefaultLabSLOTargets() LabSLOTargets {
	targets, err := LoadLabSLOTargets()
	if err != nil {
		panic(err)
	}
	return targets
}

// LabSLISnapshot values come from Prometheus instant queries over the lab metrics.
type LabSLISnapshot struct {
	Rate200 float64
	Rate503 float64
	P95     float64
	Ready   float64
}

func (s LabSLISnapshot) SuccessRatio() float64 {
	denom := s.Rate200 + s.Rate503
	if denom <= 0 {
		return 1
	}
	return s.Rate200 / denom
}

// EvaluateLabSLO returns whether all objectives are met and human-readable violations.
func EvaluateLabSLO(s LabSLISnapshot, t LabSLOTargets) (ok bool, violations []string) {
	if math.IsNaN(s.Rate200) || math.IsNaN(s.Rate503) || math.IsNaN(s.P95) || math.IsNaN(s.Ready) {
		return false, []string{"metric values must be finite numbers"}
	}
	ratio := s.SuccessRatio()
	if ratio < t.MinSuccessRatio {
		violations = append(violations, fmt.Sprintf("success ratio %.4f < min %.4f", ratio, t.MinSuccessRatio))
	}
	if s.Rate503 > t.Max503Rate {
		violations = append(violations, fmt.Sprintf("503 rate %.4f > max %.4f", s.Rate503, t.Max503Rate))
	}
	if s.P95 > t.MaxP95Seconds {
		violations = append(violations, fmt.Sprintf("p95 %.4fs > max %.4fs", s.P95, t.MaxP95Seconds))
	}
	if s.Ready < t.MinReadySum {
		violations = append(violations, fmt.Sprintf("ready sum %.2f < min %.2f", s.Ready, t.MinReadySum))
	}
	return len(violations) == 0, violations
}

// FormatLabSLISummary produces a single-line sanitized summary for evidence files.
func FormatLabSLISummary(phase string, s LabSLISnapshot, ok bool, violations []string) string {
	status := "PASS"
	if !ok {
		status = "FAIL"
	}
	v := strings.Join(violations, "; ")
	if v == "" {
		v = "-"
	}
	return fmt.Sprintf("phase=%s status=%s success_ratio=%.4f rate503=%.4f p95=%.4fs ready=%.2f violations=%s",
		phase, status, s.SuccessRatio(), s.Rate503, s.P95, s.Ready, v)
}
