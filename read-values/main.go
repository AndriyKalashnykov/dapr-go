package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"

	dapr "github.com/dapr/go-sdk/client"
	"github.com/go-chi/chi/v5"
)

const stateKey = "values"

var (
	daprClient     dapr.Client
	stateStoreName = GetenvOrDefault("STATE_STORE_NAME", "statestore")
)

type MyValues struct {
	Values []string
}

func main() {
	dc, err := dapr.NewClient()
	if err != nil {
		log.Fatalf("dapr client: NewClient: %s", err)
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
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatalf("read-values: ListenAndServe: %s", err)
	}
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
