# synapse/federation/

## Responsibility
Matrix Federation protocol - server-to-server communication.

## Design
- `transport/server/`: Federation server servlet
- `transport/client/`: Federation client for sending
- `sender/`: Sending events to remote servers
- `receiver/`: Receiving events from remote servers
- `encryption/`: Outbound federation encryption
- Uses: HTTP for transport

## Integration
- Communicates with: Other Matrix homeservers
- Receives from: Handlers (for outgoing)
- Sends to: REST handlers (for incoming)