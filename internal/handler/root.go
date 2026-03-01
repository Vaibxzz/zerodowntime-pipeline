package handler

import (
	"encoding/json"
	"net/http"
	"os"
	"time"
)

var startTime = time.Now()

type StatusResponse struct {
	Status    string `json:"status"`
	Version   string `json:"version"`
	Hostname  string `json:"hostname"`
	Uptime    string `json:"uptime"`
	Timestamp string `json:"timestamp"`
}

func Root(version string) http.HandlerFunc {
	hostname, _ := os.Hostname()
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		resp := StatusResponse{
			Status:    "ok",
			Version:   version,
			Hostname:  hostname,
			Uptime:    time.Since(startTime).Truncate(time.Second).String(),
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}
}

func Status(version string) http.HandlerFunc {
	hostname, _ := os.Hostname()
	return func(w http.ResponseWriter, r *http.Request) {
		resp := StatusResponse{
			Status:    "ok",
			Version:   version,
			Hostname:  hostname,
			Uptime:    time.Since(startTime).Truncate(time.Second).String(),
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}
}
