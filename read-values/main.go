package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	dapr "github.com/dapr/go-sdk/client"
	"github.com/go-chi/chi/v5"
)

const stateKey = "values"

// HTTP server timeout defaults (gosec G114: net/http serve helpers with no
// timeout support are vulnerable to slowloris-style resource exhaustion).
const (
	readHeaderTimeout = 5 * time.Second
	readTimeout       = 15 * time.Second
	writeTimeout      = 15 * time.Second
	idleTimeout       = 60 * time.Second
)

var (
	daprClient     dapr.Client
	stateStoreName = GetenvOrDefault("STATE_STORE_NAME", "statestore")
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
	dc, err := dapr.NewClient()
	if err != nil {
		return fmt.Errorf("dapr client: NewClient: %w", err)
	}
	daprClient = dc
	defer daprClient.Close()

	r := chi.NewRouter()
	r.Get("/", Handle)
	r.Get("/health/{endpoint:readiness|liveness}", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	})
	port := GetenvOrDefault("APP_PORT", "8080")
	log.Printf("Starting Read Values App in Port: %s", port)

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           r,
		ReadHeaderTimeout: readHeaderTimeout,
		ReadTimeout:       readTimeout,
		WriteTimeout:      writeTimeout,
		IdleTimeout:       idleTimeout,
	}
	if err := srv.ListenAndServe(); err != nil {
		return fmt.Errorf("read-values: ListenAndServe: %w", err)
	}
	return nil
}

func Handle(res http.ResponseWriter, req *http.Request) {
	avg, err := averageStoredValues(req.Context(), daprClient, stateStoreName, stateKey)
	if err != nil {
		log.Printf("read-values: %s", err)
		http.Error(res, "unable to read state", http.StatusInternalServerError)
		return
	}
	respondWithJSON(res, http.StatusOK, avg)
}

func respondWithJSON(w http.ResponseWriter, code int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("read-values: encode response: %s", err)
	}
}

func GetenvOrDefault(envName, defaultValue string) string {
	if v := os.Getenv(envName); v != "" {
		return v
	}
	return defaultValue
}
