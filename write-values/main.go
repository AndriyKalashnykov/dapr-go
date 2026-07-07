package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
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
	daprClient dapr.Client
	cfg        = writeConfig{
		StoreName:   GetenvOrDefault("STATE_STORE_NAME", "statestore"),
		StateKey:    stateKey,
		PubSubName:  GetenvOrDefault("PUB_SUB_NAME", "notifications-pubsub"),
		PubSubTopic: GetenvOrDefault("PUB_SUB_TOPIC", "notifications"),
	}
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

	port := GetenvOrDefault("APP_PORT", "8080")
	r := chi.NewRouter()
	r.Post("/", Handle)
	r.Get("/health/{endpoint:readiness|liveness}", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	})
	log.Printf("Starting Write Values App in Port: %s", port)

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           r,
		ReadHeaderTimeout: readHeaderTimeout,
		ReadTimeout:       readTimeout,
		WriteTimeout:      writeTimeout,
		IdleTimeout:       idleTimeout,
	}
	if err := srv.ListenAndServe(); err != nil {
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
