package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"

	dapr "github.com/dapr/go-sdk/client"

	"github.com/andriykalashnykov/dapr-go-frontendsvc/internal/types"
)

const stateStoreName = "statestore"

var (
	appPort    = getenvOrDefault("APP_PORT", "8080")
	daprClient dapr.Client
)

func main() {
	dc, err := dapr.NewClient()
	if err != nil {
		log.Fatalf("dapr client: NewClient: %s", err)
	}
	daprClient = dc
	defer daprClient.Close()

	log.Printf("frontend: starting service: port %s", appPort)

	mux := http.NewServeMux()
	mux.HandleFunc("POST /orders/new", postOrder)
	mux.HandleFunc("GET /orders/order/{id}", getOrder)

	if err := http.ListenAndServe(":"+appPort, mux); err != nil {
		log.Fatalf("frontend: %s", err)
	}
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
	if _, err := w.Write(data); err != nil {
		log.Printf("getOrder: write response: %s", err)
	}
}

func randomOrderID() string {
	return fmt.Sprintf("order-%x", rand.Int31())
}

func getenvOrDefault(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}
