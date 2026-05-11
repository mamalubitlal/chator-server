# synapse/storage/

## Responsibility
Database persistence layer - stores rooms, users, events, state.

## Design
- `DataStore`: Main data access class
- `controllers/`: Specific data operations
  - `room.py`: Room data
  - `user.py`: User data
  - `state.py`: State resolution
  - `purge.py`: Background purging
- `schema/`: Database schema definitions
- `databases/`: Engine-specific implementations
- Uses: SQLAlchemy for queries

## Integration
- Used by: All handlers
- Persists: All server state