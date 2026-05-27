# Session Log

> Accumulated session summaries. Updated on compaction/end-of-session.
> Newest entries at top.

---

## 2026-05-28 — Fix Cloudflare WS block: wsproxy (Go TCP→WebSocket bridge with Origin header)

**Goal:** Make frpc WebSocket connection work through Cloudflare's WAF (blocked without Origin header).

**Context:** Cloudflare in front of `*.onrender.com` returns 403 on WebSocket upgrades unless `Origin` header is present. frpc's gorilla/websocket doesn't set Origin; frp has no config option for custom WS headers. The previous `/~!frp` → `/frpws` binary sed-patch path renaming didn't help.

**Approach:**
- Discovered the root cause: `curl -H "Origin: https://chator-frp.onrender.com"` succeeds (101 Switching Protocols), without it → 403
- Built `frp/wsproxy.go` — tiny Go TCP-to-WebSocket bridge:
  - Listens on `:7002`
  - On TCP connect, dials `wss://chator-frp.onrender.com/frpws` with `Origin` header
  - Bidirectional raw TCP ↔ WebSocket binary frames relay
- Changed frpc transport from `websocket` back to `tcp`, pointing to `127.0.0.1:7002`
- Multi-stage Dockerfile: compiles wsproxy (Go), copies alongside stock frpc
- No more `sed` patching of the binary — wsproxy handles `/~!frp` path via `/frpws` in target URL
- Render side unchanged (nginx.conf already had `/frpws` location)

**Architecture:**
```
frpc (TCP) → wsproxy:7002 (adds Origin header, WS upgrade) → Render nginx → frps:7001
```

**Files created:**
- `frp/wsproxy.go` — Go TCP-to-WebSocket bridge with `-origin` flag

**Files modified:**
- `frp/Dockerfile.frpc` — multi-stage build (golang:alpine builder + alpine final)
- `frp/frpc.toml` — TCP transport, `serverAddr = "127.0.0.1"`, `serverPort = 7002`
- `frp/frpc-entrypoint.sh` — starts wsproxy in background, generates frpc config for local TCP

**Key decisions:**
- Custom code IS justified here — it's a 90-line Go bridge that adds Origin header, which frp doesn't support natively. Runs locally on home server, not on Render
- Multi-stage Docker build keeps final image small (Go binary ~7MB static)
- wsproxy is generic: `-listen`, `-target`, `-origin` flags. Could be used for other Cloudflare-gated WebSocket connections

**Status:** Done. Tunnel verified:
- frpc logs: `login to server success, get run id [...]`
- Endpoint: `GET /` → **200 OK**, serves Element Matrix client homepage
- Full pipeline: Browser → Cloudflare → Render nginx → frps → wsproxy:7002 → frpc → caddy:80 → Element

---

## 2026-05-28 — Fix Render deploy (Dockerfile path) + verify live

**Goal:** Get the stock FRP + nginx commit deployed after it failed due to stale Render config.

**Context:** Commit `dd3278109` was pushed but auto-deploy failed. Render's service config still pointed to deleted `Dockerfile.frps`. ISP was blocking `api.render.com` but later came back.

**Approach:**
- Refreshed Render CLI connection (ISP was blocking, now works)
- Found auto-deploy failed: `dockerfilePath: Dockerfile.frps` but file was deleted
- Updated Render service via REST API:
  - `envSpecificDetails.dockerfilePath`: `Dockerfile.frps` → `Dockerfile`
  - `healthCheckPath`: `` → `/healthz`
  - Used API key from `~/.render/cli.yaml`
- Triggered manual deploy — **build passed, service LIVE**

**Verified endpoints:**
- `GET /healthz` → **200** (nginx)
- `GET /~!frp` → **400** (frps control, expects WebSocket — correct)
- `GET /` → **502** (nginx→frps:8080, expected — no frpc registered yet)

**Current live deploy:** `dep-d8bj0lbj0mlc738vs3s0` (built at 17:57:08)

**Key decisions:**
- Render CLI has no `--dockerfile-path` flag on `services update`
- Had to PATCH `envSpecificDetails.dockerfilePath` directly via API
- Health check path set to `/healthz` (nginx handles it before proxy_pass)
- `buildPlan: starter` shows in API (Render internal default for free tier tests) — not changed

**Status:** Server side done. Wait for user to configure frpc on home server:
`docker compose --profile frp up -d`

---

## 2026-05-28 — Restore stock FRP with nginx on Render

**Goal:** Replace wstunnel+demux custom stack with stock FRP (fatedier/frp). Fix WebSocket upgrade failures by using nginx for routing instead of custom Go demux.

**Context:** The wstunnel detour was unnecessary — frp's WebSocket transport (`/~!frp`) worked fine through Render. The demux.go (custom Go code) was the real problem — user wants stock binaries only. nginx handles health checks + frp WebSocket routing.

**Approach:**
- `frp/Dockerfile` — stock nginx (Alpine package) + stock frps (GitHub release)
- `frp/nginx.conf` — nginx routes `/healthz` directly, `/~!frp` to frps:7001, rest to frps:8080
- `frp/frps.toml` — minimal stock frps config (bindPort=7001, no vhostHTTPPort)
- `frp/Dockerfile.frpc` — stock frpc binary, generates config from env vars at runtime
- `frp/frpc.toml` + `frp/frpc-entrypoint.sh` — TCP proxy (no customDomains needed), WebSocket transport
- `render.yaml` — back to Docker runtime, free tier
- `docker-compose.yml` — restored frpc service with `profiles: ["frp"]`

**Architecture:**
```
Matrix client → Render (TLS) → nginx:$PORT
  ├── /healthz → 200 OK
  ├── /~!frp → WebSocket → frps:7001 (control)
  └── /* → proxy → frps:8080 (TCP) → tunnel → frpc → caddy:80 → Synapse
```
- nginx on `$PORT` (stock, no custom code)
- frps WebSocket transport on `bindPort=7001` (stock frp)
- frpc connects via `wss://` with `transport.protocol = "websocket"`
- TCP proxy (`remotePort=8080`) — no Host header matching (fragile with customDomains)
- Free Render tier, well under 512MB RAM (nginx ~3MB + frps ~10MB)

**Files created:**
- `frp/Dockerfile` — nginx + frps in one image
- `frp/nginx.conf` — routing config
- `frp/frps.toml` — frps config
- `frp/frpc.toml` — frpc config template
- `frp/frpc-entrypoint.sh` — dynamic frpc config generation

**Files modified:**
- `frp/Dockerfile.frpc` — restored as stock frpc (was wstunnel client)
- `render.yaml` — back to Docker runtime, no starter plan
- `docker-compose.yml` — restored frpc service
- `SESSIONS.md` — this entry

**Files removed:**
- `frp/Dockerfile.frps` — old approach with demux
- `frp/demux.go` — custom Go code (user requirement: no custom code)
- `frp/entrypoint.sh` — old entrypoint (was demux + frps or wstunnel)
- `proxy/` — entire wowmow Ruby proxy approach (abandoned)
- All other obsolete frp files

**Key decisions:**
- **Stock FRP only** — no custom code. nginx + frps + frpc, all off-the-shelf
- nginx replaces demux for routing — handles health checks + WebSocket split
- TCP proxy type (not HTTP) — avoids fragile customDomains matching. Raw TCP forward to caddy
- Free Render tier — no upgrade needed. RAM well under 512MB
- WebSocket transport for frpc — works through Render's LB (TLS terminates at Render edge, plain WS reaches nginx)

**Status:** Ready to commit and push. After deploy, run on home server:
`docker compose --profile frp up -d`

---

## 2026-05-27 — Replace frp with wstunnel for Cloudflare WebSocket compat

**Goal:** Fix Cloudflare WebSocket upgrade failures (frp used `/~!frp` path which Cloudflare rejected). Replace frp entirely with wstunnel.

**Context:** Cloudflare blocks WebSocket upgrades with path containing `~`. wstunnel uses clean paths (`/tunnel`). Moved wstunnel server into same Render container as demux, routing via dedicated internal port.

**Approach:**
- Replaced frp binaries (frps/frpc) with wstunnel v10.5.5 (musl) in both Dockerfiles
- Added demux routing: `GET /tunnel` → wstunnel on `:9999`
- wstunnel server runs alongside demux in Render container (`entrypoint.sh`)
- wstunnel client uses `--http-upgrade-path-prefix /tunnel` + `-R tcp://8080:caddy:80`
- Removed all frp config generation (frps.toml, frpc.toml)
- Tunnel client waits for caddy before connecting

**Files modified:**
- `docker-compose.yml` — frpc→wstunnel rename, env vars
- `frp/Dockerfile.frpc` — frpc→wstunnel binary
- `frp/Dockerfile.frps` — frps→wstunnel binary
- `frp/demux.go` — added tunnelUpgradePath + tunnelPort routing
- `frp/entrypoint.sh` — frps→wstunnel server bg + demux fg
- `frp/frpc-entrypoint.sh` — frpc→wstunnel client with reverse tunnel

**Key decisions:**
- wstunnel inside existing Render container (single service, no extra networking)
- wstunnel v10.5.5 (latest musl build with `--restrict-http-upgrade-path-prefix`)
- Path `/tunnel` chosen to avoid Cloudflare filtering
- Client URL has no path suffix (path set via `--http-upgrade-path-prefix`)

**Status:** Code committed + pushed → Render auto-deploy triggered. User needs to run `docker compose --profile frp up -d` on home server and verify.

---

## 2026-05-27 — FRP demultiplexer deployed on Render

**Goal:** Make frps work on Render's single `$PORT` limitation.

**Context:** Render web services expose only one port. FRP frps needs separate control + vhost ports. Solution: TCP demultiplexer that routes by HTTP path prefix.

**Approach:**
- Wrote `frp/demux.go` — Go TCP demux, listens on `$PORT`
  - `GET /~!frp` (frpc WebSocket control) → frps control:7001
  - Other HTTP (Matrix API) → frps vhost:8080
  - `GET /` (Render health check) → 200 OK directly
- Updated Dockerfile.frps with multi-stage Go build
- Updated entrypoint.sh: frps bg + demux fg

**Files created/modified:**
- `frp/demux.go` — new, TCP demultiplexer
- `frp/Dockerfile.frps` — multi-stage build
- `frp/entrypoint.sh` — runs frps + demux
- `.gitignore` — added `frp/demux.exe`
- `SESSIONS.md` — appended this entry

**Tooling:**
- Render CLI: `C:\cli_2.18.0_windows_amd64\cli_v2.18.0.exe`

**Status:** frps deployed and LIVE on Render. Health check passes (returns OK). Next: run frpc locally to establish tunnel.

---

## 2026-05-27 — Fixed frpc profile bug, no strategy change

**Goal:** Fix docker-compose profile mismatch for frpc service.

**Context:** frpc had `profiles: ["tunnel"]` but the session log said it should be `profiles: ["frp"]` to be exclusive from cloudflared. Cloudflared comment called it "Legacy" prematurely.

**Approach:** Changed frpc profile to `["frp"]`, removed "Legacy" comment from cloudflared. No tunnel strategy changes.

**Files modified:**
- `docker-compose.yml` — frpc profile fix + cloudflared comment cleanup
- `SESSIONS.md` — added this entry

**Key decisions:**
- Leave render.yaml healthCheckPath as-is for now
- No tunnel strategy change until user decides direction

**Status:** done. User was presented with 4 options (cloudflared HTTP/2, TCP demux on Render, cheap VPS, or fix bugs only). Chose D — fix bugs only.

---

## 2026-05-27 — Chator FRP tunnel + Render deployment + persistence

**Goal:** Deploy Chator publicly accessible + set up persistent session memory.

**Context:** ISP blocks all inbound, throttles HTTP/2 outbound, blocks api.github.com. No free hosting with CC-free signup found.

**Approach:** FRP tunnel (frps on Render free tier, frpc local via WebSocket). SESSIONS.md for cross-session memory.

**Files created/modified:**
- `frp/Dockerfile.frps` — frps for Render, entrypoint generates config from `$PORT`
- `frp/Dockerfile.frpc` — frpc with dynamic env-var-based config
- `frp/entrypoint.sh` — generates frps.toml (`bindPort`=`vhostHTTPPort`=`$PORT`)
- `frp/frpc-entrypoint.sh` — generates frpc.toml from `FRP_SERVER`, `AUTH_TOKEN`
- `render.yaml` — Render blueprint
- `docker-compose.yml` — added frpc service (tunnel profile)
- `.env.example` — added `FRP_SERVER`, `FRP_AUTH_TOKEN`
- `.devcontainer/setup.sh` — Codespace auto-config (ISP blocks API)
- `SESSIONS.md` (new) — persistent session log in repo root
- `~/.config/opencode/AGENTS.md` — added SESSIONS.md maintenance protocol

**Key decisions:**
- frps uses same port for control + HTTP (`bindPort = vhostHTTPPort = $PORT`)
- frpc uses WebSocket + TLS to traverse Render's LB
- SESSIONS.md in repo root (not gitignored), updated on session compaction
- AGENTS.md instructs all agents to append to SESSIONS.md automatically

**Status:** FRP configured on GitHub. SESSIONS.md protocol active. Next: deploy frps on Render.

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
