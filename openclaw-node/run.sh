#!/usr/bin/env bash
set -e

# Read config from HA addon options
CONFIG_PATH="/data/options.json"

if [ ! -f "$CONFIG_PATH" ]; then
    echo "ERROR: Options file not found at $CONFIG_PATH"
    exit 1
fi

GATEWAY_HOST=$(jq -r '.gateway_host' "$CONFIG_PATH")
GATEWAY_PORT=$(jq -r '.gateway_port' "$CONFIG_PATH")
DISPLAY_NAME=$(jq -r '.display_name' "$CONFIG_PATH")
USE_TLS=$(jq -r '.use_tls // false' "$CONFIG_PATH")

# Validate required config
if [ -z "$GATEWAY_HOST" ] || [ "$GATEWAY_HOST" = "null" ]; then
    echo "ERROR: gateway_host is required. Set it in the addon configuration."
    echo "       Go to Settings → Add-ons → OpenClaw Node → Configuration"
    exit 1
fi

echo "=========================================="
echo "  OpenClaw Node for Home Assistant"
echo "=========================================="
echo "  Gateway:  ${GATEWAY_HOST}:${GATEWAY_PORT}"
echo "  TLS:      ${USE_TLS}"
echo "  Name:     ${DISPLAY_NAME}"
echo "  Config:   /config/ (mapped rw)"
echo "  HA API:   available via SUPERVISOR_TOKEN"
echo "=========================================="

# Persist node state across restarts
export OPENCLAW_STATE_DIR="/data/openclaw"
mkdir -p "$OPENCLAW_STATE_DIR"

# Build command
CMD=(openclaw node run
    --host "$GATEWAY_HOST"
    --port "$GATEWAY_PORT"
    --display-name "$DISPLAY_NAME"
)

if [ "$USE_TLS" = "true" ]; then
    CMD+=(--tls)
fi

# Run the node (foreground, will auto-reconnect)
exec "${CMD[@]}"
