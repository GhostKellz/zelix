# Zelix: Hedera SDK for Zig

Zelix is a native Zig SDK for interacting with Hedera Hashgraph networks. It provides a clean, idiomatic Zig API for Hedera services including accounts, tokens, consensus, and smart contracts.

## Mapping to Hedera Services

Zelix closely mirrors the official Hedera SDKs (JavaScript, Rust, Go) while leveraging Zig's strengths: no GC, compile-time safety, and high performance.

### Core Concepts

| Hedera Concept | Zelix Type | Description |
|----------------|------------|-------------|
| Account ID | `AccountId` | `shard.realm.num` identifier |
| Token ID | `TokenId` | Same format as AccountId |
| Topic ID | `TopicId` | Consensus Service topic identifier |
| Contract ID | `ContractId` | Smart contract identifier |
| Hbar | `Hbar` | Native cryptocurrency (tinybars internally) |
| Transaction ID | `TransactionId` | Account + valid start time |
| Timestamp | `Timestamp` | Seconds + nanoseconds |

### Services

#### Consensus Service (HCS)
- `TopicMessageSubmitTransaction` - Submit messages to topics
- `MirrorClient.getTopicMessages()` - Read topic messages
- `MirrorClient.subscribeTopic()` - Poll for new messages

#### Token Service (HTS)
- `TokenId` - Token identifiers
- `CryptoTransferTransaction` - Transfer tokens/hbar

#### Smart Contracts (HSCS)
- `ContractId` - Contract identifiers
- `ContractCallQuery` - Query contract state (planned)
- `ContractExecuteTransaction` - Execute contract functions (planned)

#### Network Services
- `Client` - Main client for transactions and queries
- `MirrorClient` - Read-only mirror node access
- `PrivateKey`/`PublicKey` - ED25519/ECDSA key management

## API Patterns

Zelix follows the builder pattern for complex operations:

```zig
// Query account balance
const balance = try AccountBalanceQuery{}
    .setAccountId(account_id)
    .execute(&client);

// Create transfer transaction
var tx = CryptoTransferTransaction.init(allocator);
defer tx.deinit();
try tx.addHbarTransfer(recipient, amount);
try tx.setTransactionId(TransactionId.generate(sender_account));
try tx.freeze();
try tx.sign(private_key);
// Submit via client.submitTransaction()
```

## Network Support

- **Mainnet**: Production Hedera network
- **Testnet**: Public test network
- **Previewnet**: Preview of upcoming features

Configure via environment:
```bash
export HEDERA_NETWORK=testnet
```

Or programmatically:
```zig
var client = try Client.init(allocator, .testnet);
```

## Error Handling

Zelix uses Zig's error union types:

```zig
const result = client.getAccountBalance(account_id) catch |err| {
    switch (err) {
        error.Network => // Network error
        error.Decode => // JSON decode error
        else => // Other errors
    }
};
```

## Performance

- Zero-allocation options where possible
- Compile-time validation of IDs and amounts
- Efficient protobuf serialization (planned)
- Async-friendly design for zsync integration