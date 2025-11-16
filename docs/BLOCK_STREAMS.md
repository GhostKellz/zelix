# Block Streams API (HIP-1056 / HIP-1081)

## Overview

Hedera Block Streams are the next-generation streaming API that replaces RecordStream V6. Block Streams provide a unified, verifiable stream of all network data including transactions, events, state changes, and proofs.

**Status:** Early Access / Preview (v0.56+)
**Location:** Block Nodes (separate from consensus nodes)
**Protocol:** gRPC with HTTP/2

## Architecture

```
Block Stream = Transactions + Events + State + Signatures (unified)
```

### Block Structure

Each block contains:
1. **BlockHeader** - Version, block number, hash
2. **Event Items** - One or more events containing transactions
3. **Transaction Items** - Transaction data, results, outputs
4. **State Changes** - Contract state, account balances, etc.
5. **BlockProof** - BLS signature proving consensus

## Available Services

### 1. BlockStreamService (Live Streaming)

**Method:** `subscribeBlockStream`

```protobuf
rpc subscribeBlockStream(SubscribeStreamRequest)
    returns (stream SubscribeStreamResponse);
```

**Request:**
- `start_block_number` - First block to stream
- `end_block_number` - Last block (0 = infinite/live)
- `allow_unverified` - Accept blocks without proof verification

**Response Stream:**
- Stream of `BlockItemSet` messages
- Each set contains one or more `BlockItem`s
- Ends with `SubscribeStreamResponseCode` status

**Use cases:**
- Live transaction monitoring
- Real-time event streaming
- Continuous data ingestion

### 2. BlockAccessService (Historical Queries)

**Method:** `singleBlock`

```protobuf
rpc singleBlock(SingleBlockRequest)
    returns (SingleBlockResponse);
```

**Request:**
- `block_number` - Specific block to retrieve
- `retrieve_latest` - Get most recent block
- `allow_unverified` - Accept unverified blocks

**Response:**
- Complete `Block` with all items
- Starts with BlockHeader
- Ends with BlockProof

**Use cases:**
- Query specific block by number
- Fetch latest block
- Historical data analysis

### 3. BlockNodeService (Node Status)

**Method:** `serverStatus`

```protobuf
rpc serverStatus(ServerStatusRequest)
    returns (ServerStatusResponse);
```

Returns:
- First/last available block numbers
- Node capabilities
- Current status

## Block Item Types

A `BlockItem` can be one of:

1. **header** - Block metadata (number, hash, timestamp)
2. **start_event** - Event boundary marker with metadata
3. **event_transaction** - Transaction submitted to network
4. **transaction_result** - Result of transaction execution
5. **transaction_output** - Contract call outputs, logs
6. **state_changes** - Account/contract state modifications
7. **state_proof** - BLS signature proving block validity

## Extracting Transactions

To get transaction records from blocks:

```
FOR each BlockItem in block:
  IF item is event_transaction:
    Parse transaction details
  IF item is transaction_result:
    Get status, fees, consensus timestamp
  IF item is transaction_output (optional):
    Get contract call results
  IF item is state_changes (optional):
    Get account balance changes
```

## Comparison: REST vs gRPC vs Block Streams

| Feature | REST | gRPC (Topic) | Block Streams |
|---------|------|--------------|---------------|
| Protocol | HTTP/1.1 | HTTP/2 | HTTP/2 |
| Transactions | ✅ Polling | ❌ Not available | ✅ Streaming |
| Topics | ❌ | ✅ Streaming | ✅ Included |
| Events | ❌ | ❌ | ✅ Streaming |
| State | ❌ | ❌ | ✅ Streaming |
| Verification | ❌ | SHA-384 hash | ✅ BLS signature |
| Efficiency | Low | Medium | High |
| Latency | High | Low | Very Low |

## Implementation Status in Zelix

- [ ] Proto file vendoring
- [ ] BlockAccessService client
- [ ] BlockStreamService subscriber
- [ ] Block item parser
- [ ] Transaction extraction
- [ ] State change tracking

## References

- **HIP-1056:** Block Streams specification
- **HIP-1081:** Block Node architecture
- **Protobufs:** `github.com/hashgraph/hedera-protobufs/block/`
- **Consensus node v0.56+** Required for Block Stream support
