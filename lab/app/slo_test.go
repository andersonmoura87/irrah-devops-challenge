package main

import (
	"strings"
	"testing"
)

func TestSuccessRatio(t *testing.T) {
	s := LabSLISnapshot{Rate200: 10, Rate503: 0}
	if got := s.SuccessRatio(); got != 1 {
		t.Fatalf("got %v want 1", got)
	}
	s = LabSLISnapshot{Rate200: 45, Rate503: 5}
	if got := s.SuccessRatio(); got < 0.899 || got > 0.901 {
		t.Fatalf("got %v want ~0.9", got)
	}
}

func TestEvaluateLabSLOBaselinePass(t *testing.T) {
	targets := DefaultLabSLOTargets()
	s := LabSLISnapshot{Rate200: 2.5, Rate503: 0.01, P95: 0.05, Ready: 2}
	ok, v := EvaluateLabSLO(s, targets)
	if !ok || len(v) != 0 {
		t.Fatalf("expected pass, violations=%v", v)
	}
}

func TestEvaluateLabSLOFaultFail(t *testing.T) {
	targets := DefaultLabSLOTargets()
	s := LabSLISnapshot{Rate200: 0.5, Rate503: 0.8, P95: 0.6, Ready: 2}
	ok, v := EvaluateLabSLO(s, targets)
	if ok || len(v) < 2 {
		t.Fatalf("expected multiple violations, ok=%v v=%v", ok, v)
	}
}

func TestLoadLabSLOTargetsFromConfig(t *testing.T) {
	targets, err := LoadLabSLOTargets()
	if err != nil {
		t.Fatalf("LoadLabSLOTargets: %v", err)
	}
	if targets.MinSuccessRatio != 0.92 || targets.Max503Rate != 0.04 ||
		targets.MaxP95Seconds != 0.12 || targets.MinReadySum != 1.9 {
		t.Fatalf("unexpected thresholds: %+v", targets)
	}
}

func TestFormatLabSLISummary(t *testing.T) {
	line := FormatLabSLISummary("baseline", LabSLISnapshot{Rate200: 1, Rate503: 0, P95: 0.01, Ready: 2}, true, nil)
	if !strings.Contains(line, "phase=baseline") || !strings.Contains(line, "status=PASS") {
		t.Fatalf("unexpected summary: %s", line)
	}
}
