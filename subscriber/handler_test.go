package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNotifications(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		body       string
		wantStatus int
		wantBodyIn string // substring expected in response, "" = ignore
	}{
		{
			name:       "valid event echoes payload",
			body:       `{"data":"42"}`,
			wantStatus: http.StatusOK,
			wantBodyIn: `"data":"42"`,
		},
		{
			name:       "malformed JSON returns 400 without crashing the process",
			body:       `not json`,
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "empty body returns 400",
			body:       ``,
			wantStatus: http.StatusBadRequest,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/notifications",
				bytes.NewBufferString(tc.body))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()

			notifications(rec, req)

			if rec.Code != tc.wantStatus {
				t.Errorf("status=%d, want %d (body: %q)", rec.Code, tc.wantStatus, rec.Body.String())
			}
			if tc.wantBodyIn != "" && !strings.Contains(rec.Body.String(), tc.wantBodyIn) {
				t.Errorf("body=%q, want containing %q", rec.Body.String(), tc.wantBodyIn)
			}
		})
	}
}
