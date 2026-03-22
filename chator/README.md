# чатор - Messenger for Russian Teens

A Matrix-based chat app built as an alternative to Одноклассники for Russian teens.

**Stack:**
- **Server:** Matrix Synapse (self-hosted on Render)
- **Database:** Supabase PostgreSQL (free tier)
- **Auth:** Dex OIDC (SSO with email/password, LDAP, GitHub, Google)
- **Client:** Element Web (custom branded) + Element mobile apps
- **Voice/Video:** Element Call (Jitsi - free, no setup needed)

---

## Quick Start

### 1. Deploy Matrix Server (Render + Supabase)

**Supabase Setup:**
1. Go to https://supabase.com and create a project
2. Copy your **Connection String** (Pooler mode, Session)
3. You already have: `postgresql://postgres.parolaegtntaamnrxbqr:fuckyouroskomnadzor@aws-1-eu-west-1.pooler.supabase.com:5432/postgres`

**Render Setup:**
1. Go to https://render.com and create a new **Web Service**
2. Connect your GitHub repo with these files
3. Configure:
   - **Name:** `chator-matrix`
   - **Region:** Frankfurt (closest to Russia)
   - **Branch:** `main`
   - **Root Directory:** `chator/matrix`
   - **Runtime:** `Docker`
   - **Instance Type:** Starter ($7/mo)

4. **Environment Variables** (add in Render dashboard):
   ```
   SYNAPSE_SERVER_NAME=chator.k.vu
   SYNAPSE_REPORT_STATS=yes
   SUPABASE_DB_HOST=aws-1-eu-west-1.pooler.supabase.com
   SUPABASE_DB_USER=postgres.parolaegtntaamnrxbqr
   SUPABASE_DB_PASSWORD=fuckyouroskomnadzor
   SUPABASE_DB_NAME=postgres
   ```

5. Deploy!

**DNS Setup:**
In your domain registrar for `k.vu`:
```
Type    Name                Value
A       chator.k.vu         [Render IP from dashboard]
```

**Keep Server Awake:**
Render spins down after 15 min. Set up UptimeRobot (free):
- URL: `https://chator.k.vu/_matrix/client/versions`
- Check interval: 5 minutes

### 2. Deploy Element Web (Custom Branded)

**Option A: Static Site on Render (Free)**
1. New **Static Site** on Render
2. Root directory: `chator/element-web`
3. Custom domain: `app.chator.k.vu`
4. Done!

**Option B: Use Official Element**
Tell users to:
1. Download Element from https://element.io/get-started
2. On login, click "Edit" next to server
3. Enter: `https://chator.k.vu`

### 3. Register First User

After server is running:

```bash
# Via Render shell (in dashboard)
curl -X POST 'https://chator.k.vu/_synapse/admin/v1/register' \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "uggan",
    "password": "YOUR_SECURE_PASSWORD",
    "admin": true
  }'
```

Then disable public registration in `homeserver.yaml`:
```yaml
enable_registration: false
```

### 4. Add Your Logo

Your logo is at: https://nopaste.net/chator

1. Download it
2. Convert to SVG: https://vectorizer.ai
3. Save as `chator/element-web/chator-logo.svg`
4. Update `element-web/config.json` branding.logo path

---

## Features

✅ **Free voice/video calls** - Element Call (Jitsi)
✅ **Mobile apps** - Element iOS/Android
✅ **End-to-end encryption** - Matrix protocol
✅ **Self-hosted** - Full control
✅ **Russian-friendly** - Default language RU
✅ **Custom branding** - чатор colors and logo
✅ **Bridges later** - Can bridge to Telegram, VK, etc.

---

## Costs

| Service | Cost | Notes |
|---------|------|-------|
| Render (Matrix) | $7/mo | Starter instance |
| Supabase | Free | 1GB PostgreSQL |
| Element Web | Free | Static hosting |
| Element Call | Free | Jitsi servers |
| Domain (k.vu) | Already owned | - |
| **Total** | **~$7/mo** | Can handle hundreds of users |

---

## Next Steps

1. **Deploy server** on Render
2. **Deploy Dex** for SSO (see `dex/README.md`)
3. **Test login** with Element (OIDC SSO)
4. **Add logo** to Element Web
5. **Invite beta users** (Russian teens)
6. **Build mobile apps** (optional, see `mobile/README.md`)
7. **Add bridges** (Telegram, VK) if needed
8. **Scale** when you have users

---

## Support

- Matrix docs: https://matrix.org/docs/
- Synapse config: https://matrix-org.github.io/synapse/latest/
- Element config: https://github.com/vector-im/element-web#configuration
- чатор logo: https://nopaste.net/chator

Удачи! 🥞
