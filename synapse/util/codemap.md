# synapse/util/

## Responsibility
Shared utility functions and helpers.

## Design
- `caches/`: Caching infrastructure
  - `lrucache.py`: LRU cache
  - `ttlcache.py`: TTL cache
  - `descriptors.py`: Cached properties
- `async_helpers.py`: async utilities (awaitable helpers)
- `logcontext.py`: Logging context management
- `wheel_timer.py`: Scheduled callbacks
- `stringutils.py`: String utilities
- `macaroons.py`: Token handling
- Background task queues

## Integration
- Used by: All modules throughout the codebase