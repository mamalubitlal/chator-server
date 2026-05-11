# synapse/handlers/

## Responsibility
Request handlers - business logic for Matrix operations.

## Design
- `room.py`: Room creation, joining, leaving
- `messages.py`: Sending/receiving messages
- `presence.py`: User online status
- `typing.py`: Typing notifications
- `profile.py`: User profile management
- `sync.py`: Sync API for client refresh
- `sliding_sync/`: Optimized sync for MSC
- `ui_auth/`: UI-based authentication

## Integration
- Called by: REST API endpoints
- Uses: Storage for persistence
- Emits events to: Federation, replication