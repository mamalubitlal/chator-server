# synapse/config/

## Responsibility
Configuration schema and loading from YAML files.

## Design
- `__init__.py`: Config base class
- `homeserver.py`: Main homeserver config (name, signing key, etc)
- `server.py`: Server settings (max upload size, rate limits)
- `logging.py`: Log level configuration
- `database.py`: Database connection settings
- Each config is a class with typed fields, auto-loaded from environment

## Integration
- Used by: All modules at startup
- Loads config before anything else runs