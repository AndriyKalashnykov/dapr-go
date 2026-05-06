package main

import (
	"context"
	"encoding/json"
	"fmt"

	dapr "github.com/dapr/go-sdk/client"
)

// stateAndPubSubClient is the minimal Dapr surface appendAndPublish needs.
// Defined at the use site (not pulled from the SDK) so unit tests can
// substitute a fake without spinning up a real Dapr sidecar.
type stateAndPubSubClient interface {
	GetState(ctx context.Context, storeName, key string, meta map[string]string) (*dapr.StateItem, error)
	SaveState(ctx context.Context, storeName, key string, data []byte, meta map[string]string, so ...dapr.StateOption) error
	PublishEvent(ctx context.Context, pubsubName, topicName string, data any, opts ...dapr.PublishEventOption) error
}

// writeConfig captures the Dapr component + key plumbing without coupling
// to package-level globals — production code passes the same values from
// env, tests pass deterministic constants.
type writeConfig struct {
	StoreName   string
	StateKey    string
	PubSubName  string
	PubSubTopic string
}

// appendAndPublish reads the current MyValues, appends `value`, persists it,
// then publishes `value` on the pub/sub topic. Returns the new MyValues on
// success. Errors carry enough context to identify which Dapr call failed.
func appendAndPublish(ctx context.Context, client stateAndPubSubClient, cfg writeConfig, value string) (MyValues, error) {
	result, err := client.GetState(ctx, cfg.StoreName, cfg.StateKey, nil)
	if err != nil {
		return MyValues{}, fmt.Errorf("get state: %w", err)
	}

	var values MyValues
	if result != nil && len(result.Value) > 0 {
		if err := json.Unmarshal(result.Value, &values); err != nil {
			return MyValues{}, fmt.Errorf("unmarshal stored values: %w", err)
		}
	}
	values.Values = append(values.Values, value)

	encoded, err := json.Marshal(values)
	if err != nil {
		return MyValues{}, fmt.Errorf("marshal values: %w", err)
	}

	if err := client.SaveState(ctx, cfg.StoreName, cfg.StateKey, encoded, nil); err != nil {
		return MyValues{}, fmt.Errorf("save state: %w", err)
	}

	if err := client.PublishEvent(ctx, cfg.PubSubName, cfg.PubSubTopic, []byte(value)); err != nil {
		return MyValues{}, fmt.Errorf("publish event: %w", err)
	}
	return values, nil
}
