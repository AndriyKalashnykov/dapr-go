package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	dapr "github.com/dapr/go-sdk/client"
)

// stateGetter is the minimal Dapr surface averageStoredValues needs.
// Defined at the use site so unit tests can substitute a fake.
type stateGetter interface {
	GetState(ctx context.Context, storeName, key string, meta map[string]string) (*dapr.StateItem, error)
}

// averageStoredValues reads the JSON-encoded MyValues from the state store,
// parses each entry as int (skipping non-integers with a logged warning at
// the caller's discretion), and returns the arithmetic mean.
//
// Returns 0 when the key is empty or no entries parse as integers; this is
// safe because count-zero is a valid "no data yet" state, not an error.
//
// Float division uses `float64(total) / float64(count)`, NOT
// `float64(total / count)` — the latter integer-divides first and silently
// truncates (avg(7,2) returns 3.0 instead of 3.5). See
// /rules/golang/testing.md §"Integer division before float cast".
func averageStoredValues(ctx context.Context, client stateGetter, store, key string) (float64, error) {
	result, err := client.GetState(ctx, store, key, nil)
	if err != nil {
		return 0, fmt.Errorf("get state: %w", err)
	}
	if result == nil || len(result.Value) == 0 {
		return 0, nil
	}

	var values MyValues
	if err := json.Unmarshal(result.Value, &values); err != nil {
		return 0, fmt.Errorf("unmarshal stored values: %w", err)
	}

	var total, count int
	for _, v := range values.Values {
		n, err := strconv.Atoi(v)
		if err != nil {
			// Malformed entries are skipped, not fatal — a single bad
			// write should not poison every subsequent read.
			continue
		}
		total += n
		count++
	}
	if count == 0 {
		return 0, nil
	}
	return float64(total) / float64(count), nil
}
