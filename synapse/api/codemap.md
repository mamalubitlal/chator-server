# synapse/api/

## Responsibility
Core API definitions - constants, URL paths, auth blocking, rate limiting.

## Design
- `constants.py`: Matrix spec constants (event types, join rules, presets)
- `urls.py`: URL path prefix configuration
- `ratelimiting.py`: Per-user rate limiter
- `auth_blocking.py`: Auth denial for deactivated users
- `filtering.py`: Event filtering for sync
- `presence.py`: Presence state tracking
- `room_versions.py`: Supported room versions and features

## Integration
- Used by: REST handlers, federation
- Depends on: config, util