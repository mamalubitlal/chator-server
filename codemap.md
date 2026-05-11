# Repository Atlas: synapse (Matrix Homeserver)

## Project Responsibility
Synapse is a Matrix homeserver implementation in Python. It provides:
- Matrix Client-Server API implementation
- Federation protocol (server-to-server communication)
- Storage layer for persistent data (PostgreSQL/SQLite)
- Worker architecture for horizontal scaling

## System Entry Points
- `synapse/__init__.py`: Server initialization entry point
- `synapse/server.py`: HomeServer start method
- `synapse/app/__init__.py`: Application service registration
- `synapse/config/`: Configuration from YAML files

## Directory Map

| Directory | Responsibility | Code Map |
|-----------|----------------|----------|
| `synapse/api/` | Core API constants, URLs, auth blocking, rate limiting | [codemap](synapse/api/codemap.md) |
| `synapse/app/` | Application services (bridges, webhooks) | [codemap](synapse/app/codemap.md) |
| `synapse/config/` | Configuration schema and loading | [codemap](synapse/config/codemap.md) |
| `synapse/crypto/` | Encryption, key management, token verification | [codemap](synapse/crypto/codemap.md) |
| `synapse/events/` | Event parsing, validation, type builders | [codemap](synapse/events/codemap.md) |
| `synapse/federation/` | Federation server-to-server protocol | [codemap](synapse/federation/codemap.md) |
| `synapse/handlers/` | Request handling (rooms, users, messages) | [codemap](synapse/handlers/codemap.md) |
| `synapse/http/` | HTTP server/servlet layer | [codemap](synapse/http/codemap.md) |
| `synapse/media/` | Media repository (uploads, thumbnails) | [codemap](synapse/media/codemap.md) |
| `synapse/replication/` | Multi-worker communication | [codemap](synapse/replication/codemap.md) |
| `synapse/rest/` | REST API endpoint definitions | [codemap](synapse/rest/codemap.md) |
| `synapse/storage/` | Database persistence layer | [codemap](synapse/storage/codemap.md) |
| `synapse/util/` | Utilities (caches, async, logging) | [codemap](synapse/util/codemap.md) |

## Architecture Overview

```
                    +----------+
                    |  Client  |
                    +----+-----+
                         |
                    REST API
                         |
          +--------------+---------------+
          |              |               |
    +-----+-----+  +----+----+  +-----+-----+
    | Handlers |  | Fed  |  | Media    |
    +-----+-----+  +----+----+  +---------+
          |              |
    +-----+-----+  +----+----+
    | Storage |  | Repl |
    +---------+  +-------+
```