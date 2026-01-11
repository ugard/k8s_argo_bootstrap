package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAlertFormatter_Format(t *testing.T) {
	formatter := NewAlertFormatter()

	tests := []struct {
		name     string
		alert    Alert
		expected string
	}{
		{
			name: "critical alert",
			alert: Alert{
				Labels: map[string]string{
					"alertname": "NodeDown",
					"severity":  "critical",
					"namespace": "monitoring",
					"instance":  "node-01",
				},
				Annotations: map[string]string{
					"summary": "Node is down",
				},
			},
			expected: "🔴 NodeDown: Node is down (monitoring/node-01)",
		},
		{
			name: "warning alert",
			alert: Alert{
				Labels: map[string]string{
					"alertname": "HighCPU",
					"severity":  "warning",
					"namespace": "production",
					"instance":  "app-server",
				},
				Annotations: map[string]string{
					"summary": "CPU usage above 80%",
				},
			},
			expected: "🟡 HighCPU: CPU usage above 80% (production/app-server)",
		},
		{
			name: "info alert",
			alert: Alert{
				Labels: map[string]string{
					"alertname": "ConfigChanged",
					"severity":  "info",
				},
				Annotations: map[string]string{
					"summary": "Configuration was updated",
				},
			},
			expected: "🔵 ConfigChanged: Configuration was updated (unknown/unknown)",
		},
		{
			name: "alert with exported_namespace",
			alert: Alert{
				Labels: map[string]string{
					"alertname":          "CertificateExpiring",
					"severity":           "warning",
					"exported_namespace": "firefly",
				},
				Annotations: map[string]string{
					"summary": "Certificate expires soon",
				},
			},
			expected: "🟡 CertificateExpiring: Certificate expires soon (firefly/unknown)",
		},
		{
			name: "alert with pod instead of instance",
			alert: Alert{
				Labels: map[string]string{
					"alertname": "PodCrash",
					"severity":  "critical",
					"namespace": "default",
					"pod":       "myapp-pod-abc123",
				},
				Annotations: map[string]string{
					"summary": "Pod crashed",
				},
			},
			expected: "🔴 PodCrash: Pod crashed (default/myapp-pod-abc123)",
		},
		{
			name: "unknown severity",
			alert: Alert{
				Labels: map[string]string{
					"alertname": "UnknownAlert",
					"severity":  "unknown",
				},
				Annotations: map[string]string{
					"summary": "Something happened",
				},
			},
			expected: "⚪ UnknownAlert: Something happened (unknown/unknown)",
		},
		{
			name: "missing summary uses default",
			alert: Alert{
				Labels: map[string]string{
					"alertname": "TestAlert",
					"severity":  "warning",
				},
				Annotations: map[string]string{},
			},
			expected: "⚪ TestAlert: No description (unknown/unknown)",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := formatter.Format(&tt.alert)
			if result != tt.expected {
				t.Errorf("Format() = %q, want %q", result, tt.expected)
			}
		})
	}
}

func TestWebhookHandler_ServeHTTP(t *testing.T) {
	formatter := NewAlertFormatter()
	sender := &MockNtfySender{}
	handler := NewWebhookHandler(formatter, sender)

	tests := []struct {
		name           string
		method         string
		path           string
		body           string
		expectedStatus int
		sendCalled     bool
		expectedTitle  string
	}{
		{
			name:           "POST to /webhook with firing alert",
			method:         http.MethodPost,
			path:           "/webhook",
			body:           `{"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"TestAlert","severity":"warning","namespace":"test"},"annotations":{"summary":"Test"}}],"groupLabels":{"alertname":"TestAlert"}}`,
			expectedStatus: http.StatusOK,
			sendCalled:     true,
			expectedTitle:  "Alert: TestAlert",
		},
		{
			name:           "POST to /webhook with resolved alert",
			method:         http.MethodPost,
			path:           "/webhook",
			body:           `{"status":"resolved","alerts":[{"status":"resolved","labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"Test"}}],"groupLabels":{"alertname":"TestAlert"}}`,
			expectedStatus: http.StatusOK,
			sendCalled:     true,
			expectedTitle:  "Resolved: TestAlert",
		},
		{
			name:           "GET method not allowed",
			method:         http.MethodGet,
			path:           "/webhook",
			body:           "",
			expectedStatus: http.StatusMethodNotAllowed,
			sendCalled:     false,
		},
		{
			name:           "wrong path returns 404",
			method:         http.MethodPost,
			path:           "/other",
			body:           "{}",
			expectedStatus: http.StatusNotFound,
			sendCalled:     false,
		},
		{
			name:           "invalid JSON",
			method:         http.MethodPost,
			path:           "/webhook",
			body:           "invalid",
			expectedStatus: http.StatusBadRequest,
			sendCalled:     false,
		},
		{
			name:           "empty alerts",
			method:         http.MethodPost,
			path:           "/webhook",
			body:           `{"status":"firing","alerts":[]}`,
			expectedStatus: http.StatusOK,
			sendCalled:     false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sender.reset()

			req := httptest.NewRequest(tt.method, tt.path, strings.NewReader(tt.body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			handler.ServeHTTP(w, req)

			if w.Code != tt.expectedStatus {
				t.Errorf("ServeHTTP() status = %d, want %d", w.Code, tt.expectedStatus)
			}

			if tt.sendCalled != sender.called {
				t.Errorf("Send() called = %v, want %v", sender.called, tt.sendCalled)
			}

			if tt.sendCalled && tt.expectedTitle != "" && sender.lastTitle != tt.expectedTitle {
				t.Errorf("Send() title = %q, want %q", sender.lastTitle, tt.expectedTitle)
			}
		})
	}
}

type MockNtfySender struct {
	called    bool
	lastTitle string
	lastMsg   string
}

func (m *MockNtfySender) reset() {
	m.called = false
	m.lastTitle = ""
	m.lastMsg = ""
}

func (m *MockNtfySender) Send(message, title, priority string) error {
	m.called = true
	m.lastTitle = title
	m.lastMsg = message
	return nil
}

func TestNtfySender_Send(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("Content-Type = %q, want %q", r.Header.Get("Content-Type"), "application/json")
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	sender := NewNtfySender(server.URL, "test-token")

	err := sender.Send("test message", "test title", "high")
	if err != nil {
		t.Errorf("Send() error = %v", err)
	}
}

func TestNtfySender_SendWithError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
	}))
	defer server.Close()

	sender := NewNtfySender(server.URL, "")

	err := sender.Send("test message", "test title", "high")
	if err == nil {
		t.Error("Send() expected error, got nil")
	}
}

func BenchmarkAlertFormatter_Format(b *testing.B) {
	formatter := NewAlertFormatter()
	alert := &Alert{
		Labels: map[string]string{
			"alertname": "NodeDown",
			"severity":  "critical",
			"namespace": "monitoring",
			"instance":  "node-01",
		},
		Annotations: map[string]string{
			"summary": "Node is down",
		},
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		formatter.Format(alert)
	}
}

func BenchmarkWebhookHandler_ServeHTTP(b *testing.B) {
	formatter := NewAlertFormatter()
	sender := &MockNtfySender{}
	handler := NewWebhookHandler(formatter, sender)

	body := `{"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"TestAlert","severity":"warning","namespace":"test"},"annotations":{"summary":"Test"}}],"groupLabels":{"alertname":"TestAlert"}}`

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		sender.reset()
		req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, req)
	}
}
