# Sessions

## 2026-05-29 — Full HTTPS setup, Element Web/Call at chator.duckdns.org

**Goal:** Serve Chator (Matrix + LiveKit) at `chator.duckdns.org` with HTTPS, working chat registration and voice/video calls
**Context:** VPS at 85.209.2.14, Debian 13 Trixie, bare-metal (no Docker). Supabase PostgreSQL pooler. DuckDNS for dynamic DNS.
**Approach:**
- Obtained LE wildcard cert via DNS-01 (certbot-dns-duckdns), cron for DuckDNS auto-update every 5 min
- Fixed nginx to proxy HTTPS → Synapse (port 8009), LiveKit (/livekit → 7880), Element Call (/call/ → static files)
- Changed `server_name` from `localhost` → `chator.duckdns.org` in homeserver.yaml, env, start.sh — required full DB schema reset (dropped 173 tables)
- Configured LiveKit: `use_external_ip: true`, `external_ip: 85.209.2.14`, TURN with local coturn, fixed YAML syntax
- Updated lk-jwt-service to use `ws://localhost:7880` (not render.com tunnel)
- Set coturn realm to `chator.duckdns.org`
- Fixed Element Call asset path corruption (idempotent sed: revert-then-apply in deploy.sh)
- Killed stale coturn process, cleaned up temp files
- Verified: registration open, Element Web works via browser, all endpoints return 200 from external
**Files modified:**
- `deploy/deploy.sh` — Element Call asset fix made idempotent (revert first, then apply)
- `deploy/conf/homeserver.yaml` — server_name, turn_uris
- `docker/livekit.conf` — external IP, TURN, YAML fix
- `deploy/start.sh` — server_name
- `/etc/chator/env` — PUBLIC_IP added
- `/etc/turnserver.conf` — realm
- `/etc/supervisor/supervisord.conf` — LIVEKIT_URL
**Key decisions:**
- DNS-01 over HTTP-01 (port 80 contested; DNS avoids port conflicts)
- Reset DB schema rather than migrate server_name (only test users existed)
- Local coturn + LiveKit instead of render.com tunnel for VoIP
**Status:** done — `https://chator.duckdns.org` serves Element Web with open registration, LiveKit call widget at /call/
**Credentials:**
- Admin: `@admin2:chator.duckdns.org` / `admin2_pass_2026`
- Registration: open with `m.login.dummy` (no email/captcha)
- TURN secret: `chator-test-secret`
**Remaining:** Federation test with matrix.org, actual Element Call browser test (waiting on user)

## 2026-05-29 — Synapse live on Supabase PostgreSQL

**Goal:** Get Synapse running stably on Supabase PostgreSQL via pooler
**Context:** Synapse crashed on startup — collation mismatch (en_US.UTF-8 vs C) + pooler username format
**Approach:**
- Fixed `allow_unsafe_locale` placement: Synapse YAML config level, not psycopg2 args
- Fixed pooler username: `postgres.ukymrxkunsylwiagdowy` (project ref suffix)
- SCPed updated `supabase_db.py`, re-ran it, restarted Chator
- All 7 supervisor processes running, Synapse 1.153.0 healthy
- Registered admin2 user, verified login via Matrix API
**Files modified:**
- `docker/supabase_db.py` — added `allow_unsafe_locale: true` (at database: level, not args)
**Status:** done — full stack operational
**Notes:**
- Admin user `admin2` / `admin2_pass_2026` registered and tested
- Original `admin` user exists but password was mangled by PowerShell interpolation — left as-is
- Synapse health: `curl localhost:8009/health` → OK
- Element Web: serving at port 8008
- Port 8008 → nginx → Synapse port 8009 proxying works

## 2026-05-29 — Pooler username fix for Supabase DB auto-detect

**Goal:** Fix Supabase pooler tenant routing — pooler requires username `postgres.<PROJECT_REF>` not just `postgres`
**Context:** Synapse failed to authenticate via pooler because Supabase pooler routes tenants by suffix in the username (`.ukymrxkunsylwiagdowy`)
**Approach:**
- Extracted `SUPABASE_PROJECT_REF` from the direct endpoint hostname (`db.ukymrxkunsylwiagdowy.supabase.co`)
- Constructed `POOLER_USER = f"{PG_USER}.{SUPABASE_PROJECT_REF}"` (→ `postgres.ukymrxkunsylwiagdowy`)
- Updated `pick_best()` to return `(host, port, name)` so caller knows which endpoint was selected
- Updated `replace_db_section(path, host, port, name)` — uses `POOLER_USER` when `name == "pooler"`, else `PG_USER`
- Fixed `main()` to unpack and pass the `name` through
**Files modified:**
- `docker/supabase_db.py` — added `SUPABASE_PROJECT_REF`, `POOLER_USER`, `name` plumbing through `pick_best` → `replace_db_section` → `main`
**Key decisions:**
- Derived `SUPABASE_PROJECT_REF` from `HOSTS[0]` hostname rather than hardcoding (though both refer to same project)
- Function signature change (add `name` param) rather than re-deriving pooler status from port — cleaner
**Status:** done — script now writes correct username per endpoint

## 2026-05-28 — Docker build fix & full stack verification

**Goal:** Get Docker build to complete and full stack to run
**Context:** Build failed with heredoc syntax error — Dockerfile had CRLF line endings from Windows editing
**Approach:**
- Diagnosed build failure: `set: Illegal option -` caused by `\r` (CR) from CRLF line endings
- Converted Dockerfile to Unix LF using PowerShell `ReadAllText` + regex replace
- Also fixed Docker Desktop DNS issue (IPv6-only DNS was failing) by adding explicit IPv4 DNS to `daemon.json`
- Built successfully (all but 1 layer cached)
- Started `docker compose up -d` with coturn + chator + caddy
- Verified all 7 supervisor processes running and all endpoints responding
**Files modified:**
- `Dockerfile` — line endings CRLF→LF
- `~/.docker/daemon.json` — added `"dns": ["1.1.1.1", "1.0.0.1", "8.8.8.8"]`
**Key decisions:**
- CRLF→LF conversion on Dockerfile was the minimal fix — avoided rewriting heredoc with echo/printf
- DNS fix was needed separately (Docker Desktop uses host DNS which preferred failing IPv6 DNS)
**Status:** done
