# Dex OIDC for чатор

OpenID Connect authentication provider for Matrix Synapse using [Dex](https://dexidp.io/).

## What is Dex?

Dex is an identity service that uses OpenID Connect (OIDC) to provide authentication for other applications. It acts as a bridge between your app (Matrix Synapse) and identity providers.

**Why Dex?**
- Single sign-on (SSO) for Matrix
- Support for multiple auth methods (password, LDAP, GitHub, Google, etc.)
- Standards-based (OIDC/OAuth2)
- Self-hosted, full control

---

## Quick Setup (Free Tier - No DNS Required)

### Step 1: Generate Password Hash (Do this locally!)

Since you can't access Render shell, generate the password hash on your computer:

**Option A: Using Docker (Recommended)**
```bash
docker run --rm ghcr.io/dexidp/dex:latest dex password hash YOURPASSWORD
```

**Option B: Using htpasswd (if you have Apache tools)**
```bash
htpasswd -nbB admin YOURPASSWORD
```

**Option C: Online generator**
Go to https://bcrypt-generator.com/ and generate a bcrypt hash (rounds: 10)

**Save the output!** It will look like:
```
$2a$10$2b2c9e3b8f8e8c8d8e8f8g8h8i8j8k8l8m8n8o8p8q8r8s8t8u8v
```

---

### Step 2: Deploy Dex on Render

1. Go to https://render.com and log in
2. Click **New +** → **Web Service**
3. Connect your GitHub repo: `mamalubitlal/chator-server`
4. Configure:
   - **Name:** `chator-auth`
   - **Region:** Frankfurt (closest to Russia)
   - **Branch:** `main`
   - **Root Directory:** `chator/dex`
   - **Runtime:** Docker
   - **Instance Type:** **Starter (Free)** ✨

5. **Environment Variables** (click "Advanced" → "Add Environment Variable"):

   | Key | Value | Notes |
   |-----|-------|-------|
   | `DEX_ISSUER` | `https://chator-auth.onrender.com` | Will be auto-filled after deploy |
   | `DEX_CLIENT_SECRET` | `matrix-synapse-secret-change-me` | Make this random! |
   | `SYNAPSE_URL` | `https://chator-matrix.onrender.com` | Your Synapse URL |
   | `DEX_STATIC_PASSWORD_EMAIL` | `admin@chator.local` | Your admin email |
   | `DEX_STATIC_PASSWORD_USERNAME` | `admin` | Your admin username |
   | `DEX_STATIC_PASSWORD_HASH` | `$2a$10$...` | **Paste the hash from Step 1** |

6. Click **Create Web Service**

> **Important:** After first deploy, Render will show you the actual URL (e.g., `https://chator-auth-xyz.onrender.com`). Update `DEX_ISSUER` and `SYNAPSE_URL` with the real URLs, then redeploy!

---

### Step 3: Update Synapse Config

Add these env vars to your **Matrix Synapse** Render service:

| Key | Value |
|-----|-------|
| `DEX_ISSUER` | `https://chator-auth.onrender.com` |
| `DEX_CLIENT_ID` | `matrix-synapse` |
| `DEX_CLIENT_SECRET` | `matrix-synapse-secret-change-me` |

Restart Synapse: Render Dashboard → Manual Deploy → **Restart**

---

### Step 4: Test Login

1. Wait for Dex to deploy (green checkmark)
2. Open your Element Web URL
3. Click "Sign In"
4. Should see SSO button for "чатор Login"
5. Login with:
   - **Email:** `admin@chator.local` (or what you set)
   - **Password:** The password you hashed in Step 1

---

## Adding More Users

Since you can't edit files on Render, you have two options:

### Option A: Add to config.yaml (Commit to Git)

Edit `chator/dex/config.yaml` locally:

```yaml
connectors:
- type: mockPasswordDB
  id: logins
  name: Email
  config:
    usernames:
    - email: "admin@chator.local"
      password: "$2a$10$..."  # Hash 1
      username: "admin"
      userID: "1"
    - email: "user2@chator.local"
      password: "$2a$10$..."  # Hash 2
      username: "user2"
      userID: "2"
```

Commit and push - Render will auto-deploy!

### Option B: Use Multiple Env Vars (Advanced)

Modify `docker-entrypoint.sh` to support multiple users via env vars. For now, Option A is simpler.

---

## Connectors (Advanced)

Dex supports multiple authentication backends. Add these to `config.yaml`:

### GitHub OAuth

```yaml
connectors:
- type: github
  id: github
  name: GitHub
  config:
    clientID: $GITHUB_CLIENT_ID
    clientSecret: $GITHUB_CLIENT_SECRET
    redirectURI: https://chator-auth.onrender.com/callback
    org: your-org  # Optional: restrict to org members
```

### Google OAuth

```yaml
connectors:
- type: google
  id: google
  name: Google
  config:
    clientID: $GOOGLE_CLIENT_ID
    clientSecret: $GOOGLE_CLIENT_SECRET
    redirectURI: https://chator-auth.onrender.com/callback
    hostedDomains:
    - chator.k.vu  # Optional: restrict to domain
```

### LDAP/Active Directory

```yaml
connectors:
- type: ldap
  id: ldap
  name: LDAP
  config:
    host: ldap.example.com:636
    bindDN: cn=admin,dc=example,dc=com
    bindPW: password
    userSearch:
      baseDN: ou=users,dc=example,dc=com
      username: uid
      emailAttr: mail
      nameAttr: cn
```

See full connector docs: https://dexidp.io/docs/connectors/

---

## Storage Options

### SQLite (Default - Free Tier)
```yaml
storage:
  type: sqlite3
  config:
    file: /var/dex/dex.db
```

Good for testing and small deployments (< 100 users). Data persists in the container.

### PostgreSQL (Production)
```yaml
storage:
  type: postgres
  config:
    host: db.chator.k.vu
    port: 5432
    database: dex
    user: dex
    password: $DEX_DB_PASSWORD
```

---

## Testing

### 1. Check Dex Health
```bash
curl https://chator-auth.onrender.com/healthz
# Should return: OK
```

### 2. Test OIDC Discovery
```bash
curl https://chator-auth.onrender.com/.well-known/openid-configuration
```

### 3. Login via Matrix
1. Open Element Web
2. Click "Sign In"
3. Should see "чатор Login" button
4. Login with Dex credentials

---

## Troubleshooting

### "Invalid redirect_uri"
Ensure the redirect URI in Dex config matches Synapse callback:
```yaml
redirectURIs:
- '${SYNAPSE_URL}/_synapse/client/oidc/callback'
```

### "Client authentication failed"
Check `client_id` and `client_secret` match in both Dex and Synapse configs.

### "User mapping failed"
Ensure OIDC claims (`preferred_username`, `email`, `name`) are returned by Dex. Check Dex logs in Render dashboard.

### "Issuer mismatch"
Make sure `DEX_ISSUER` env var matches the actual Render URL.

### "Invalid password hash"
Regenerate the hash with:
```bash
docker run --rm ghcr.io/dexidp/dex:latest dex password hash YOURPASSWORD
```

---

## Environment Variables Reference

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `DEX_ISSUER` | Yes | Public URL of Dex service | `https://chator-auth.onrender.com` |
| `DEX_CLIENT_SECRET` | Yes | Shared secret with Synapse | `matrix-synapse-secret-change-me` |
| `SYNAPSE_URL` | Yes | URL of Matrix Synapse | `https://chator-matrix.onrender.com` |
| `DEX_STATIC_PASSWORD_HASH` | Yes | Bcrypt hash of admin password | `$2a$10$...` |
| `DEX_STATIC_PASSWORD_EMAIL` | No | Admin email | `admin@chator.local` |
| `DEX_STATIC_PASSWORD_USERNAME` | No | Admin username | `admin` |

---

## Security Notes

- 🔒 **Always use HTTPS** (Render provides this automatically)
- 🔑 **Use strong secrets** - change `matrix-synapse-secret-change-me` to a random string
- 🔐 **Use strong passwords** - generate bcrypt hashes with 10+ rounds
- 🛡️ **Rate limiting** - Render has basic DDoS protection
- 📝 **Monitor logs** in Render dashboard (Logs tab)

---

## Resources

- Dex Docs: https://dexidp.io/docs/
- Dex GitHub: https://github.com/dexidp/dex
- Synapse OIDC: https://matrix-org.github.io/synapse/latest/openid.html
- OIDC Spec: https://openid.net/connect/
- bcrypt Generator: https://bcrypt-generator.com/

---

**чатор** - Secure, self-hosted messaging for Russian teens 🥞
