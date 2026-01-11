package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

type Alert struct {
	Status      string            `json:"status"`
	Labels      map[string]string `json:"labels"`
	Annotations map[string]string `json:"annotations"`
	StartsAt    time.Time         `json:"startsAt"`
	EndsAt      time.Time         `json:"endsAt"`
}

type AlertData struct {
	Status      string            `json:"status"`
	Alerts      []Alert           `json:"alerts"`
	GroupLabels map[string]string `json:"groupLabels"`
}

var (
	ntfyURL    = getEnv("NTFY_URL", "https://ntfy.sh/lTw2Yxq33ICYDPpX")
	ntfyToken  = getEnv("NTFY_TOKEN", "")
	httpClient = &http.Client{Timeout: 10 * time.Second}
)

func getEnv(key, defaultValue string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultValue
}

type AlertFormatter struct{}

func NewAlertFormatter() *AlertFormatter {
	return &AlertFormatter{}
}

func (f *AlertFormatter) Format(alert *Alert) string {
	emoji := "⚪"
	switch strings.ToLower(alert.Labels["severity"]) {
	case "critical":
		emoji = "🔴"
	case "warning":
		emoji = "🟡"
	case "info":
		emoji = "🔵"
	}

	name := alert.Labels["alertname"]
	if name == "" {
		name = "Unknown"
	}

	summary := alert.Annotations["summary"]
	if summary == "" {
		summary = "No description"
	}

	namespace := alert.Labels["namespace"]
	if namespace == "" {
		namespace = alert.Labels["exported_namespace"]
	}
	if namespace == "" {
		namespace = "unknown"
	}

	instance := alert.Labels["instance"]
	if instance == "" {
		instance = alert.Labels["pod"]
	}
	if instance == "" {
		instance = "unknown"
	}

	return fmt.Sprintf("%s %s: %s (%s/%s)", emoji, name, summary, namespace, instance)
}

type NtfySenderInterface interface {
	Send(message, title, priority string) error
}

type NtfySender struct {
	url   string
	token string
}

func NewNtfySender(url, token string) *NtfySender {
	return &NtfySender{url: url, token: token}
}

func (s *NtfySender) Send(message, title, priority string) error {
	payload := map[string]string{
		"message":  message,
		"title":    title,
		"priority": priority,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal JSON: %w", err)
	}

	req, err := http.NewRequest("POST", s.url, strings.NewReader(string(body)))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if s.token != "" {
		req.Header.Set("Authorization", "Bearer "+s.token)
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("ntfy returned status %d", resp.StatusCode)
	}

	return nil
}

type WebhookHandler struct {
	formatter *AlertFormatter
	sender    NtfySenderInterface
}

func NewWebhookHandler(formatter *AlertFormatter, sender NtfySenderInterface) *WebhookHandler {
	return &WebhookHandler{
		formatter: formatter,
		sender:    sender,
	}
}

func (h *WebhookHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if r.URL.Path != "/webhook" {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}

	var data AlertData
	if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	if len(data.Alerts) == 0 {
		w.WriteHeader(http.StatusOK)
		return
	}

	status := data.Status
	alertName := data.GroupLabels["alertname"]
	if alertName == "" && len(data.Alerts) > 0 {
		alertName = data.Alerts[0].Labels["alertname"]
	}

	var title, priority string
	if status == "firing" {
		title = fmt.Sprintf("Alert: %s", alertName)
		priority = "high"
	} else {
		title = fmt.Sprintf("Resolved: %s", alertName)
		priority = "default"
	}

	var messages []string
	for _, alert := range data.Alerts {
		messages = append(messages, h.formatter.Format(&alert))
	}

	message := strings.Join(messages, "\n")

	if err := h.sender.Send(message, title, priority); err != nil {
		log.Printf("failed to send ntfy: %v", err)
		http.Error(w, "failed to send", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
}

func main() {
	formatter := NewAlertFormatter()
	sender := NewNtfySender(ntfyURL, ntfyToken)
	handler := NewWebhookHandler(formatter, sender)

	mux := http.NewServeMux()
	mux.Handle("/webhook", handler)

	log.Printf("Starting alert-webhook on :5000")
	if err := http.ListenAndServe(":5000", mux); err != nil {
		log.Fatal(err)
	}
}
