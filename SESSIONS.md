# Session Log

> Accumulated session summaries. Updated on compaction/end-of-session.
> Newest entries at top.

---

## 2026-05-27 — Chator FRP tunnel + Render deployment

**Goal:** Deploy Chator (Matrix/Element/TURN) server publicly accessible despite ISP blocking all inbound traffic + throttling persistent HTTP/2 outbound.

**Context:** ISP (Russian residential) blocks all inbound TCP/UDP, throttles persistent HTTP/2 (Cloudflare tunnel dropped ~40s), and blocks api.github.com (Codespaces unreachable).

**Approach:** FRP tunnel — lightweight frps (~10MB) on Render free tier (512MB RAM, no CC), frpc locally connects outbound via WebSocket-over-HTTPS. ISP cannot block outbound.

**Files created:**
- `frp/Dockerfile.frps` — frps for Render, entrypoint generates config from `$PORT`
- `frp/Dockerfile.frpc` — frpc with dynamic env-var-based config
- `frp/entrypoint.sh` — generates frps.toml (`bindPort`=`vhostHTTPPort`=`$PORT`)
- `frp/frpc-entrypoint.sh` — generates frpc.toml from `FRP_SERVER`, `AUTH_TOKEN`
- `render.yaml` — Render blueprint
- `docker-compose.yml` — added frpc service (tunnel profile)
- `.env.example` — added `FRP_SERVER`, `FRP_AUTH_TOKEN`
- `.devcontainer/setup.sh` — Codespace auto-config (unused, ISP blocks API)

**Key decisions:**
- frps uses same port for control + HTTP (`bindPort = vhostHTTPPort = $PORT`)
- frpc uses `transport.protocol = "websocket"` + `transport.tls.enable = true` to work through Render's LB
- Local cloudflared kept as QUIC fallback (tunnel profile)
- Caddy `auto_https disable_redirects` for tunnel compatibility

**Status:** Configured and pushed to GitHub. User needs to deploy frps on Render, update `FRP_SERVER` locally, run `docker compose --profile tunnel up -d frpc`.

---

## 2026-05-27 — Initial session: Chator local deployment + ISP blocking analysis

**Goal:** Make Chator server at 192.168.0.10 publicly accessible.

**Analysis:** ISP blocks ALL inbound ports despite UPnP forwarding working (26 rules on router). Cloudflare Tunnel works but HTTP/2 persistent connection throttled (~40s drops). Play with Docker shut down (March 2026). Codespaces created but unreachable (api.github.com blocked).

**Key findings:**
- UPnP router limit: ~28 entries
- Cloudflare Tunnel QUIC might bypass HTTP/2 throttling (untested)
- Free hosting without CC: Render (needs testing), Koyeb (needs CC), Fly.io (needs CC)
- Russian providers (Timeweb) might work but untested

**Decisions:**
- Pivot from UPnP → Cloudflare Tunnel → FRP on Render
- Shrunk TURN relay range 49200→49180, UDP-only to fit router limit
- Caddy port 80 catch-all for tunnel traffic instead of HTTPS redirect
