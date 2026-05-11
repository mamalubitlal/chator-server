# synapse/events/

## Responsibility
Event parsing, construction, validation.

## Design
- Event type classes with JSON serialization
- Builder pattern for event creation
- Signature verification
- Auth rules checking

## Integration
- Used by: Handlers, federation, storage