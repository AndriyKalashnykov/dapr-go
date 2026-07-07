package main

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync/atomic"
	"time"

	dapr "github.com/dapr/go-sdk/client"

	"github.com/andriykalashnykov/dapr-go-frontendsvc/internal/types"
)

const stateStoreName = "statestore"

// Health endpoint names (the `{endpoint}` path value on GET /health/{endpoint}).
const (
	endpointReadiness = "readiness"
	endpointLiveness  = "liveness"
)

// HTTP server timeout defaults (gosec G114: net/http serve helpers with no
// timeout support are vulnerable to slowloris-style resource exhaustion).
const (
	readHeaderTimeout = 5 * time.Second
	readTimeout       = 15 * time.Second
	writeTimeout      = 15 * time.Second
	idleTimeout       = 60 * time.Second
)

var (
	appPort    = getenvOrDefault("APP_PORT", "8080")
	daprClient dapr.Client
	// daprReady flips true once the Dapr sidecar connection is established; the
	// readiness probe reads it so traffic only flows to a pod with a working sidecar.
	daprReady atomic.Bool
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

// run holds every deferred cleanup (the Dapr client Close) so that main()
// only ever calls log.Fatal AFTER run has returned and its defers have
// already executed (gocritic exitAfterDefer: log.Fatal[f] inside a deferred
// scope would exit the process before defer daprClient.Close() could run).
func run() error {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /orders/new", postOrder)
	mux.HandleFunc("GET /orders/order/{id}", getOrder)
	mux.HandleFunc("GET /health/{endpoint}", healthCheck)

	srv := &http.Server{
		Addr:              ":" + appPort,
		Handler:           mux,
		ReadHeaderTimeout: readHeaderTimeout,
		ReadTimeout:       readTimeout,
		WriteTimeout:      writeTimeout,
		IdleTimeout:       idleTimeout,
	}
	// Serve immediately (background) so liveness/readiness endpoints are reachable
	// while we connect to the sidecar (health is decoupled from the Dapr connection).
	serveErr := make(chan error, 1)
	go func() { serveErr <- srv.ListenAndServe() }()
	log.Printf("frontend: starting service: port %s", appPort)

	// The daprd sidecar and this app start concurrently; NewClient can time out
	// while the sidecar loads components. Retry with bounded backoff — the app is
	// already serving /health, so a slow sidecar only delays readiness, never
	// kills the pod (no CrashLoopBackOff, no probe knife-edge).
	var dc dapr.Client
	var err error
	for attempt := 1; attempt <= 40; attempt++ {
		if dc, err = dapr.NewClient(); err == nil {
			break
		}
		log.Printf("dapr client not ready (attempt %d/40): %v", attempt, err)
		time.Sleep(3 * time.Second)
	}
	if err != nil {
		_ = srv.Close()
		return fmt.Errorf("frontend: dapr client after 40 attempts: %w", err)
	}
	daprClient = dc
	defer daprClient.Close()
	daprReady.Store(true)
	log.Printf("frontend: dapr client connected, readiness now true")

	if err := <-serveErr; err != nil {
		return fmt.Errorf("frontend: %w", err)
	}
	return nil
}

func postOrder(w http.ResponseWriter, r *http.Request) {
	var in types.Order
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		log.Printf("postOrder: decode: %s", err)
		http.Error(w, "unable to decode order", http.StatusBadRequest)
		return
	}

	saved, err := saveOrder(r.Context(), daprClient, stateStoreName, in, randomOrderID)
	if err != nil {
		log.Printf("postOrder: %s", err)
		http.Error(w, "unable to post order", http.StatusInternalServerError)
		return
	}

	log.Printf("order received: [orderid=%s]", saved.ID)
	w.Header().Set("Content-Type", "application/json")
	if _, err := fmt.Fprintf(w, `{"order":"%s","status":"received"}`, saved.ID); err != nil {
		log.Printf("postOrder: write response: %s", err)
	}
}

func getOrder(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")

	data, err := loadOrder(r.Context(), daprClient, stateStoreName, id)
	if errors.Is(err, errOrderNotFound) {
		http.Error(w, "order not found", http.StatusNotFound)
		return
	}
	if err != nil {
		log.Printf("getOrder: %s", err)
		http.Error(w, "unable to get order", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	//nolint:gosec // G705: JSON API response (Content-Type application/json set above), not HTML — no XSS surface
	if _, err := w.Write(data); err != nil {
		log.Printf("getOrder: write response: %s", err)
	}
}

// healthCheck mirrors the read-values/subscriber chi route
// `GET /health/{endpoint:readiness|liveness}` — frontendsvc's router is the
// stdlib net/http.ServeMux (no regex path constraints), so the
// readiness|liveness constraint is enforced in the handler body instead of
// the route pattern.
func healthCheck(w http.ResponseWriter, r *http.Request) {
	switch r.PathValue("endpoint") {
	case endpointReadiness:
		// Readiness reflects the Dapr connection so traffic waits for a working sidecar.
		if !daprReady.Load() {
			http.Error(w, `{"ok":false}`, http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	case endpointLiveness:
		// Liveness is process-alive only — never gated on the sidecar, so a slow
		// sidecar can't cause a restart loop.
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	default:
		http.NotFound(w, r)
	}
}

// randomOrderID generates an order ID from 4 cryptographically random bytes
// (gosec G404: math/rand is not suitable for anything that must not be
// predictable/guessable, including resource identifiers). Falls back to a
// timestamp-derived suffix in the astronomically unlikely case crypto/rand's
// entropy source is unavailable, so order creation never hard-fails on it.
func randomOrderID() string {
	var b [4]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("order-%x", time.Now().UnixNano())
	}
	return fmt.Sprintf("order-%x", b)
}

func getenvOrDefault(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}
