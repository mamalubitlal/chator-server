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

## Quick Setup

### 1. Deploy Dex on Render

**Render Setup:**
1. Go to https://render.com
2. Create new **Web Service**
3. Connect your GitHub repo
4. Configure:
   - **Name:** `chator-auth`
   - **Region:** Frankfurt
   - **Root Directory:** `chator/dex`
   - **Runtime:** Docker
   - **Plan:** Starter ($7/mo)

5. **Environment Variables:**
   ```
   DEX_ISSUER=https://auth.chator.k.vu
   DEX_CLIENT_SECRET=your-secure-secret-here
   ```

6. Deploy!

### 2. Configure DNS

Add CNAME record for Dex:
```
Type    Name                Value
CNAME   auth.chator.k.vu    [Render Dex URL]
```

### 3. Update Synapse Config

Add these env vars to your Matrix Synapse Render service:
```
DEX_ISSUER=https://auth.chator.k.vu
DEX_CLIENT_ID=matrix-synapse
DEX_CLIENT_SECRET=your-secure-secret-here
```

Restart Synapse to apply OIDC config.

### 4. Add Users to Dex

Edit `config.yaml` to add users:

```yaml
staticPasswords:
- email: "user@chator.k.vu"
  hash: "$2a$10$..."  # Generate with: docker run ghcr.io/dexidp/dex:latest dex password hash YOURPASSWORD
  username: "username"
  userID: "2"
```

Or connect LDAP/OAuth connectors (see below).

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
    redirectURI: https://auth.chator.k.vu/callback
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
    redirectURI: https://auth.chator.k.vu/callback
    hostedDomains:
    - chator.k.vu
```

See full connector docs: https://dexidp.io/docs/connectors/

---

## Storage Options

### SQLite (Default - for testing)
```yaml
storage:
  type: sqlite3
  config:
    file: /var/dex/dex.db
```

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
    ssl:
      mode: verify-ca
```

---

## Testing

### 1. Check Dex Health
```bash
curl https://auth.chator.k.vu/healthz
# Should return: OK
```

### 2. Test OIDC Discovery
```bash
curl https://auth.chator.k.vu/.well-known/openid-configuration
```

### 3. Login via Matrix
1. Open Element Web: https://app.chator.k.vu
2. Click "Sign In"
3. Should see "чатор Login" button
4. Login with Dex credentials

---

## Troubleshooting

### "Invalid redirect_uri"
Ensure the redirect URI in Dex config matches Synapse callback:
```yaml
redirectURIs:
- 'https://chator.k.vu/_synapse/client/oidc/callback'
```

### "Client authentication failed"
Check `client_id` and `client_secret` match in both Dex and Synapse configs.

### "User mapping failed"
Ensure OIDC claims (`preferred_username`, `email`, `name`) are returned by Dex. Check Dex logs.

---

## Security Notes

- 🔒 **Always use HTTPS** for Dex in production
- 🔑 **Rotate secrets** regularly
- 🛡️ **Enable rate limiting** (use nginx in front)
- 📝 **Monitor logs** for suspicious activity
- 🔐 **Use strong passwords** (bcrypt hashes)

---

## Resources

- Dex Docs: https://dexidp.io/docs/
- Dex GitHub: https://github.com/dexidp/dex
- Synapse OIDC: https://matrix-org.github.io/synapse/latest/openid.html
- OIDC Spec: https://openid.net/connect/

---

**чатор** - Secure, self-hosted messaging for Russian teens 🥞
