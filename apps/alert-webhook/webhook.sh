#!/bin/bash

NTFY_URL="${NTFY_URL:-https://ntfy.sh/lTw2Yxq33ICYDPpX}"
NTFY_TOKEN="${NTFY_TOKEN:-}"

send_ntfy() {
    local message="$1"
    local title="$2"
    local priority="$3"

    local data="{\"message\": \"$message\""
    [[ -n "$title" ]] && data="$data, \"title\": \"$title\""
    [[ -n "$priority" ]] && data="$data, \"priority\": \"$priority\""
    data="$data}"

    local headers="Content-Type: application/json"
    [[ -n "$NTFY_TOKEN" ]] && headers="$headers\nAuthorization: Bearer $NTFY_TOKEN"

    curl -s -H "$headers" -d "$data" "$NTFY_URL" >/dev/null
}

format_alert() {
    local alert="$1"

    local status=$(echo "$alert" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    local name=$(echo "$alert" | grep -o '"alertname":"[^"]*"' | cut -d'"' -f4)
    local severity=$(echo "$alert" | grep -o '"severity":"[^"]*"' | cut -d'"' -f4)
    local summary=$(echo "$alert" | grep -o '"summary":"[^"]*"' | cut -d'"' -f4)
    local namespace=$(echo "$alert" | grep -o '"namespace":"[^"]*"' | cut -d'"' -f4)
    [[ -z "$namespace" ]] && namespace=$(echo "$alert" | grep -o '"exported_namespace":"[^"]*"' | cut -d'"' -f4)
    [[ -z "$namespace" ]] && namespace="unknown"
    local instance=$(echo "$alert" | grep -o '"instance":"[^"]*"' | cut -d'"' -f4)
    [[ -z "$instance" ]] && instance=$(echo "$alert" | grep -o '"pod":"[^"]*"' | cut -d'"' -f4)
    [[ -z "$instance" ]] && instance="unknown"

    case "$severity" in
        critical) emoji="🔴" ;;
        warning)  emoji="🟡" ;;
        info)     emoji="🔵" ;;
        *)        emoji="⚪" ;;
    esac

    echo "${emoji} *${name}*"
    echo "📝 ${summary}"
    echo "📍 ${namespace} | ${instance}"
}

webhook_handler() {
    local data
    data=$(cat)

    local status=$(echo "$data" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    local alert_name=$(echo "$data" | grep -o '"alertname":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ "$status" == "firing" ]]; then
        title="Alert: ${alert_name}"
        priority="high"
    else
        title="Resolved: ${alert_name}"
        priority="default"
    fi

    local messages=()
    local alerts=$(echo "$data" | grep -o '"status":"firing"[^}]*}[^}]*' || echo "$data")
    local alert_count=$(echo "$data" | grep -o '"status":"firing"' | wc -l)

    if [[ $alert_count -eq 0 && "$status" != "firing" ]]; then
        alert_count=$(echo "$data" | grep -o '"status":"resolved"' | wc -l)
    fi

    local i=0
    while [[ $i -lt $alert_count ]]; do
        local alert=$(echo "$data" | grep -o '{[^}]*"status":"[^"]*"[^}]*}' | head -n $((i + 1)) | tail -n 1)
        if [[ -n "$alert" ]]; then
            messages+= "$(format_alert "$alert")"
        fi
        i=$((i + 1))
    done

    if [[ ${#messages[@]} -eq 0 ]]; then
        messages+= "$(format_alert "$data")"
    fi

    local message=$(IFS=$'\n'; echo "${messages[*]}")
    send_ntfy "$message" "$title" "$priority"
}

echo "Starting alert-webhook on :5000"

while true; do
    nc -l -p 5000 -q 1 | webhook_handler
done
