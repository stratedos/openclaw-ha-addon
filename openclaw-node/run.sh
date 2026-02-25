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
SSH_USER=$(jq -r '.ssh_user // empty' "$CONFIG_PATH")

# Validate required config
if [ -z "$GATEWAY_HOST" ] || [ "$GATEWAY_HOST" = "null" ]; then
    echo "ERROR: gateway_host is required. Set it in the addon configuration."
    echo "       Go to Settings → Add-ons → OpenClaw Node → Configuration"
    exit 1
fi

# Persist node state across restarts
export OPENCLAW_STATE_DIR="/data/openclaw"
mkdir -p "$OPENCLAW_STATE_DIR"

# SSH key directory (persisted across restarts)
SSH_DIR="/data/openclaw/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Generate SSH key if it doesn't exist
if [ ! -f "$SSH_DIR/id_ed25519" ]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -C "openclaw-ha-addon"
    echo ""
    echo "=========================================="
    echo "  SSH KEY SETUP REQUIRED"
    echo "=========================================="
    echo "  Add this public key to ${GATEWAY_HOST}:"
    echo ""
    cat "$SSH_DIR/id_ed25519.pub"
    echo ""
    echo "  Run on the gateway host:"
    echo "    echo '$(cat "$SSH_DIR/id_ed25519.pub")' >> ~/.ssh/authorized_keys"
    echo "=========================================="
    echo ""
fi

# Determine connection method
if [ -n "$SSH_USER" ] && [ "$SSH_USER" != "null" ]; then
    # SSH tunnel mode — connect via localhost after tunneling
    LOCAL_PORT=18789
    
    echo "=========================================="
    echo "  OpenClaw Node for Home Assistant"
    echo "=========================================="
    echo "  Gateway:  ${GATEWAY_HOST}:${GATEWAY_PORT} (via SSH tunnel)"
    echo "  SSH User: ${SSH_USER}"
    echo "  Name:     ${DISPLAY_NAME}"
    echo "  Config:   /config/ (mapped rw)"
    echo "  HA API:   available via SUPERVISOR_TOKEN"
    echo "=========================================="
    
    # Start SSH tunnel in background
    echo "Establishing SSH tunnel to ${SSH_USER}@${GATEWAY_HOST}..."
    ssh -f -N -L ${LOCAL_PORT}:127.0.0.1:${GATEWAY_PORT} \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -o ConnectTimeout=10 \
        -i "$SSH_DIR/id_ed25519" \
        "${SSH_USER}@${GATEWAY_HOST}"
    
    echo "SSH tunnel established ✅"
    
    # Connect node to localhost (through tunnel)
    exec openclaw node run \
        --host "127.0.0.1" \
        --port "$LOCAL_PORT" \
        --display-name "$DISPLAY_NAME"
else
    echo "=========================================="
    echo "  OpenClaw Node for Home Assistant"
    echo "=========================================="
    echo "  Gateway:  ${GATEWAY_HOST}:${GATEWAY_PORT} (direct)"
    echo "  Name:     ${DISPLAY_NAME}"
    echo "  Config:   /config/ (mapped rw)"
    echo "  HA API:   available via SUPERVISOR_TOKEN"
    echo "=========================================="
    echo ""
    echo "WARNING: Direct connection requires the gateway to be on localhost"
    echo "         or use TLS. Set ssh_user in config to connect via SSH tunnel."
    echo ""
    
    exec openclaw node run \
        --host "$GATEWAY_HOST" \
        --port "$GATEWAY_PORT" \
        --display-name "$DISPLAY_NAME"
fi
