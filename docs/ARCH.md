# Architecture

Zelix is structured as a layered SDK with clear separation of concerns.

## Layer Diagram

```
┌─────────────────┐
│   Application   │
└─────────────────┘
         │
    ┌────────────┐
    │   Zelix    │  ← Public API
    │  (zelix.zig) │
    └────────────┘
         │
    ┌────┼────┐
    │         │
┌─────────┐ ┌─────────┐
│ Client  │ │Mirror   │
│ (grpc)  │ │Client   │
└─────────┘ │(rest)   │
            └─────────┘
                 │
            ┌─────────┐
            │ Mirror  │
            │ Node    │
            │ (REST)  │
            └─────────┘
```

## Components

### Public API (`src/zelix.zig`)
- Exports all public types and functions
- Single import point: `@import("zelix")`
- Re-exports from internal modules

### Core Types (`src/model.zig`)
- `AccountId`, `TokenId`, `Hbar`, `Timestamp`, etc.
- Parsing, formatting, validation
- No external dependencies

### Crypto (`src/crypto.zig`)
- ED25519/ECDSA key generation and signing
- DER/PEM serialization (planned)
- Pluggable signer interface (planned)

### Client (`src/client.zig`)
- Main network client
- Transaction submission (gRPC, planned)
- Query execution (via Mirror Node)
- Environment configuration

### Mirror Client (`src/mirror.zig`)
- Read-only mirror node access
- Pagination support
- Topic polling
- Transaction waiting

### Transactions (`src/tx.zig`)
- Transaction builders
- Freeze/sign/serialize pipeline
- Concrete transaction types

### Queries (`src/query.zig`)
- Query builders
- JSON response parsing
- Error handling

## Data Flow

### Query Flow
1. Application creates query builder
2. Builder sets parameters
3. `execute(client)` called
4. Client sends HTTP request to Mirror Node
5. JSON response parsed into Zig structs
6. Result returned to application

### Transaction Flow
1. Application creates transaction builder
2. Builder adds operations
3. `freeze()` finalizes transaction body
4. `sign(private_key)` adds signatures
5. `toBytes()` serializes for network
6. Client submits to consensus nodes (planned)
7. Receipt retrieved via Mirror Node

## Dependencies

- **std**: Zig standard library (HTTP, JSON, crypto)
- **No external crates**: Pure Zig implementation
- **Optional**: zhttp, ztls for advanced networking (planned)

## Threading Model

- Synchronous by default
- Async-friendly (no blocking operations)
- Compatible with zsync event loop

## Error Propagation

- Zig error unions throughout
- Custom `HelixError` for SDK-specific errors
- HTTP status codes mapped to errors
- JSON parsing errors propagated up

## Extensibility

- Pluggable crypto signers
- Custom network transports
- Additional query/transaction types
- Mirror node alternatives