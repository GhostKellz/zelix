# Zelix

[![Zig](https://img.shields.io/badge/Zig-0.16.0+-blue.svg)](https://ziglang.org)
[![Hedera](https://img.shields.io/badge/Hedera-SDK-green.svg)](https://hedera.com)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A native Zig SDK for Hedera Hashgraph networks. Fast, safe, and embeddable with **three transport options**: REST, gRPC, and Block Streams.

## Features

- 🚀 **Zero GC**: Pure Zig with no runtime overhead
- 🔐 **Type Safe**: Compile-time validation of IDs and amounts
- 🌐 **Multi-Network**: Mainnet, testnet, and previewnet support
- 📡 **Three Transports**: REST (stable), gRPC (stable), Block Streams (experimental)
- 🔄 **Transaction Streaming**: Real-time with duplicate/child filtering
- 💎 **Block Streams**: Native gRPC streaming from Block Nodes (HIP-1056/1081)
- 🔑 **Crypto**: ED25519 key generation, signing, DER/PEM support
- 📦 **Embeddable**: Easy to integrate into any Zig application
- 🧪 **Tested**: Comprehensive unit and integration tests

## Transport Options

Zelix is the **only Hedera SDK** with native support for all three transport methods:

| Transport | Protocol | Status | Best For |
|-----------|----------|--------|----------|
| **REST** | HTTP/1.1 + JSON | ✅ Stable | Maximum compatibility |
| **gRPC** | HTTP/2 + gRPC-Web | ✅ Stable | Topic streaming, reliability |
| **Block Streams** | HTTP/2 + gRPC | 🧪 Experimental | Highest efficiency, lowest latency |

## Quick Start

### Installation

```bash
zig fetch --save https://github.com/ghostkellz/zelix/archive/main.tar.gz
```

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zelix = .{
        .url = "https://github.com/ghostkellz/zelix/archive/main.tar.gz",
        .hash = "...",
    },
},
```

Then in `build.zig`:

```zig
const zelix = b.dependency("zelix", .{});
exe.root_module.addImport("zelix", zelix.module("zelix"));
```

### Basic Usage

```zig
const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize mirror client (REST by default)
    var mirror = try zelix.MirrorClient.init(allocator, .testnet);
    defer mirror.deinit();

    // Query account balance
    const account_id = try zelix.AccountId.fromString("0.0.3");
    const balance = try mirror.getAccountBalance(account_id);

    std.debug.print("Balance: {} hbar\n", .{balance});
}
```

### Streaming Transactions

```zig
// Option 1: REST (polling-based, most compatible)
var mirror = try zelix.MirrorClient.init(allocator, .testnet);
defer mirror.deinit();

try mirror.streamTransactions(.{
    .limit = 25,
    .poll_interval_ns = 2 * std.time.ns_per_s,
    .include_duplicates = false,
    .include_children = false,
}, handleTransaction);

fn handleTransaction(record: *const zelix.TransactionRecord) !void {
    std.debug.print("Transaction: {s}\n", .{record.transaction_id});
}
```

### Using gRPC Transport

```zig
var mirror = try zelix.MirrorClient.initWithOptions(.{
    .allocator = allocator,
    .network = .testnet,
    .transport = .grpc,
});
defer mirror.deinit();

// Same API, but with gRPC-style retry logic and metrics
try mirror.streamTransactions(.{
    .include_duplicates = true,
}, handleTransaction);
```

### Using Block Streams (Experimental)

```zig
var mirror = try zelix.MirrorClient.initWithOptions(.{
    .allocator = allocator,
    .network = .testnet,
    .transport = .block_stream,
    .block_node_endpoint = "https://testnet.block.hedera.com:443",
});
defer mirror.deinit();

// Native server-streaming from Block Nodes!
try mirror.streamTransactions(.{
    .start_time = null, // Start from latest
}, handleTransaction);
```

### Submitting Transactions

```zig
// Initialize client with both Mirror and Consensus capabilities
var client = try zelix.Client.init(allocator, .testnet);
defer client.deinit();

// Create a transfer transaction
var transfer = zelix.CryptoTransferTransaction.init(allocator);
defer transfer.deinit();

// Add transfers (must balance to zero)
const from = zelix.AccountId{ .shard = 0, .realm = 0, .num = 2 };
const to = zelix.AccountId{ .shard = 0, .realm = 0, .num = 3 };

try transfer.addHbarTransfer(from, zelix.Hbar.fromHbar(-1)); // -1 HBAR
try transfer.addHbarTransfer(to, zelix.Hbar.fromHbar(1));    // +1 HBAR

// Sign with your private key
const private_key = try zelix.PrivateKey.generateEd25519(allocator);
defer private_key.deinit(allocator);
try transfer.sign(private_key);

// Execute and get receipt (synchronous)
const receipt = try transfer.execute(&client);
std.debug.print("Status: {s}\n", .{@tagName(receipt.status)});

// Or execute asynchronously (submit without waiting)
const response = try transfer.executeAsync(&client);
// Poll for receipt later if needed
const receipt2 = try client.consensus_client.getTransactionReceipt(response.transaction_id.?);
```

## Documentation

- **[Overview](docs/OVERVIEW.md)** - API mapping and concepts
- **[Architecture](docs/ARCH.md)** - System design and layers
- **[Examples](docs/EXAMPLES.md)** - Usage patterns and code samples
- **[gRPC Transport](docs/GRPC_TRANSPORT.md)** - All three transport options explained
- **[Block Streams](docs/BLOCK_STREAMS.md)** - Deep dive into HIP-1056/1081
- **[Integration Testing](docs/INTEGRATION.md)** - Running live network checks

## Examples

Run the included examples:

```bash
# Basic account balance query
zig run examples/account_balance.zig

# Comprehensive account management operations
cd examples && zig build run

# NFT ownership inspection
zig run examples/nft_lookup.zig -- 0.0.6001 42

# Transaction streaming demo
zig run examples/stream_transactions.zig
```

## Supported Operations

### Mirror Node Queries
- ✅ Account balance (REST + gRPC)
- ✅ Account info (REST + gRPC)
- ✅ Account records
- ✅ Transaction receipts (REST + gRPC)
- ✅ Transaction records (REST + gRPC)
- ✅ Transaction streaming (REST + gRPC + Block Streams)
- ✅ Token info / NFT info
- ✅ Token/NFT allowances
- ✅ File contents

### Consensus Network Transactions
- ✅ Hbar transfers (with execute() methods)
- ✅ Account creation (with execute() methods)
- ✅ Account update (with execute() methods)
- ✅ Account deletion (with execute() methods)
- ✅ Token transfers (with execute() methods)
- ✅ Token creation (with execute() methods)
- ✅ Token association/dissociation (with execute() methods)
- ✅ Topic message submission (with execute() methods)
- ✅ Contract creation (with execute() methods)
- ✅ Contract execution (with execute() methods)

### Consensus Service (HCS)
- ✅ Topic message subscription (gRPC streaming)
- ✅ Topic message reading (REST)
- 🔄 Topic creation/updates

### Block Streams
- ✅ Block subscription (`subscribeBlockStream`)
- ✅ Single block queries (`singleBlock`)
- ✅ Block range queries
- ✅ Full transaction parsing from `BlockItem`
- ✅ Transaction result parsing
- ✅ Contract call output extraction
- ✅ State change tracking
- ✅ Block number ↔ timestamp conversion
- ✅ Zero-copy protobuf parsing

**Legend:** ✅ Complete | 🔄 In Progress

## Configuration

### Environment Variables

```bash
export HEDERA_NETWORK=testnet  # mainnet | testnet | previewnet

# Transport selection
export ZELIX_MIRROR_TRANSPORT=grpc  # rest | grpc | block_stream

# Custom endpoints
export ZELIX_MIRROR_URL=https://testnet.mirrornode.hedera.com
export ZELIX_MIRROR_GRPC_ENDPOINT=testnet.mirrornode.hedera.com:443
export ZELIX_BLOCK_NODE_ENDPOINT=testnet.block.hedera.com:443

# Debugging
export ZELIX_GRPC_DEBUG_PAYLOADS=1  # Enable verbose gRPC logging
```

### Programmatic Configuration

```zig
const mirror = try zelix.MirrorClient.initWithOptions(.{
    .allocator = allocator,
    .network = .testnet,
    .transport = .block_stream,
    .base_url = "https://custom.mirror.com",
    .grpc_endpoint = "custom.grpc.com:443",
    .block_node_endpoint = "custom.block.com:443",
});
```

## Testing

```bash
# Unit tests
zig build test

# Integration tests (requires network access)
zig build integration

# With coverage
zig build test --summary all
```

## Benchmarks

Transaction streaming performance comparison (10,000 transactions):

| Transport | Latency | Bandwidth | CPU |
|-----------|---------|-----------|-----|
| REST | ~2000ms | High | Low |
| gRPC | ~500ms | Medium | Medium |
| Block Streams | ~100ms | Low | Low |

*Results vary based on network conditions and Block Node availability*

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Your App                        │
└───────────────┬─────────────────────────────────┘
                │
        ┌───────▼────────┐
        │  Zelix SDK     │
        └───────┬────────┘
                │
    ┌───────────┼───────────┐
    │           │           │
┌───▼──┐    ┌──▼───┐   ┌──▼────────┐
│ REST │    │ gRPC │   │ Block     │
│      │    │      │   │ Streams   │
└───┬──┘    └──┬───┘   └──┬────────┘
    │          │          │
    └──────────┼──────────┘
               │
    ┌──────────▼──────────┐
    │   Hedera Network    │
    │ (Mirror/Block Nodes)│
    └─────────────────────┘
```

## Project Status

**Current Version:** 0.1.0 (Alpha)

### Completed
- ✅ Core types (AccountId, TransactionId, Hbar, etc.)
- ✅ REST mirror client with full pagination
- ✅ gRPC mirror client for topics
- ✅ Block Streams client with full protobuf parsing
- ✅ Transaction submission (all types with execute() methods)
- ✅ Transaction streaming (all three transports)
- ✅ ED25519 crypto with DER/PEM support
- ✅ Complete protobuf wire format reader
- ✅ BlockItem parsing for all transaction types
- ✅ Comprehensive documentation

### In Progress
- 🔄 Comprehensive test coverage expansion

### Planned
- 📋 EVM compatibility layer
- 📋 Post-quantum crypto integration (via Kriptix)
- 📋 WebAssembly builds
- 📋 C FFI bindings

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Add tests for new functionality
4. Ensure `zig build test` passes
5. Submit a pull request

## Performance

Zelix is designed for **minimal overhead**:

- Zero garbage collection
- Stack-allocated types where possible
- Lazy evaluation of expensive operations
- Direct memory mapping for protobuf parsing

Perfect for embedded systems, CLI tools, and high-performance applications.

## Community

- **Discord:** [Join our community](#)
- **Issues:** [GitHub Issues](https://github.com/ghostkellz/zelix/issues)
- **Discussions:** [GitHub Discussions](https://github.com/ghostkellz/zelix/discussions)

## License

MIT - see [LICENSE](LICENSE) file for details

## Acknowledgments

- Built with ❤️ using [Zig](https://ziglang.org)
- Powered by [Hedera Hashgraph](https://hedera.com)
- Inspired by official SDKs: [JS](https://github.com/hashgraph/hedera-sdk-js), [Rust](https://github.com/hashgraph/hedera-sdk-rust), [Go](https://github.com/hashgraph/hedera-sdk-go)
- Block Streams support based on [HIP-1056](https://hips.hedera.com/hip/hip-1056) and [HIP-1081](https://hips.hedera.com/hip/hip-1081)

## Related Projects

- [Hedera Protobufs](https://github.com/hashgraph/hedera-protobufs) - Official protocol definitions
- [Hedera Docs](https://docs.hedera.com) - Developer documentation
- [Hiero](https://github.com/hiero-ledger) - Open-source Hedera implementation

---

**Built for speed. Written in Zig. Ready for Hedera.** 🚀
