package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync/atomic"
	"time"

	dapr "github.com/dapr/go-sdk/client"
	"github.com/go-chi/chi/v5"
)

const stateKey = "values"

// endpointReadiness is the `{endpoint}` path value the readiness probe hits.
const endpointReadiness = "readiness"

// HTTP server timeout defaults (gosec G114: net/http serve helpers with no
// timeout support are vulnerable to slowloris-style resource exhaustion).
const (
	readHeaderTimeout = 5 * time.Second
	readTimeout       = 15 * time.Second
	writeTimeout      = 15 * time.Second
	idleTimeout       = 60 * time.Second
)

var (
	daprClient dapr.Client
	cfg        = writeConfig{
		StoreName:   GetenvOrDefault("STATE_STORE_NAME", "statestore"),
		StateKey:    stateKey,
		PubSubName:  GetenvOrDefault("PUB_SUB_NAME", "notifications-pubsub"),
		PubSubTopic: GetenvOrDefault("PUB_SUB_TOPIC", "notifications"),
	}
	// daprReady flips true once the Dapr sidecar connection is established; the
	// readiness probe reads it so traffic only flows to a pod with a working sidecar.
	daprReady atomic.Bool
)

type MyValues struct {
	Values []string
}

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
	port := GetenvOrDefault("APP_PORT", "8080")
	r := chi.NewRouter()
	r.Post("/", Handle)
	// Health is served independently of the Dapr connection so the liveness probe
	// never kills the pod while the sidecar is still starting. Readiness returns
	// 200 only once the Dapr client is connected, so the Deployment's Available
	// condition (and traffic) waits for a working sidecar without a kill/restart race.
	r.Get("/health/{endpoint:readiness|liveness}", healthHandler)

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           r,
		ReadHeaderTimeout: readHeaderTimeout,
		ReadTimeout:       readTimeout,
		WriteTimeout:      writeTimeout,
		IdleTimeout:       idleTimeout,
	}
	// Serve immediately (background) so liveness/readiness endpoints are reachable
	// while we connect to the sidecar.
	serveErr := make(chan error, 1)
	go func() { serveErr <- srv.ListenAndServe() }()
	log.Printf("Starting Write Values App in Port: %s", port)

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
		return fmt.Errorf("write-values: dapr client after 40 attempts: %w", err)
	}
	daprClient = dc
	defer daprClient.Close()
	daprReady.Store(true)
	log.Printf("write-values: dapr client connected, readiness now true")

	if err := <-serveErr; err != nil {
		return fmt.Errorf("write-values: ListenAndServe: %w", err)
	}
	return nil
}

// errMissingValue is returned when the request omits the required query param.
var errMissingValue = errors.New("missing required query parameter 'value'")

// sanitizeLog strips CR/LF from untrusted input before it is written to the
// log, preventing log injection / forged log lines (gosec G706, CWE-117).
func sanitizeLog(s string) string {
	replacer := strings.NewReplacer("\n", " ", "\r", " ")
	return replacer.Replace(s)
}

// healthHandler serves the k8s probes. Readiness reflects daprReady (503 until
// the sidecar connects); liveness (the only other endpoint the chi route
// matches) is always 200 so a slow sidecar can't trigger a restart.
func healthHandler(w http.ResponseWriter, req *http.Request) {
	if chi.URLParam(req, "endpoint") == endpointReadiness && !daprReady.Load() {
		http.Error(w, `{"ok":false}`, http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

func Handle(res http.ResponseWriter, req *http.Request) {
	value := req.URL.Query().Get("value")
	if value == "" {
		http.Error(res, errMissingValue.Error(), http.StatusBadRequest)
		return
	}

	values, err := appendAndPublish(req.Context(), daprClient, cfg, value)
	if err != nil {
		log.Printf("write-values: %s", err)
		http.Error(res, "unable to persist value", http.StatusInternalServerError)
		return
	}

	//nolint:gosec // G706: value is CR/LF-sanitized via sanitizeLog before logging
	log.Printf("write-values: persisted %d values, published %q", len(values.Values), sanitizeLog(value))
	respondWithJSON(res, http.StatusOK, values)
}

func respondWithJSON(w http.ResponseWriter, code int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("write-values: encode response: %s", err)
	}
}

func GetenvOrDefault(envName, defaultValue string) string {
	if v := os.Getenv(envName); v != "" {
		return v
	}
	return defaultValue
}
