package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/vaibhavsrivastava/zerodowntime-pipeline/internal/handler"
	"github.com/vaibhavsrivastava/zerodowntime-pipeline/internal/health"
	"github.com/vaibhavsrivastava/zerodowntime-pipeline/internal/middleware"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "unknown"
	}

	checker := health.NewChecker()

	mux := http.NewServeMux()
	mux.HandleFunc("/", handler.Root(version))
	mux.HandleFunc("/healthz", checker.LivenessHandler)
	mux.HandleFunc("/readyz", checker.ReadinessHandler)
	mux.Handle("/metrics", promhttp.Handler())
	mux.HandleFunc("/api/v1/status", handler.Status(version))

	logged := middleware.Chain(mux,
		middleware.RequestID,
		middleware.Logging,
		middleware.Recovery,
		middleware.Metrics,
	)

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      logged,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("server starting on :%s (version=%s)", port, version)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	// Mark ready after startup completes
	checker.SetReady(true)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit
	log.Printf("received signal %v, starting graceful shutdown", sig)

	// Stop accepting new traffic before draining
	checker.SetReady(false)

	// Give load balancer time to deregister this pod
	drainDelay := 5 * time.Second
	if d := os.Getenv("DRAIN_DELAY"); d != "" {
		if parsed, err := time.ParseDuration(d); err == nil {
			drainDelay = parsed
		}
	}
	log.Printf("waiting %s for in-flight requests to drain", drainDelay)
	time.Sleep(drainDelay)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("forced shutdown: %v", err)
	}

	fmt.Println("server stopped gracefully")
}
