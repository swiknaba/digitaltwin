// Digitaltwin offline tests injected into a disposable upstream checkout.
// Only provider HTTP transport is replaced; upstream retry code remains unchanged.
package server

import (
	"context"
	"errors"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"fmt"
	"github.com/mattermost/mattermost/server/public/shared/mlog"
	apns "github.com/sideshow/apns2"
	"google.golang.org/api/option"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

type digitaltwinTransport func(*http.Request) (*http.Response, error)

func (f digitaltwinTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestDigitaltwinAPNsTransportRetry(t *testing.T) {
	for _, tc := range []struct {
		name       string
		fail       bool
		budget     time.Duration
		wantCalls  int
		alwaysFail bool
	}{
		{"recovers after transport failure", true, 3 * time.Second, 2, false},
		{"does not retry provider rejection", false, 3 * time.Second, 1, false},
		{"total deadline bounds retries", true, 40 * time.Millisecond, 1, false},
		{"maximum attempts", true, 5 * time.Second, 3, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			logger, err := mlog.NewLogger()
			if err != nil {
				t.Fatal(err)
			}
			defer logger.Shutdown()
			calls := 0
			client := &apns.Client{Host: "https://provider.invalid", HTTPClient: &http.Client{Transport: digitaltwinTransport(func(r *http.Request) (*http.Response, error) {
				calls++
				if _, ok := r.Context().Deadline(); !ok {
					t.Fatal("missing deadline")
				}
				if tc.fail && (calls == 1 || tc.alwaysFail) {
					return nil, errors.New("offline transport failure")
				}
				status, body := 200, "{}"
				if !tc.fail {
					status, body = 400, `{"reason":"BadDeviceToken"}`
				}
				return &http.Response{StatusCode: status, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body))}, nil
			})}}
			server := &AppleNotificationServer{AppleClient: client, logger: logger, sendTimeout: tc.budget, retryTimeout: time.Second}
			start := time.Now()
			res, err := server.SendNotificationWithRetry(&apns.Notification{DeviceToken: "disposable-token", Payload: []byte(`{"aps":{"alert":"offline"}}`)})
			if calls != tc.wantCalls {
				t.Fatalf("calls=%d want=%d", calls, tc.wantCalls)
			}
			if tc.budget < time.Second {
				if !errors.Is(err, context.DeadlineExceeded) || time.Since(start) > time.Second {
					t.Fatalf("deadline not enforced: %v", err)
				}
			} else if tc.alwaysFail {
				if err == nil {
					t.Fatal("failure disappeared")
				}
			} else if err != nil {
				t.Fatal(err)
			} else if res == nil {
				t.Fatal("missing response")
			}
		})
	}
}
func TestDigitaltwinFCMRetryClassification(t *testing.T) {
	for _, tc := range []struct {
		name, code string
		want       bool
	}{
		{"internal", "INTERNAL", true}, {"quota", "QUOTA_EXCEEDED", true},
		{"invalid argument", "INVALID_ARGUMENT", false}, {"revoked auth", "THIRD_PARTY_AUTH_ERROR", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			app, err := firebase.NewApp(context.Background(), &firebase.Config{ProjectID: "fixture"}, option.WithoutAuthentication(), option.WithHTTPClient(&http.Client{Transport: digitaltwinTransport(func(r *http.Request) (*http.Response, error) {
				body := fmt.Sprintf(`{"error":{"code":400,"message":"offline fixture","status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"%s"}]}}`, tc.code)
				return &http.Response{StatusCode: 400, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body))}, nil
			})}))
			if err != nil {
				t.Fatal(err)
			}
			client, err := app.Messaging(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			_, err = client.Send(context.Background(), &messaging.Message{Token: "fixture"})
			if err == nil {
				t.Fatal("expected provider rejection")
			}
			if got := isRetryable(err); got != tc.want {
				t.Fatalf("retry=%v want=%v: %v", got, tc.want, err)
			}
		})
	}
	if !isRetryable(context.DeadlineExceeded) || isRetryable(errors.New("offline")) {
		t.Fatal("deadline/ordinary error classification changed")
	}
}
