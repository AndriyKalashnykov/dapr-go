package main

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"os"

	"github.com/go-chi/chi/v5"
)

type Result struct {
	Data string `json:"data"`
}

func notifications(w http.ResponseWriter, r *http.Request) {
	if dump, err := httputil.DumpRequest(r, true); err == nil {
		log.Println(string(dump))
	}

	data, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("notifications: read body: %s", err)
		http.Error(w, "unable to read request body", http.StatusBadRequest)
		return
	}

	var result Result
	if err := json.Unmarshal(data, &result); err != nil {
		log.Printf("notifications: unmarshal: %s", err)
		http.Error(w, "invalid JSON payload", http.StatusBadRequest)
		return
	}
	log.Printf("Subscriber received on /notifications: %s", result.Data)

	w.Header().Set("Content-Type", "application/json")
	if _, err := w.Write(data); err != nil {
		log.Printf("notifications: write response: %s", err)
	}
}

func printRoot(_ http.ResponseWriter, r *http.Request) {
	if dump, err := httputil.DumpRequest(r, true); err == nil {
		log.Println(string(dump))
	}
}

func main() {
	port := GetenvOrDefault("APP_PORT", "8080")

	r := chi.NewRouter()
	r.Post("/", printRoot)
	r.Post("/notifications", notifications)
	r.Get("/health/{endpoint:readiness|liveness}", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	})

	log.Printf("Starting Subscriber in Port: %s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatalf("subscriber: ListenAndServe: %s", err)
	}
}

func GetenvOrDefault(envName, defaultValue string) string {
	if v := os.Getenv(envName); v != "" {
		return v
	}
	return defaultValue
}
