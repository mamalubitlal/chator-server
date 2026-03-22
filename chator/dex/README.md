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

### 1. Deploy Dex on Render

**Render Setup:**
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
   ```
   DEX_ISSUER=https://chator-auth.onrender.com
   DEX_CLIENT_SECRET=matrix-synapse-secret-change-me
   SYNAPSE_URL=https://chator-matrix.onrender.com
   ```
   
   > **Note:** Replace URLs with your actual Render URLs after deployment!

6. Click **Create Web Service**

### 2. Update Synapse Config

Add these env vars to your **Matrix Synapse** Render service:

```
DEX_ISSUER=https://chator-auth.onrender.com
DEX_CLIENT_ID=matrix-synapse
DEX_CLIENT_SECRET=matrix-synapse-secret-change-me
```

Restart Synapse (Render → Dashboard → Manual Deploy → Restart).

### 3. Generate Password Hash

Generate a secure password hash for Dex:

```bash
docker run --rm ghcr.io/dexidp/dex:latest dex password hash YOURPASSWORD
```

Copy the output hash and update `config.yaml`:

```yaml
connectors:
- type: mockPasswordDB
  id: logins
  name: Email
  config:
    usernames:
    - email: "uggan@chator.local"
      password: "$2a$10$..."  # Paste your hash here
      username: "uggan"
      userID: "1"
```

Commit and push - Render will auto-deploy!

### 4. Test Login

1. Open Element Web (your Synapse URL)
2. Click "Sign In"
3. Should see SSO button for "чатор Login"
4. Login with Dex credentials (email: `uggan@chator.local`, password: your password)

---

## When You Get a Domain (Optional)

Later, if you buy a domain:

1. Add CNAME: `auth.chator.k.vu → chator-auth.onrender.com`
2. Update `DEX_ISSUER` to `https://auth.chator.k.vu`
3. Update `SYNAPSE_URL` to `https://chator.k.vu`
4. Update redirect URI in Dex config

---

## Password Hash Generation

Generate bcrypt password hashes for Dex:

```bash
docker run --rm ghcr.io/dexidp/dex:latest dex password hash YOURPASSWORD
```

Copy the hash output to `config.yaml`.

---

## Connectors

Dex supports multiple authentication backends:

### Static Passwords (Default)
Simple email/password stored in config. Good for small teams.

### LDAP/Active Directory
Connect to existing LDAP directory:

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

### GitHub OAuth
Let users login with GitHub:

```yaml
connectors:
- type: github
  id: github
  name: GitHub
  config:
    clientID: $GITHUB_CLIENT_ID
    clientSecret: $GITHUB_CLIENT_SECRET
    redirectURI: https://chator-auth.onrender.com/callback
    org: your-org
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
    - chator.k.vu
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

Good for testing and small deployments (< 100 users).

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
Ensure OIDC claims (`preferred_username`, `email`, `name`) are returned by Dex. Check Dex logs.

### "Issuer mismatch"
Make sure `DEX_ISSUER` env var matches the actual Render URL.

---

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DEX_ISSUER` | Public URL of Dex service | `https://chator-auth.onrender.com` |
| `DEX_CLIENT_SECRET` | Shared secret with Synapse | `matrix-synapse-secret-change-me` |
| `SYNAPSE_URL` | URL of Matrix Synapse | `https://chator-matrix.onrender.com` |

---

## Security Notes

- 🔒 **Always use HTTPS** (Render provides this automatically)
- 🔑 **Use strong secrets** - change `matrix-synapse-secret-change-me`
- 🛡️ **Rate limiting** - Render has basic DDoS protection
- 📝 **Monitor logs** in Render dashboard
- 🔐 **Use strong passwords** (bcrypt hashes)

---

## Resources

- Dex Docs: https://dexidp.io/docs/
- Dex GitHub: https://github.com/dexidp/dex
- Synapse OIDC: https://matrix-org.github.io/synapse/latest/openid.html
- OIDC Spec: https://openid.net/connect/

---

**чатор** - Secure, self-hosted messaging for Russian teens 🥞
