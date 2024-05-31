package main

import (
	"encoding/json"
	"fmt"
	"github.com/go-chi/chi/v5"
	"log"
	"net/http"
	"os"

	dapr "github.com/dapr/go-sdk/client"
)

var (
	daprClient       dapr.Client
	STATE_STORE_NAME = GetenvOrDefault("STATE_STORE_NAME", "statestore")
	DAPR_HOST        = GetenvOrDefault("DAPR_HOST", "127.0.0.1")
	DAPR_PORT        = GetenvOrDefault("DAPR_PORT", "50001")
	PUB_SUB_NAME     = GetenvOrDefault("PUB_SUB_NAME", "notifications-pubsub")
	PUB_SUB_TOPIC    = GetenvOrDefault("PUB_SUB_TOPIC", "notifications")
)

type MyValues struct {
	Values []string
}

func main() {

	//dc, err := dapr.NewClientWithAddressContext(context.Background(), fmt.Sprintf("%s:%s", DAPR_HOST, DAPR_PORT))
	dc, err := dapr.NewClient()
	if err != nil {
		log.Fatalf("dapr client: NewClient: %s", err)
		//panic(err)
	}

	daprClient = dc
	defer daprClient.Close()

	port := GetenvOrDefault("APP_PORT", "8080")
	r := chi.NewRouter()
	r.Post("/", Handle)
	log.Printf("Starting Write Values App in Port: %s", port)
	http.ListenAndServe(":"+port, r)
}

func Handle(res http.ResponseWriter, req *http.Request) {

	value := req.URL.Query().Get("value")
	fmt.Println("Got data:", value)
	myValues := MyValues{}

	if req.Context() == nil {
		fmt.Println("Context is nil")
	}
	result, err := daprClient.GetState(req.Context(), STATE_STORE_NAME, "values", nil)

	if err == nil {
		if result.Value != nil {
			json.Unmarshal(result.Value, &myValues)
		}

		if myValues.Values == nil || len(myValues.Values) == 0 {
			myValues.Values = []string{value}
		} else {
			myValues.Values = append(myValues.Values, value)
		}

		jsonData, err := json.Marshal(myValues)

		err = daprClient.SaveState(req.Context(), STATE_STORE_NAME, "values", jsonData, nil)
		if err != nil {
			log.Println("error: %s", err)
		}

		daprClient.PublishEvent(req.Context(), PUB_SUB_NAME, PUB_SUB_TOPIC, []byte(value))
		log.Printf("Published data:", jsonData)
	} else {
		respondWithJSON(res, http.StatusOK, myValues)
		log.Println("error: %s", err)
	}

}

func respondWithJSON(w http.ResponseWriter, code int, payload interface{}) {
	response, _ := json.Marshal(payload)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	w.Write(response)
}

func GetenvOrDefault(envName, defaultValue string) string {
	v := os.Getenv(envName)
	if v != "" {
		return v
	}
	return defaultValue
}
