# synapse/crypto/

## Responsibility
Cryptographic operations - encryption, signing, key management.

## Design
- Encryption (Olm, Megolm)
- Signature verification
- Key export/import
- Token verification (macaroons)

## Integration
- Used by: Federation, room encryption
- Depends on: util