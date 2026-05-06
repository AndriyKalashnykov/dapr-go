package main

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	dapr "github.com/dapr/go-sdk/client"

	"github.com/andriykalashnykov/dapr-go-frontendsvc/internal/types"
)

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
	stableID := func() string { return "order-deadbeef" }

	got, err := saveOrder(context.Background(), fc, "statestore",
		types.Order{Items: []string{"pizza", "cola"}}, stableID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.ID != "order-deadbeef" {
		t.Errorf("ID=%q, want order-deadbeef", got.ID)
	}
	if !got.Received || !got.Completed {
		t.Errorf("Received/Completed flags not set: %+v", got)
	}
	if fc.saves != 1 || fc.saveKey != "order-deadbeef" {
		t.Errorf("saves=%d key=%q, want 1/order-deadbeef", fc.saves, fc.saveKey)
	}
	var persisted types.Order
	if err := json.Unmarshal(fc.saveGot, &persisted); err != nil {
		t.Fatalf("persisted payload not valid JSON: %v", err)
	}
	if persisted.ID != "order-deadbeef" || len(persisted.Items) != 2 {
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
	if string(got) != string(payload) {
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
