# Testing Chator from GitHub Codespaces

This guide explains how to build, run, and test the Chator server from outside
your local network using GitHub Codespaces.

## Quick Start

1. **Open in Codespaces** — from the GitHub repo page, click `Code > Codespaces > Create codespace on master`

2. **Build** (auto-runs via `postCreateCommand` in devcontainer.json):
   ```bash
   docker compose build
   ```

3. **Start services** (auto-runs via `postStartCommand`):
   ```bash
   docker compose up -d
   ```

4. **Test HTTP/Synapse** — open the forwarded port URLs from Codespaces:
   - Port `8008` → `https://8008-<codespace-name>-<hash>.github.dev`
   - Hit `/health` or `/_matrix/client/versions`

5. **Test TURN UDP** — from any external machine:
   ```bash
   TARGET_HOST=<codespace-forwarded-host> bash docker/turn-test/test_udp_codespace.sh
   ```

6. **Test TURN TCP** — from outside:
   ```bash
   TARGET_HOST=<codespace-host> bash docker/turn-test/test_synapse_remote.sh
   ```

7. **Full external verification**:
   ```bash
   python3 docker/turn-test/verify_external.py
   ```

## Port Forwarding

Codespaces forwards these ports automatically:

| Port | Service | Protocol |
|------|---------|----------|
| 8008 | Synapse (Matrix API) | TCP/HTTP |
| 3478 | TURN/STUN | TCP + UDP |
| 3479 | TURN TLS | TCP + UDP |
| 80   | HTTP (Caddy) | TCP |
| 443  | HTTPS (Caddy) | TCP |
| 8448 | Matrix Federation | TCP |

**Note**: UDP forwarding in Codespaces requires the `gh` CLI with `--protocol udp`.

## Testing from External Machine

Once the server is running in Codespaces:

### HTTP (Synapse API)
```bash
curl -s https://8008-<codespace>.github.dev/health
curl -s https://8008-<codespace>.github.dev/_matrix/client/versions
```

### TURN/STUN UDP
```bash
node docker/turn-test/test_turn_allocate.js <codespace-host> 3478
```

### TURN TCP
```bash
# Requires nc or similar
echo "" | nc -w 3 <codespace-host> 3478
```

### Full automated test
```bash
# From the external machine:
TARGET_HOST=<codespace-host> python3 docker/turn-test/verify_external.py
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CHATOR_PUBLIC_URL` | `https://localhost` | Public URL for Synapse |
| `CHATOR_DOMAIN` | `localhost` | Domain for Caddy reverse proxy |
| `COTURN_ENABLED` | `true` | Enable TURN server config |
| `TURN_EXTERNAL_IP` | (auto-detect) | External IP for TURN relay |
| `TARGET_HOST` | `localhost` | Target for remote test scripts |
| `TARGET_PORT` | `3478` | Target port for remote test scripts |
