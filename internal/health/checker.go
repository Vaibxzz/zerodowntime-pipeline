package health

import (
	"encoding/json"
	"net/http"
	"sync/atomic"
)

type Checker struct {
	ready atomic.Bool
}

func NewChecker() *Checker {
	return &Checker{}
}

func (c *Checker) SetReady(v bool) {
	c.ready.Store(v)
}

func (c *Checker) IsReady() bool {
	return c.ready.Load()
}

// LivenessHandler returns 200 if the process is alive.
// Kubernetes uses this to decide whether to restart the container.
func (c *Checker) LivenessHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "alive"})
}

// ReadinessHandler returns 200 only when the pod should receive traffic.
// Returns 503 during startup and graceful shutdown so the Service
// stops routing new requests before the pod terminates.
func (c *Checker) ReadinessHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if !c.IsReady() {
		w.WriteHeader(http.StatusServiceUnavailable)
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "not_ready"})
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
}
