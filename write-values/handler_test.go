package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	dapr "github.com/dapr/go-sdk/client"
	"github.com/go-chi/chi/v5"
)

// fakeClient drives every branch in appendAndPublish. Each method records
// its inputs and returns the next programmed result, so a single test can
// assert both behaviour and call shape.
type fakeClient struct {
	getStateResult *dapr.StateItem
	getStateErr    error

	saveStateErr error
	saveStateGot []byte // last payload SaveState was called with

	publishErr error
	publishGot []byte // last value PublishEvent was called with

	publishCalls int
	saveCalls    int
}

func (f *fakeClient) GetState(_ context.Context, _, _ string, _ map[string]string) (*dapr.StateItem, error) {
	return f.getStateResult, f.getStateErr
}

func (f *fakeClient) SaveState(_ context.Context, _, _ string, data []byte, _ map[string]string, _ ...dapr.StateOption) error {
	f.saveCalls++
	f.saveStateGot = data
	return f.saveStateErr
}

func (f *fakeClient) PublishEvent(_ context.Context, _, _ string, data any, _ ...dapr.PublishEventOption) error {
	f.publishCalls++
	if b, ok := data.([]byte); ok {
		f.publishGot = b
	}
	return f.publishErr
}

var testCfg = writeConfig{
	StoreName:   "statestore",
	StateKey:    "values",
	PubSubName:  "notifications-pubsub",
	PubSubTopic: "notifications",
}

func TestAppendAndPublish_HappyPath_EmptyState(t *testing.T) {
	t.Parallel()
	fc := &fakeClient{getStateResult: &dapr.StateItem{}} // empty Value
	got, err := appendAndPublish(context.Background(), fc, testCfg, "42")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got.Values) != 1 || got.Values[0] != "42" {
		t.Errorf("got %v, want [42]", got.Values)
	}
	if fc.saveCalls != 1 || fc.publishCalls != 1 {
		t.Errorf("saveCalls=%d publishCalls=%d, want 1/1", fc.saveCalls, fc.publishCalls)
	}
	if string(fc.publishGot) != "42" {
		t.Errorf("publishGot=%q, want 42", fc.publishGot)
	}
	var saved MyValues
	if err := json.Unmarshal(fc.saveStateGot, &saved); err != nil {
		t.Fatalf("saved payload not valid JSON: %v", err)
	}
	if len(saved.Values) != 1 || saved.Values[0] != "42" {
		t.Errorf("saved=%v, want [42]", saved.Values)
	}
}

func TestAppendAndPublish_HappyPath_AppendsToExisting(t *testing.T) {
	t.Parallel()
	existing, _ := json.Marshal(MyValues{Values: []string{"1", "2"}})
	fc := &fakeClient{getStateResult: &dapr.StateItem{Value: existing}}
	got, err := appendAndPublish(context.Background(), fc, testCfg, "3")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{"1", "2", "3"}
	if len(got.Values) != 3 {
		t.Fatalf("got %v, want %v", got.Values, want)
	}
	for i, v := range want {
		if got.Values[i] != v {
			t.Errorf("got[%d]=%q, want %q", i, got.Values[i], v)
		}
	}
}

func TestAppendAndPublish_GetStateError(t *testing.T) {
	t.Parallel()
	want := errors.New("dapr unreachable")
	fc := &fakeClient{getStateErr: want}
	_, err := appendAndPublish(context.Background(), fc, testCfg, "42")
	if err == nil || !errors.Is(err, want) {
		t.Errorf("err=%v, want wrap of %v", err, want)
	}
	if fc.saveCalls != 0 || fc.publishCalls != 0 {
		t.Errorf("save/publish should not run on GetState error; got %d/%d", fc.saveCalls, fc.publishCalls)
	}
}

func TestAppendAndPublish_CorruptStoredJSON(t *testing.T) {
	t.Parallel()
	fc := &fakeClient{getStateResult: &dapr.StateItem{Value: []byte("not json")}}
	_, err := appendAndPublish(context.Background(), fc, testCfg, "42")
	if err == nil {
		t.Fatal("expected error for corrupt stored JSON")
	}
	if fc.saveCalls != 0 || fc.publishCalls != 0 {
		t.Errorf("save/publish should not run on unmarshal error; got %d/%d", fc.saveCalls, fc.publishCalls)
	}
}

func TestAppendAndPublish_SaveStateError(t *testing.T) {
	t.Parallel()
	want := errors.New("redis down")
	fc := &fakeClient{
		getStateResult: &dapr.StateItem{},
		saveStateErr:   want,
	}
	_, err := appendAndPublish(context.Background(), fc, testCfg, "42")
	if err == nil || !errors.Is(err, want) {
		t.Errorf("err=%v, want wrap of %v", err, want)
	}
	if fc.publishCalls != 0 {
		t.Errorf("publish should not run on SaveState error; got %d", fc.publishCalls)
	}
}

func TestAppendAndPublish_PublishError(t *testing.T) {
	t.Parallel()
	want := errors.New("broker down")
	fc := &fakeClient{
		getStateResult: &dapr.StateItem{},
		publishErr:     want,
	}
	_, err := appendAndPublish(context.Background(), fc, testCfg, "42")
	if err == nil || !errors.Is(err, want) {
		t.Errorf("err=%v, want wrap of %v", err, want)
	}
	// SaveState should have already succeeded — partial failure is observable.
	if fc.saveCalls != 1 {
		t.Errorf("saveCalls=%d, want 1", fc.saveCalls)
	}
}

// TestHandle_MissingValue_Returns400 exercises the HTTP handler's own
// validation branch (Handle, not appendAndPublish): a request with no
// `value` query parameter must short-circuit with 400 before ever touching
// the Dapr client. Hermetic — no Dapr sidecar, no network.
func TestHandle_MissingValue_Returns400(t *testing.T) {
	t.Parallel()
	req := httptest.NewRequestWithContext(context.Background(), http.MethodPost, "/", http.NoBody)
	rec := httptest.NewRecorder()

	Handle(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d, want %d", rec.Code, http.StatusBadRequest)
	}
	if body := rec.Body.String(); !strings.Contains(body, errMissingValue.Error()) {
		t.Errorf("body=%q, want to contain %q", body, errMissingValue.Error())
	}
}

// TestHealthHandler exercises the readiness-gating contract (decoupled from the
// Dapr connection to survive the sidecar-startup race): readiness returns 503
// until daprReady, 200 after; liveness is always 200 (the chi route constrains
// {endpoint} to readiness|liveness, so no other value reaches the handler).
func TestHealthHandler(t *testing.T) {
	tests := []struct {
		name     string
		endpoint string
		ready    bool
		want     int
	}{
		{"readiness before dapr connected -> 503", endpointReadiness, false, http.StatusServiceUnavailable},
		{"readiness after dapr connected -> 200", endpointReadiness, true, http.StatusOK},
		{"liveness is always 200", "liveness", false, http.StatusOK},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			daprReady.Store(tc.ready)
			req := httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/health/"+tc.endpoint, http.NoBody)
			rctx := chi.NewRouteContext()
			rctx.URLParams.Add("endpoint", tc.endpoint)
			req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
			rec := httptest.NewRecorder()

			healthHandler(rec, req)

			if rec.Code != tc.want {
				t.Fatalf("endpoint=%s ready=%v: status=%d, want %d", tc.endpoint, tc.ready, rec.Code, tc.want)
			}
		})
	}
	daprReady.Store(false) // reset shared package state
}
