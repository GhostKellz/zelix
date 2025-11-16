# gRPC Transport Guide

This document captures the current behaviour of Zelix when using gRPC for consensus and mirror interactions. It complements the existing REST documentation and will evolve as more parity work lands.

## Enabling gRPC

- **Mirror client:** When constructing `MirrorClient`, set `transport = .grpc` and ensure `grpc_endpoint` points at a Hedera mirror gRPC endpoint (defaults exist for mainnet/testnet).
- **Consensus submit:** The consensus client uses gRPC by default for submissions and automatically falls back to REST if a node rejects the stream.
- **Fallback logging:** When gRPC is unavailable the clients emit a warning indicating the feature name and endpoint they fell back to.

## Payload Logging Toggle

- Call `setGrpcPayloadLogging(true)` on either the consensus or mirror client to turn on debug logging for request and response payload size, status codes, and retry counts.
- Turning the flag back off disables verbose output without rebuilding binaries, making it safe to expose via CLI flags or environment variables.
- Set `ZELIX_GRPC_DEBUG_PAYLOADS=1` (or `true/yes/on`) before constructing a client and the config loader will enable verbose payload logging automatically. JSON configs can provide the same behaviour via a `"grpcDebugPayloads": true` field.

## Metrics Snapshotting

- Use `getGrpcStats()` on any client that exposes it to retrieve aggregate counters including total requests, retries, last latency, and last HTTP/gRPC status codes.
- The stats struct is lightweight and can be sampled for ad-hoc diagnostics; call `resetStats()` on the underlying `GrpcWebClient` to clear the counters between test runs.

## Fallback Expectations

- Consensus submissions attempt gRPC first, retry with exponential backoff, and fall back to REST only after all attempts fail.
- Mirror topic streaming maintains a cursor and reconnect loop; when the stream fails it backs off, doubles the delay up to five seconds, and resumes from the last consensus timestamp.
- REST fallbacks reuse the same pagination tokens (`next` or timestamp cursors) so behaviour matches existing REST-based flows.

## Local Testing Tips

1. Export mirror and consensus endpoints in your shell or rely on network defaults for testnet.
2. Run `zig build test` to exercise the updated code paths; the transport is used in unit coverage even without live nodes.
3. For manual validation, build the examples under `examples/` and toggle the payload logging flag to see gRPC activity inline.
4. When streaming topics locally, lower the reconnect delay in `mirror.zig` if you need tighter loops while iterating.

## Transport Options

Zelix supports three transport methods for interacting with the Hedera network:

1. **REST** - Traditional HTTP/1.1 with JSON (stable, production-ready)
2. **gRPC** - HTTP/2 with gRPC-Web for topic streaming (stable)
3. **Block Streams** - Native gRPC streaming from Block Nodes (experimental, HIP-1056/1081)

### Choosing a Transport

```zig
// Option 1: REST (default, most compatible)
const mirror = try MirrorClient.initWithOptions(.{
    .allocator = allocator,
    .network = .testnet,
    .transport = .rest,
});

// Option 2: gRPC (for topic streaming)
const mirror = try MirrorClient.initWithOptions(.{
    .allocator = allocator,
    .network = .testnet,
    .transport = .grpc,
    .grpc_endpoint = "https://testnet.mirrornode.hedera.com:443",
});

// Option 3: Block Streams (experimental, cutting edge)
const mirror = try MirrorClient.initWithOptions(.{
    .allocator = allocator,
    .network = .testnet,
    .transport = .block_stream,
    .block_node_endpoint = "https://testnet.block.hedera.com:443",
});
```

## Transaction Streaming

Zelix supports streaming transaction records via both REST and gRPC transports:

```zig
const options = .{
    .start_time = null, // Start from current time
    .limit = 25,        // Fetch up to 25 records per request
    .poll_interval_ns = 2 * std.time.ns_per_s,  // Poll every 2 seconds
    .include_duplicates = false,  // Filter out duplicate transactions
    .include_children = false,    // Filter out child/scheduled transactions
};

try mirror_client.streamTransactions(options, handleTransaction);

fn handleTransaction(record: *const TransactionRecord) !void {
    std.debug.print("Transaction: {s}\n", .{record.transaction_id});
}
```

### gRPC Transaction Streaming

**Note:** Hedera Mirror Node currently does not provide a native gRPC transaction streaming endpoint. The `streamTransactionsGrpc` implementation uses REST polling with gRPC-style retry logic and exponential backoff. When a proper gRPC endpoint becomes available, this will be replaced with server-streaming RPC.

The gRPC-style transport provides:
- Automatic retry with exponential backoff (controlled by `GrpcWebClient` options)
- Connection failure tolerance with configurable max retries
- Consistent error handling across REST and gRPC code paths

### Duplicate and Child Transaction Filtering

Set `include_duplicates = true` to include duplicate transactions (transactions with different nonces). Set `include_children = true` to include scheduled/child transactions. By default, both are filtered out.

REST API query parameters:
- `nonce=ne:0` - Include duplicates
- `scheduled=true` - Include child transactions

### Block Streams (Experimental)

**Status:** Early Access (v0.56+) - Schema subject to change

Block Streams provide the most efficient way to stream transactions from Hedera:

```zig
const mirror = try MirrorClient.initWithOptions(.{
    .allocator = allocator,
    .network = .testnet,
    .transport = .block_stream,
    .block_node_endpoint = "https://testnet.block.hedera.com:443",
});

try mirror.streamTransactions(.{
    .start_time = null, // Start from latest
    .include_duplicates = false,
    .include_children = false,
}, handleTransaction);
```

**How it works:**
1. Subscribes to `BlockStreamService.subscribeBlockStream`
2. Receives stream of `BlockItem` messages from Block Nodes
3. Extracts `event_transaction` items
4. Parses transactions and invokes callback

**Advantages:**
- True server-streaming gRPC (no polling)
- Unified data stream (transactions + events + state)
- BLS signature verification
- Lower latency than REST
- More efficient than polling

**Limitations:**
- Requires Block Node infrastructure (HIP-1081)
- Proto schema in early access/preview
- Not all Block Nodes may be available on all networks
- Transaction parsing from `BlockItem` requires protobuf decoding (TODO)

**See also:** `docs/BLOCK_STREAMS.md` for detailed Block Streams documentation

## Debugging Checklist

- Verify TLS and host configuration when `GrpcTransportUnavailable` is raised; the transport must know the authority header to connect.
- Watch for warning logs that include the attempted method and final status codes; they surface retry counts and gRPC `grpc-status` values.
- Collect stats snapshots before and after a reproducer to understand retry behaviour and latency spikes.
- For transaction streaming issues, enable gRPC payload logging to see fetch attempts, retry counts, and backoff delays.
