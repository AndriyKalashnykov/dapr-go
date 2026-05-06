package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	dapr "github.com/dapr/go-sdk/client"

	"github.com/andriykalashnykov/dapr-go-frontendsvc/internal/types"
)

// orderStateClient is the minimal Dapr surface saveOrder/loadOrder need.
// Defined at the use site so unit tests can substitute a fake.
type orderStateClient interface {
	GetState(ctx context.Context, storeName, key string, meta map[string]string) (*dapr.StateItem, error)
	SaveState(ctx context.Context, storeName, key string, data []byte, meta map[string]string, so ...dapr.StateOption) error
}

// errOrderNotFound is returned by loadOrder when the state store has no
// document at the requested key.
var errOrderNotFound = errors.New("order not found")

// saveOrder marks the incoming order received+completed, assigns it a fresh
// ID via idGen, persists it, and returns the populated order. The id-gen
// indirection makes unit tests deterministic.
func saveOrder(ctx context.Context, client orderStateClient, store string, in types.Order, idGen func() string) (types.Order, error) {
	in.ID = idGen()
	in.Received = true
	in.Completed = true

	data, err := json.Marshal(in)
	if err != nil {
		return types.Order{}, fmt.Errorf("marshal order: %w", err)
	}
	if err := client.SaveState(ctx, store, in.ID, data, nil); err != nil {
		return types.Order{}, fmt.Errorf("save state: %w", err)
	}
	return in, nil
}

// loadOrder fetches the raw order JSON for `id`. Returns errOrderNotFound
// when the state store has no entry at that key (Dapr returns a non-nil
// StateItem with empty Value rather than an error in that case).
func loadOrder(ctx context.Context, client orderStateClient, store, id string) ([]byte, error) {
	result, err := client.GetState(ctx, store, id, nil)
	if err != nil {
		return nil, fmt.Errorf("get state: %w", err)
	}
	if result == nil || len(result.Value) == 0 {
		return nil, errOrderNotFound
	}
	return result.Value, nil
}
