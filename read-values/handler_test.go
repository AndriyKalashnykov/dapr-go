package main

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	dapr "github.com/dapr/go-sdk/client"
)

type fakeStateGetter struct {
	result *dapr.StateItem
	err    error
}

func (f *fakeStateGetter) GetState(_ context.Context, _, _ string, _ map[string]string) (*dapr.StateItem, error) {
	return f.result, f.err
}

func mustEncode(t *testing.T, v MyValues) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal fixture: %v", err)
	}
	return b
}

func TestAverageStoredValues(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		stored MyValues
		empty  bool // override: simulate empty state
		want   float64
	}{
		{name: "empty state returns 0", empty: true, want: 0},
		{name: "empty values slice returns 0", stored: MyValues{Values: []string{}}, want: 0},
		{
			name:   "single value",
			stored: MyValues{Values: []string{"5"}},
			want:   5,
		},
		{
			name:   "non-integer division — was 3.0 before the float-cast fix",
			stored: MyValues{Values: []string{"7", "2"}},
			want:   4.5,
		},
		{
			name:   "exact integer division",
			stored: MyValues{Values: []string{"4", "8"}},
			want:   6,
		},
		{
			name:   "skips malformed entries",
			stored: MyValues{Values: []string{"10", "garbage", "20", "", "30"}},
			want:   20, // (10+20+30)/3
		},
		{
			name:   "all malformed returns 0",
			stored: MyValues{Values: []string{"a", "b", "c"}},
			want:   0,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var fg *fakeStateGetter
			if tc.empty {
				fg = &fakeStateGetter{result: &dapr.StateItem{}}
			} else {
				fg = &fakeStateGetter{result: &dapr.StateItem{Value: mustEncode(t, tc.stored)}}
			}
			got, err := averageStoredValues(context.Background(), fg, "statestore", "values")
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %v, want %v", got, tc.want)
			}
		})
	}
}

func TestAverageStoredValues_GetStateError(t *testing.T) {
	t.Parallel()
	want := errors.New("dapr unreachable")
	fg := &fakeStateGetter{err: want}
	_, err := averageStoredValues(context.Background(), fg, "statestore", "values")
	if err == nil || !errors.Is(err, want) {
		t.Errorf("err=%v, want wrap of %v", err, want)
	}
}

func TestAverageStoredValues_CorruptStoredJSON(t *testing.T) {
	t.Parallel()
	fg := &fakeStateGetter{result: &dapr.StateItem{Value: []byte("not json")}}
	_, err := averageStoredValues(context.Background(), fg, "statestore", "values")
	if err == nil {
		t.Fatal("expected error for corrupt stored JSON")
	}
}
