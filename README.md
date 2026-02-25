# OpenClaw Node for Home Assistant

A lightweight Home Assistant add-on that runs an [OpenClaw](https://openclaw.ai) headless node, connecting to your existing gateway.

## What it does

- Runs an OpenClaw node inside HA OS
- Connects to your existing OpenClaw gateway (not a new gateway)
- Gives OpenClaw access to `/config/` so it can edit `configuration.yaml`, automations, etc.
- **All commands go through the exec approval flow** — you approve/deny every action in Discord/Telegram

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**
2. Click the **⋮** menu (top right) → **Repositories**
3. Add this repository URL: `https://github.com/stratedos/openclaw-ha-addon`
4. Find "OpenClaw Node" in the store and install
5. Configure the gateway host/port in the addon settings
6. Start the addon — it will appear as a pending node in your gateway
7. Approve the pairing in OpenClaw

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `gateway_host` | *(required)* | IP/hostname of your OpenClaw gateway |
| `gateway_port` | `18789` | Gateway WebSocket port |
| `display_name` | `Home Assistant` | How this node appears in OpenClaw |
| `ssh_user` | *(optional)* | SSH username on gateway host for secure tunnel |

## Mapped directories

| Path | Access | Contents |
|------|--------|----------|
| `/config/` | Read/Write | HA configuration (configuration.yaml, automations, etc.) |
| `/media/` | Read/Write | HA media files |
| `/share/` | Read/Write | Shared addon storage |
| `/ssl/` | Read only | SSL certificates |
| `/backup/` | Read only | HA backups |

## Security

Every command executed on this node goes through OpenClaw's exec approval system. You'll see approval requests in your configured channel (Discord, Telegram, etc.) and can approve or deny each one.
