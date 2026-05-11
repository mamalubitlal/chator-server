# synapse/rest/

## Responsibility
REST API endpoint definitions (Client-Server, Admin, Federation).

## Design
- `client/`: Client API endpoints (/r0/*)
  - `account/`: Registration, login
  - `rooms/`: Room operations
  - `sync/`: Sync endpoint
- `admin/`: Admin endpoints
- `federation/`: Federation client API
- `media/`: Media endpoints
- `keys/`: Key upload/download
- `consent/`: Privacy consent

## Integration
- Serves: HTTP requests
- Calls: Handlers for business logic