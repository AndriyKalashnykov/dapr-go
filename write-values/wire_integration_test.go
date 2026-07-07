//go:build integration

// Wire-format integration test: validates that the JSON `MyValues` shape
// write-values produces round-trips losslessly through a real Redis backend.
//
// Why this is non-trivial despite being JSON: a future contributor changing
// `Values []string` → `Values []int`, or renaming the field, or switching
// to a different struct-tag convention, would silently break the cross-
// service contract with read-values and the canonical wire format consumed
// by Dapr. The unit test asserts in-process Marshal/Unmarshal of the same
// type — this test asserts it survives an out-of-process roundtrip too.
package main

import (
	"context"
	"encoding/json"
	"reflect"
	"testing"
	"time"

	goredis "github.com/redis/go-redis/v9"
	tcredis "github.com/testcontainers/testcontainers-go/modules/redis"
)

// testRedisImage is Renovate-tracked via the *.go customManager in
// renovate.json. NEVER inline this literal into tcredis.Run — Renovate
// won't see the string, the pin will drift, CVEs will accumulate.
//
// renovate: datasource=docker depName=redis
const testRedisImage = "redis:8-alpine"

func TestMyValuesRedisRoundtrip(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	rc, err := tcredis.Run(ctx, testRedisImage)
	if err != nil {
		t.Fatalf("start redis container: %v", err)
	}
	t.Cleanup(func() { _ = rc.Terminate(ctx) })

	uri, err := rc.ConnectionString(ctx)
	if err != nil {
		t.Fatalf("redis connection string: %v", err)
	}
	opts, err := goredis.ParseURL(uri)
	if err != nil {
		t.Fatalf("parse redis URL: %v", err)
	}
	cli := goredis.NewClient(opts)
	t.Cleanup(func() { _ = cli.Close() })

	src := MyValues{Values: []string{"10", "20", "30"}}
	encoded, err := json.Marshal(src)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if err := cli.Set(ctx, "values", encoded, 0).Err(); err != nil {
		t.Fatalf("redis set: %v", err)
	}

	got, err := cli.Get(ctx, "values").Bytes()
	if err != nil {
		t.Fatalf("redis get: %v", err)
	}
	var dst MyValues
	if err := json.Unmarshal(got, &dst); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !reflect.DeepEqual(src, dst) {
		t.Errorf("roundtrip mismatch: src=%v dst=%v", src, dst)
	}

	// Cross-service contract guard: the JSON written by write-values must be
	// parseable by a struct shaped like read-values' MyValues (same package
	// has the same shape; this future-proofs against drift if either side
	// renames a field). Decoded via a locally-defined twin so the assertion
	// fails if either side's `json:` tags or field names diverge.
	var twin struct {
		Values []string
	}
	if err := json.Unmarshal(got, &twin); err != nil {
		t.Fatalf("twin unmarshal: %v", err)
	}
	if !reflect.DeepEqual(src.Values, twin.Values) {
		t.Errorf("cross-service contract drift: src.Values=%v twin.Values=%v", src.Values, twin.Values)
	}
}
