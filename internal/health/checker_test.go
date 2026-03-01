package health_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/vaibhavsrivastava/zerodowntime-pipeline/internal/health"
)

func TestLiveness_AlwaysOK(t *testing.T) {
	c := health.NewChecker()
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	c.LivenessHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestReadiness_NotReadyByDefault(t *testing.T) {
	c := health.NewChecker()
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	c.ReadinessHandler(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", rec.Code)
	}

	var resp map[string]string
	json.NewDecoder(rec.Body).Decode(&resp)
	if resp["status"] != "not_ready" {
		t.Errorf("expected not_ready, got %s", resp["status"])
	}
}

func TestReadiness_ReadyAfterSet(t *testing.T) {
	c := health.NewChecker()
	c.SetReady(true)

	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	c.ReadinessHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestReadiness_BackToNotReady(t *testing.T) {
	c := health.NewChecker()
	c.SetReady(true)
	c.SetReady(false)

	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	c.ReadinessHandler(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 after setting not ready, got %d", rec.Code)
	}
}
