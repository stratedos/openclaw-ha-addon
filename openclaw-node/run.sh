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
GATEWAY_TOKEN=$(jq -r '.gateway_token // empty' "$CONFIG_PATH")
DISPLAY_NAME=$(jq -r '.display_name' "$CONFIG_PATH")
SSH_USER=$(jq -r '.ssh_user // empty' "$CONFIG_PATH")
TLS=$(jq -r '.tls // false' "$CONFIG_PATH")
TLS_FINGERPRINT=$(jq -r '.tls_fingerprint // empty' "$CONFIG_PATH")

# Validate required config
if [ -z "$GATEWAY_HOST" ] || [ "$GATEWAY_HOST" = "null" ]; then
    echo "ERROR: gateway_host is required. Set it in the addon configuration."
    exit 1
fi

# Persist node state across restarts
export OPENCLAW_STATE_DIR="/data/openclaw"
mkdir -p "$OPENCLAW_STATE_DIR"

# Resolve SUPERVISOR_TOKEN — s6 stores it in container_environment files
# With init:false, it's not automatically exported as an env var
if [ -z "$SUPERVISOR_TOKEN" ] && [ -f /run/s6/container_environment/SUPERVISOR_TOKEN ]; then
    SUPERVISOR_TOKEN=$(cat /run/s6/container_environment/SUPERVISOR_TOKEN)
fi

# Also check HASSIO_TOKEN (legacy name)
if [ -z "$SUPERVISOR_TOKEN" ] && [ -f /run/s6/container_environment/HASSIO_TOKEN ]; then
    SUPERVISOR_TOKEN=$(cat /run/s6/container_environment/HASSIO_TOKEN)
fi

# Save it so exec'd commands can access it
if [ -n "$SUPERVISOR_TOKEN" ]; then
    echo "$SUPERVISOR_TOKEN" > /tmp/.supervisor_token
    chmod 600 /tmp/.supervisor_token
    echo "Supervisor API token: available ✅"
else
    echo "WARNING: SUPERVISOR_TOKEN not found — ha-api commands won't work"
fi

# Create a helper script that wraps `ha` CLI via the Supervisor REST API
cat > /usr/local/bin/ha-api <<'HAEOF'
#!/usr/bin/env bash
# Wrapper to call HA Supervisor API (replacement for `ha` CLI in addon containers)
TOKEN=$(cat /tmp/.supervisor_token 2>/dev/null)
if [ -z "$TOKEN" ]; then
    echo "ERROR: SUPERVISOR_TOKEN not available"
    exit 1
fi
ENDPOINT="${1:-}"
METHOD="${2:-GET}"
shift 2 2>/dev/null || true
case "$ENDPOINT" in
    core/restart)  curl -sf -X POST -H "Authorization: Bearer $TOKEN" http://supervisor/core/api/services/homeassistant/restart ;;
    core/stop)     curl -sf -X POST -H "Authorization: Bearer $TOKEN" http://supervisor/core/api/services/homeassistant/stop ;;
    core/check)    curl -sf -X POST -H "Authorization: Bearer $TOKEN" http://supervisor/core/api/config/core/check ;;
    core/info)     curl -sf -H "Authorization: Bearer $TOKEN" http://supervisor/core/info ;;
    host/info)     curl -sf -H "Authorization: Bearer $TOKEN" http://supervisor/host/info ;;
    host/reboot)   curl -sf -X POST -H "Authorization: Bearer $TOKEN" http://supervisor/host/reboot ;;
    supervisor/info) curl -sf -H "Authorization: Bearer $TOKEN" http://supervisor/supervisor/info ;;
    addons)        curl -sf -H "Authorization: Bearer $TOKEN" http://supervisor/addons ;;
    backups/new)   curl -sf -X POST -H "Authorization: Bearer $TOKEN" http://supervisor/backups/new/full ;;
    *)             curl -sf -H "Authorization: Bearer $TOKEN" "http://supervisor${ENDPOINT}" ;;
esac
HAEOF
chmod +x /usr/local/bin/ha-api

# Write gateway config for the node to read
# The node reads token from its config file at $OPENCLAW_STATE_DIR/openclaw.json
if [ -n "$GATEWAY_TOKEN" ]; then
    # Read existing config or start fresh
    if [ -f "$OPENCLAW_STATE_DIR/openclaw.json" ]; then
        EXISTING=$(cat "$OPENCLAW_STATE_DIR/openclaw.json")
    else
        EXISTING="{}"
    fi
    
    # Update gateway auth token
    echo "$EXISTING" | jq --arg token "$GATEWAY_TOKEN" '
        .gateway.auth.mode = "token" |
        .gateway.auth.token = $token
    ' > "$OPENCLAW_STATE_DIR/openclaw.json"
fi

# SSH key directory (persisted across restarts)
SSH_DIR="/data/openclaw/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Determine connection method
if [ -n "$SSH_USER" ] && [ "$SSH_USER" != "null" ]; then
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
        echo "After adding the key, restart this addon."
        # Don't exit — let it try and fail, user will see the SSH error
    fi

    LOCAL_PORT=18789
    
    echo "=========================================="
    echo "  OpenClaw Node for Home Assistant"
    echo "=========================================="
    echo "  Gateway:  ${GATEWAY_HOST}:${GATEWAY_PORT} (via SSH tunnel)"
    echo "  SSH User: ${SSH_USER}"
    echo "  Token:    ${GATEWAY_TOKEN:+(set)}"
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
    
    # Build TLS args
    TLS_ARGS=""
    if [ "$TLS" = "true" ]; then
        TLS_ARGS="--tls"
        if [ -n "$TLS_FINGERPRINT" ] && [ "$TLS_FINGERPRINT" != "null" ]; then
            TLS_ARGS="$TLS_ARGS --tls-fingerprint $TLS_FINGERPRINT"
        fi
    fi
    
    # Connect node to localhost (through tunnel)
    exec openclaw node run \
        --host "127.0.0.1" \
        --port "$LOCAL_PORT" \
        --display-name "$DISPLAY_NAME" \
        $TLS_ARGS
else
    echo "=========================================="
    echo "  OpenClaw Node for Home Assistant"
    echo "=========================================="
    echo "  Gateway:  ${GATEWAY_HOST}:${GATEWAY_PORT} (direct)"
    echo "  Token:    ${GATEWAY_TOKEN:+(set)}"
    echo "  Name:     ${DISPLAY_NAME}"
    echo "  Config:   /config/ (mapped rw)"
    echo "  HA API:   available via SUPERVISOR_TOKEN"
    echo "=========================================="
    
    # Build TLS args
    TLS_ARGS=""
    if [ "$TLS" = "true" ]; then
        TLS_ARGS="--tls"
        if [ -n "$TLS_FINGERPRINT" ] && [ "$TLS_FINGERPRINT" != "null" ]; then
            TLS_ARGS="$TLS_ARGS --tls-fingerprint $TLS_FINGERPRINT"
        fi
    fi
    
    exec openclaw node run \
        --host "$GATEWAY_HOST" \
        --port "$GATEWAY_PORT" \
        --display-name "$DISPLAY_NAME" \
        $TLS_ARGS
fi
