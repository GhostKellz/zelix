# Next Steps for Zelix Development

## 🎯 Immediate Priorities (Week 1-2)

### 1. Transaction Submission Foundation

**Why:** Core functionality needed for any Hedera SDK

**Goal:** Submit transactions to consensus nodes and get receipts

**Implementation:**
```zig
// src/consensus.zig (NEW FILE)
pub const ConsensusClient = struct {
    allocator: std.mem.Allocator,
    network: model.Network,
    node_endpoints: [][]const u8,
    grpc_client: grpc_web.GrpcWebClient,

    pub fn init(allocator: std.mem.Allocator, network: model.Network) !ConsensusClient { ... }
    pub fn submitTransaction(self: *ConsensusClient, signed_tx: []const u8) !TransactionId { ... }
    pub fn getReceipt(self: *ConsensusClient, tx_id: TransactionId) !TransactionReceipt { ... }
};

// src/transaction.zig (NEW FILE)
pub const TransferTransaction = struct {
    transfers: std.ArrayList(Transfer),
    max_fee: ?Hbar = null,
    memo: ?[]const u8 = null,

    pub fn addHbarTransfer(self: *TransferTransaction, account: AccountId, amount: Hbar) !void { ... }
    pub fn build(self: *TransferTransaction, allocator: std.mem.Allocator) ![]u8 { ... }
    pub fn execute(self: *TransferTransaction, client: *Client) !TransactionReceipt { ... }
};
```

**Tasks:**
- [x] Create `src/consensus.zig` - Consensus node client ✅ COMPLETE
- [x] Create `src/tx.zig` - Transaction builders ✅ COMPLETE
- [x] Add protobuf builders for transaction bodies ✅ COMPLETE
- [x] Implement transaction signing with ED25519 ✅ COMPLETE
- [x] Add fee calculation logic ✅ COMPLETE
- [x] Create receipt polling loop ✅ COMPLETE
- [x] Add example: `examples/send_hbar.zig` ✅ COMPLETE
- [x] Add execute() methods to all transaction types ✅ COMPLETE

**Files to Create:**
```
src/
├── consensus.zig       # Consensus node gRPC client
├── transaction.zig     # Transaction builders
└── proto_builders.zig  # Protobuf encoding helpers

examples/
└── send_hbar.zig       # Transfer HBAR example
```

**Estimated Effort:** 3-5 days

---

### 2. Block Stream Protobuf Parser

**Why:** Unlock the full power of Block Streams

**Goal:** Parse `BlockItem` protobuf messages into Zig structs

**Implementation:**
```zig
// src/block_parser.zig (NEW FILE)
pub fn parseBlockItem(allocator: std.mem.Allocator, data: []const u8) !BlockItem {
    var reader = proto.Reader.init(data);

    // Parse protobuf wire format
    while (try reader.next()) |field| {
        switch (field.tag) {
            1 => { /* header */ },
            2 => { /* start_event */ },
            3 => { /* event_transaction */ },
            4 => { /* transaction_result */ },
            5 => { /* transaction_output */ },
            6 => { /* state_changes */ },
            7 => { /* state_proof */ },
        }
    }
}

pub fn extractTransactionRecord(allocator: std.mem.Allocator, block_item: BlockItem) !TransactionRecord {
    // Convert BlockItem.event_transaction → TransactionRecord
    return TransactionRecord{
        .transaction_id = ...,
        .consensus_timestamp = ...,
        .result = ...,
        .fee = ...,
        .transfers = ...,
    };
}
```

**Tasks:**
- [ ] Create `src/proto/reader.zig` - Protobuf wire format parser
- [ ] Create `src/block_parser.zig` - BlockItem parser
- [ ] Map `event_transaction` to `TransactionRecord`
- [ ] Parse `transaction_result` for status/fees
- [ ] Extract transfer lists from `state_changes`
- [ ] Add unit tests with real block data
- [ ] Update `src/block_stream.zig` to use parser

**Files to Create:**
```
src/
├── proto/
│   └── reader.zig      # Protobuf wire format reader
└── block_parser.zig    # BlockItem → TransactionRecord

tests/
└── block_parser_test.zig
```

**Estimated Effort:** 4-6 days

---

## 📋 Medium Priority (Week 3-4)

### 3. Comprehensive Testing

**Tests Needed:**
- [ ] Transaction submission end-to-end
- [ ] Block stream parsing with real data
- [ ] All three transports (REST, gRPC, Block Streams)
- [ ] Error handling and retry logic
- [ ] Performance benchmarks

**Files:**
```
tests/
├── transaction_test.zig
├── block_parser_test.zig
├── integration_test.zig
└── benchmark.zig
```

### 4. Additional Transaction Types

**Priority Order:**
1. **Token transfers** - Most requested feature
2. **Topic messages** - HCS integration
3. **Account operations** - Full lifecycle
4. **File operations** - Complete support

**Example:**
```zig
// Token transfer
const transfer = zelix.TokenTransferTransaction{};
transfer.addTokenTransfer(token_id, from_account, amount(-100));
transfer.addTokenTransfer(token_id, to_account, amount(100));
const receipt = try transfer.execute(&client);
```

---

## 🚀 Nice to Have (Week 5-8)

### 5. Developer Experience Improvements

**CLI Tool:**
```bash
# zelix-cli: Command-line tool for Hedera
zelix balance 0.0.3
zelix transfer --from 0.0.2 --to 0.0.3 --amount 10
zelix stream --network testnet --transport block_stream
```

**VS Code Extension:**
- Syntax highlighting for Hedera IDs
- Inline balance/info lookup
- Transaction template snippets

### 6. Advanced Features

**Smart Contracts:**
```zig
const contract = try zelix.Contract.fromAddress(allocator, contract_id);
const result = try contract.call("transfer", .{
    .to = recipient,
    .amount = 1000,
});
```

**NFT Operations:**
```zig
const nft = try zelix.NftMintTransaction{};
nft.setTokenId(token_id);
nft.addMetadata("ipfs://...");
const receipt = try nft.execute(&client);
```

---

## 📊 Success Criteria

### Week 2 Checkpoint
- [ ] Can submit basic Hbar transfer transactions
- [ ] Receive and verify transaction receipts
- [ ] Example code works end-to-end

### Week 4 Checkpoint
- [ ] Block stream parser extracts transactions
- [ ] All tests passing
- [ ] Documentation updated

### Week 8 Checkpoint (v0.2.0 Release)
- [ ] Full transaction support (Hbar, tokens, topics)
- [ ] Comprehensive test coverage (>80%)
- [ ] Performance benchmarks published
- [ ] Release notes and migration guide

---

## 🛠 Development Workflow

### Setup
```bash
cd /data/projects/zelix

# Run tests continuously
zig build test --summary all

# Check specific module
zig build-exe src/transaction.zig --test-no-exec

# Format code
zig fmt src/
```

### Before Each Commit
```bash
# 1. Ensure tests pass
zig build test

# 2. Format code
zig fmt .

# 3. Check for unused code
zig build --summary all

# 4. Update documentation
# Edit relevant docs/*.md files
```

### Release Process (v0.2.0)
```bash
# 1. Update version in build.zig.zon
# .version = "0.2.0"

# 2. Update CHANGELOG.md
# ## [0.2.0] - 2026-XX-XX
# ### Added
# - Transaction submission support
# - Block stream protobuf parsing
# ...

# 3. Tag release
git tag -a v0.2.0 -m "Release v0.2.0: Transaction Submission"
git push origin v0.2.0

# 4. Create GitHub release
gh release create v0.2.0 --title "v0.2.0" --notes-file CHANGELOG.md
```

---

## 💡 Design Decisions to Make

### 1. Error Handling Strategy
**Options:**
- A) Zig error unions everywhere (current)
- B) Result type with detailed error info
- C) Hybrid approach

**Recommendation:** Stick with A for now, revisit in v0.3.0

### 2. Async I/O
**Options:**
- A) Blocking I/O (current)
- B) async/await with event loop
- C) Thread pool

**Recommendation:** Keep blocking for v0.2.0, add async in v0.3.0

### 3. Transaction Builder API
**Options:**
- A) Builder pattern (like Rust SDK)
- B) Struct initialization (like current)
- C) Functional/fluent API

**Recommendation:** B for simplicity, ergonomics

---

## 📚 Resources

### Hedera Documentation
- [Transaction Structure](https://docs.hedera.com/hedera/sdks-and-apis/sdks)
- [Protobuf Definitions](https://github.com/hashgraph/hedera-protobufs)
- [HIP-1056 Block Streams](https://hips.hedera.com/hip/hip-1056)

### Reference Implementations
- [Rust SDK Transaction](https://github.com/hashgraph/hedera-sdk-rust/blob/main/src/transaction.rs)
- [JS SDK Transaction](https://github.com/hashgraph/hedera-sdk-js/blob/main/src/transaction/Transaction.js)
- [Go SDK Transaction](https://github.com/hashgraph/hedera-sdk-go/blob/main/transaction.go)

### Zig Best Practices
- [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide)
- [Error Handling](https://ziglang.org/documentation/master/#Errors)
- [Memory Management](https://ziglang.org/documentation/master/#Memory)

---

## 🎉 Celebration Milestones

- [ ] First successful transaction on testnet
- [ ] First Block Stream transaction parsed
- [ ] 100% test coverage achieved
- [ ] v0.2.0 released
- [ ] Featured on Hedera developer portal
- [ ] 100+ GitHub stars

---

**Last Updated:** 2025-11-16
**Owner:** Zelix Core Team
**Status:** Active Development
