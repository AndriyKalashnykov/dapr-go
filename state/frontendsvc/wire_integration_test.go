//go:build integration

// Wire-format integration test: validates that the JSON `Order` shape
// frontendsvc produces round-trips losslessly through a real Redis
// backend, with Dapr's `<app-id>||<key>` namespacing applied client-side.
package main

import (
	"context"
	"encoding/json"
	"reflect"
	"testing"
	"time"

	goredis "github.com/redis/go-redis/v9"
	tcredis "github.com/testcontainers/testcontainers-go/modules/redis"

	"github.com/andriykalashnykov/dapr-go-frontendsvc/internal/types"
)

func TestOrderRedisRoundtrip(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	rc, err := tcredis.Run(ctx, "redis:7-alpine")
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

	src := types.Order{
		ID:        "order-deadbeef",
		Items:     []string{"pizza", "cola"},
		Received:  true,
		Completed: true,
	}
	encoded, err := json.Marshal(src)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if err := cli.Set(ctx, src.ID, encoded, 0).Err(); err != nil {
		t.Fatalf("redis set: %v", err)
	}

	got, err := cli.Get(ctx, src.ID).Bytes()
	if err != nil {
		t.Fatalf("redis get: %v", err)
	}
	var dst types.Order
	if err := json.Unmarshal(got, &dst); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !reflect.DeepEqual(src, dst) {
		t.Errorf("roundtrip mismatch: src=%+v dst=%+v", src, dst)
	}

	// Negative case: missing key returns redis.Nil, which the production
	// loadOrder helper translates to errOrderNotFound.
	_, err = cli.Get(ctx, "missing-order").Bytes()
	if err != goredis.Nil {
		t.Errorf("expected redis.Nil for missing key, got %v", err)
	}
}
