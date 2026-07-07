package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	dapr "github.com/dapr/go-sdk/client"

	"github.com/andriykalashnykov/dapr-go-frontendsvc/internal/types"
)

// testStableOrderID is a fixed order ID used by tests that need a
// deterministic idGen (goconst: was repeated as a "order-deadbeef" literal
// 4 times across this file).
const testStableOrderID = "order-deadbeef"

type fakeOrderClient struct {
	getResult *dapr.StateItem
	getErr    error

	saveErr error
	saveGot []byte
	saveKey string
	saves   int
}

func (f *fakeOrderClient) GetState(_ context.Context, _, _ string, _ map[string]string) (*dapr.StateItem, error) {
	return f.getResult, f.getErr
}

func (f *fakeOrderClient) SaveState(_ context.Context, _, key string, data []byte, _ map[string]string, _ ...dapr.StateOption) error {
	f.saves++
	f.saveKey = key
	f.saveGot = data
	return f.saveErr
}

func TestSaveOrder_HappyPath(t *testing.T) {
	t.Parallel()
	fc := &fakeOrderClient{}
	stableID := func() string { return testStableOrderID }

	got, err := saveOrder(context.Background(), fc, "statestore",
		types.Order{Items: []string{"pizza", "cola"}}, stableID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.ID != testStableOrderID {
		t.Errorf("ID=%q, want %s", got.ID, testStableOrderID)
	}
	if !got.Received || !got.Completed {
		t.Errorf("Received/Completed flags not set: %+v", got)
	}
	if fc.saves != 1 || fc.saveKey != testStableOrderID {
		t.Errorf("saves=%d key=%q, want 1/%s", fc.saves, fc.saveKey, testStableOrderID)
	}
	var persisted types.Order
	if err := json.Unmarshal(fc.saveGot, &persisted); err != nil {
		t.Fatalf("persisted payload not valid JSON: %v", err)
	}
	if persisted.ID != testStableOrderID || len(persisted.Items) != 2 {
		t.Errorf("persisted=%+v", persisted)
	}
}

func TestSaveOrder_SaveStateError(t *testing.T) {
	t.Parallel()
	want := errors.New("redis down")
	fc := &fakeOrderClient{saveErr: want}
	_, err := saveOrder(context.Background(), fc, "statestore",
		types.Order{Items: []string{"a"}}, func() string { return "id" })
	if err == nil || !errors.Is(err, want) {
		t.Errorf("err=%v, want wrap of %v", err, want)
	}
}

func TestLoadOrder_HappyPath(t *testing.T) {
	t.Parallel()
	payload := []byte(`{"ID":"order-1","Items":["pizza"],"Received":true,"Completed":true}`)
	fc := &fakeOrderClient{getResult: &dapr.StateItem{Value: payload}}
	got, err := loadOrder(context.Background(), fc, "statestore", "order-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Errorf("loadOrder returned %q, want %q", got, payload)
	}
}

func TestLoadOrder_NotFound(t *testing.T) {
	t.Parallel()
	fc := &fakeOrderClient{getResult: &dapr.StateItem{}} // empty Value
	_, err := loadOrder(context.Background(), fc, "statestore", "missing")
	if !errors.Is(err, errOrderNotFound) {
		t.Errorf("err=%v, want errOrderNotFound", err)
	}
}

func TestLoadOrder_NilResult(t *testing.T) {
	t.Parallel()
	fc := &fakeOrderClient{}
	_, err := loadOrder(context.Background(), fc, "statestore", "missing")
	if !errors.Is(err, errOrderNotFound) {
		t.Errorf("err=%v, want errOrderNotFound", err)
	}
}

func TestLoadOrder_GetStateError(t *testing.T) {
	t.Parallel()
	want := errors.New("dapr unreachable")
	fc := &fakeOrderClient{getErr: want}
	_, err := loadOrder(context.Background(), fc, "statestore", "order-1")
	if err == nil || !errors.Is(err, want) {
		t.Errorf("err=%v, want wrap of %v", err, want)
	}
}

// TestPostOrder_MalformedJSON_Returns400 exercises the HTTP handler's own
// decode branch (postOrder, not saveOrder): a body that fails json.Decode
// must short-circuit with 400 before ever touching the Dapr client.
// Hermetic — no Dapr sidecar, no network.
func TestPostOrder_MalformedJSON_Returns400(t *testing.T) {
	t.Parallel()
	req := httptest.NewRequest(http.MethodPost, "/orders/new", strings.NewReader("{not valid json"))
	rec := httptest.NewRecorder()

	postOrder(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d, want %d", rec.Code, http.StatusBadRequest)
	}
}
