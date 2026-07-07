//go:build integration

// Wire-format integration test: pre-populates Redis with a canonical
// `MyValues` JSON payload (the shape write-values produces) and verifies
// `averageStoredValues` reads it back correctly through a fake stateGetter
// that proxies to a real Redis container.
//
// This catches drift in either direction: if read-values' Unmarshal target
// changes, OR if the canonical JSON shape changes, this test fails.
package main

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	dapr "github.com/dapr/go-sdk/client"
	goredis "github.com/redis/go-redis/v9"
	tcredis "github.com/testcontainers/testcontainers-go/modules/redis"
)

// redisBackedGetter implements stateGetter against a real Redis client.
// In production this role is filled by the Dapr SDK; in this test we bypass
// Dapr to focus on the JSON wire format.
type redisBackedGetter struct {
	cli *goredis.Client
}

func (g *redisBackedGetter) GetState(ctx context.Context, _, key string, _ map[string]string) (*dapr.StateItem, error) {
	bytes, err := g.cli.Get(ctx, key).Bytes()
	if err == goredis.Nil {
		return &dapr.StateItem{Key: key}, nil
	}
	if err != nil {
		return nil, err
	}
	return &dapr.StateItem{Key: key, Value: bytes}, nil
}

// testRedisImage is Renovate-tracked via the *.go customManager in
// renovate.json. NEVER inline this literal into tcredis.Run — Renovate
// won't see the string, the pin will drift, CVEs will accumulate.
//
// renovate: datasource=docker depName=redis
const testRedisImage = "redis:8-alpine"

func TestAverageStoredValuesAgainstRedis(t *testing.T) {
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
	getter := &redisBackedGetter{cli: cli}

	tests := []struct {
		name   string
		stored MyValues
		want   float64
		empty  bool
	}{
		{name: "empty key returns 0", empty: true, want: 0},
		{name: "single integer", stored: MyValues{Values: []string{"5"}}, want: 5},
		{name: "non-divisible average", stored: MyValues{Values: []string{"7", "2"}}, want: 4.5},
		{name: "skips malformed entries", stored: MyValues{Values: []string{"10", "garbage", "20", "30"}}, want: 20},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if tc.empty {
				_ = cli.Del(ctx, "values").Err()
			} else {
				encoded, err := json.Marshal(tc.stored)
				if err != nil {
					t.Fatalf("marshal: %v", err)
				}
				if err := cli.Set(ctx, "values", encoded, 0).Err(); err != nil {
					t.Fatalf("redis set: %v", err)
				}
			}

			got, err := averageStoredValues(ctx, getter, "statestore", "values")
			if err != nil {
				t.Fatalf("averageStoredValues: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %v, want %v", got, tc.want)
			}
		})
	}
}
