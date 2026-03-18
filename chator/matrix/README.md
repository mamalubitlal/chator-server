# чатор Matrix Server - Deploy on Render + Supabase

## Your Setup (Pre-configured)

- **Domain:** `chator.k.vu`
- **Database:** Supabase PostgreSQL (pooler, Session mode)
- **Voice/Video:** Element Call via Jitsi (FREE)
- **Region:** Frankfurt (closest to Russia)

---

## Deploy Steps

### 1. Render Web Service

1. Go to https://render.com → New → **Web Service**
2. Connect your GitHub repo
3. Configure:
   - **Name:** `chator-matrix`
   - **Region:** Frankfurt
   - **Branch:** `main`
   - **Root Directory:** `chator/matrix`
   - **Runtime:** `Docker`
   - **Instance Type:** Starter ($7/mo)

### 2. Environment Variables

Add these in Render dashboard:

```
SYNAPSE_SERVER_NAME=chator.k.vu
SYNAPSE_REPORT_STATS=yes
SUPABASE_DB_HOST=aws-1-eu-west-1.pooler.supabase.com
SUPABASE_DB_USER=postgres.parolaegtntaamnrxbqr
SUPABASE_DB_PASSWORD=fuckyouroskomnadzor
SUPABASE_DB_NAME=postgres
```

### 3. DNS

In your `k.vu` domain settings:

```
Type    Name        Value
A       chator      [Render IP from dashboard]
```

### 4. Deploy & Wait

- Build takes ~5-10 minutes
- Check logs in Render dashboard
- Server is healthy when you see: `Synapse is now ready`

### 5. Keep Alive (IMPORTANT!)

Render spins down after 15 min. Set up **UptimeRobot** (free):

1. Go to https://uptimerobot.com
2. Add monitor: `https://chator.k.vu/_matrix/client/versions`
3. Interval: 5 minutes
4. Type: HTTPS

### 6. Register Admin User

```bash
curl -X POST 'https://chator.k.vu/_synapse/admin/v1/register' \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "uggan",
    "password": "YOUR_STRONG_PASSWORD",
    "admin": true
  }'
```

Then **disable public registration** by updating `homeserver.yaml`:
```yaml
enable_registration: false
```
(Or set via environment variable)

---

## Test It

1. Go to https://app.element.io (or your custom Element)
2. Click **Edit** next to server
3. Enter: `https://chator.k.vu`
4. Login with your admin account

---

## Voice/Video Calls

**Already configured!** Element Call uses Jitsi servers (free):

- 1-on-1 calls: Click phone/video icon in room
- Group calls: Click "Start Call" → others can join
- No setup needed on your end

---

## Admin Commands

**List users:**
```bash
curl 'https://chator.k.vu/_synapse/admin/v2/users' \
  -H 'Authorization: Bearer YOUR_ADMIN_TOKEN'
```

**Delete user:**
```bash
curl -X DELETE 'https://chator.k.vu/_synapse/admin/v1/users/@baduser:chator.k.vu' \
  -H 'Authorization: Bearer YOUR_ADMIN_TOKEN'
```

**Get your admin token:**
- Login to Element
- Settings → Help & About → Click "Access Token"

---

## Troubleshooting

**Can't connect?**
- Check Render logs
- Verify DNS propagated (use https://dnschecker.org)
- Ensure UptimeRobot is pinging

**Database errors?**
- Supabase pooler is Session mode (not Transaction)
- Check credentials match `.env.example`

**High RAM?**
- Starter plan has 512MB - should handle ~100 users
- Upgrade to Standard ($15/mo) if needed

---

## Costs

| Item | Cost |
|------|------|
| Render (Starter) | $7/mo |
| Supabase | Free (1GB) |
| Element Call | Free (Jitsi) |
| **Total** | **$7/mo** |

---

Ready to deploy? 🥞
