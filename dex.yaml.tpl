# Dex configuration for Chator
# Template - values replaced at runtime

issuer: {{ .Env.DEX_ISSUER }}
web:
  http: 0.0.0.0:5556
  origins:
    - {{ .Env.SYNAPSE_URL | default "https://chator-server.onrender.com" }}

storage:
  type: sqlite3
  config:
    file: /data/dex.db

logger:
  level: info
  format: json

oauth2:
  responseTypes: [id_token]
  deviceResponseTypes: [device_code]
  skipApprovalScreen: true
  passwordConnector: local

enablePasswordDB: true
deviceFlow:
  enabled: true

staticClients:
  - id: {{ .Env.DEX_CLIENT_ID }}
    name: Matrix Synapse
    redirectURIs:
      - {{ .Env.SYNAPSE_URL | default "https://chator-server.onrender.com" }}/_matrix/client/v3/login/oidc/callback
    secret: {{ .Env.DEX_CLIENT_SECRET }}

staticPasswords:
  - email: {{ .Env.DEX_STATIC_PASSWORD_EMAIL }}
    hash: {{ .Env.DEX_STATIC_PASSWORD_HASH }}
    username: {{ .Env.DEX_STATIC_PASSWORD_USERNAME }}