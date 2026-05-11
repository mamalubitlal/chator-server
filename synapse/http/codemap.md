# synapse/http/

## Responsibility
HTTP server and client layer.

## Design
- `__init__.py`: Site creation
- `server.py`: Base servlet classes
- `client.py`: HTTP client for federation/external
- `federation/`: Federation HTTP transport

## Integration
- Handles: All HTTP traffic
- Used by: REST endpoints, federation client