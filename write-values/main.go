package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"

	dapr "github.com/dapr/go-sdk/client"
	"github.com/go-chi/chi/v5"
)

const stateKey = "values"

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
	dc, err := dapr.NewClient()
	if err != nil {
		log.Fatalf("dapr client: NewClient: %s", err)
	}
	daprClient = dc
	defer daprClient.Close()

	port := GetenvOrDefault("APP_PORT", "8080")
	r := chi.NewRouter()
	r.Post("/", Handle)
	log.Printf("Starting Write Values App in Port: %s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatalf("write-values: ListenAndServe: %s", err)
	}
}

// errMissingValue is returned when the request omits the required query param.
var errMissingValue = errors.New("missing required query parameter 'value'")

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

	log.Printf("write-values: persisted %d values, published %q", len(values.Values), value)
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
