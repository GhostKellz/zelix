# Zelix Development Roadmap

## Current Status: v0.1.0 (Alpha)

Zelix has achieved a major milestone with **three transport options** (REST, gRPC, Block Streams) and comprehensive transaction streaming support.

---

## ✅ Phase 1: Foundation (COMPLETE)

### Core Types & Data Structures
- [x] AccountId, TransactionId, Timestamp
- [x] Hbar with compile-time arithmetic
- [x] TokenId, FileId, ContractId
- [x] TransactionRecord, TransactionReceipt
- [x] ED25519 key generation and signing
- [x] DER/PEM encoding support

### Mirror Node Integration
- [x] REST client with pagination
- [x] gRPC client for topics (HCS)
- [x] Block Streams client (HIP-1056/1081)
- [x] Account balance/info queries
- [x] Transaction receipts and records
- [x] Token/NFT info and allowances
- [x] File content retrieval

### Transaction Streaming
- [x] REST polling with configurable intervals
- [x] gRPC-style retry logic and exponential backoff
- [x] Block Streams native gRPC streaming
- [x] Duplicate/child transaction filtering
- [x] Unified callback interface across all transports

### Documentation
- [x] Comprehensive README
- [x] Architecture overview
- [x] gRPC transport guide
- [x] Block Streams deep dive
- [x] Example code samples

---

## ✅ Phase 2: Transaction Submission (COMPLETE)

**Priority: HIGH**

### Consensus Node Integration
- [x] Consensus node client (gRPC) ✅
- [x] Transaction signing and submission ✅
- [x] Fee calculation and scheduling ✅
- [x] Transaction status polling ✅
- [x] Receipt verification ✅

### Transaction Types
- [x] Hbar transfers (with execute() methods) ✅
- [x] Account create/update/delete (with execute() methods) ✅
- [x] Token transfers (HTS) (with execute() methods) ✅
- [x] Token creation (with execute() methods) ✅
- [x] Token associate/dissociate (with execute() methods) ✅
- [x] Topic message submission (HCS) (with execute() methods) ✅
- [x] Smart contract create/execute (with execute() methods) ✅

### Error Handling
- [x] Comprehensive error types ✅
- [x] Retry logic for transient failures ✅
- [x] Transaction timeout handling ✅
- [ ] Pre-check validation (future enhancement)

### Developer Experience
- [x] Execute() methods for synchronous transaction submission ✅
- [x] ExecuteAsync() methods for asynchronous submission ✅
- [x] Comprehensive example: examples/send_hbar.zig ✅

**Completed:** 2025-11-16
**Target:** v0.2.0 (Q1 2026)

---

## ✅ Phase 3: Block Streams Enhancement (COMPLETE)

**Priority: MEDIUM**

### Protobuf Parsing
- [x] Full `BlockItem` deserialization ✅
- [x] `event_transaction` → TransactionRecord mapping ✅
- [x] `transaction_result` parsing ✅
- [x] `transaction_output` extraction (contract calls) ✅
- [x] `state_changes` tracking ✅

### Advanced Features
- [x] Block number ↔ timestamp conversion ✅
- [x] Historical block queries (`singleBlock`) ✅
- [x] Block range queries ✅
- [x] Protobuf Reader implementation ✅
- [x] Zero-copy parsing support ✅

### Infrastructure
- [x] Complete protobuf wire format parser (Reader) ✅
- [x] BlockItem parsing methods for all item types ✅
- [x] Helper methods for timestamp/block conversions ✅
- [x] Comprehensive parsing example ✅

### Future Performance Optimizations
- [ ] Streaming decompression (gzip) (future)
- [ ] Connection pooling (future)
- [ ] Async I/O integration (future)

**Completed:** 2025-11-16
**Target:** v0.3.0 (Q2 2026)

---

## 🎯 Phase 4: Smart Contracts & EVM (PLANNED)

**Priority: MEDIUM**

### Contract Interaction
- [ ] Contract deployment
- [ ] Contract function calls
- [ ] Contract queries
- [ ] Event log parsing
- [ ] Gas estimation

### EVM Compatibility
- [ ] Solidity ABI encoding/decoding
- [ ] Ethereum address support
- [ ] EIP-155 transaction signing
- [ ] Web3-style JSON-RPC interface
- [ ] MetaMask wallet integration

### Developer Tools
- [ ] Contract verification
- [ ] Local testing framework
- [ ] Gas profiler
- [ ] Debugger integration

**Target:** v0.4.0 (Q3 2026)

---

## 🔐 Phase 5: Advanced Crypto (PLANNED)

**Priority: LOW**

### Post-Quantum Cryptography
- [ ] Integration with Kriptix (PQC library)
- [ ] Dilithium signatures
- [ ] Kyber key exchange
- [ ] Hybrid classical + PQC schemes

### Hardware Security
- [ ] Ledger hardware wallet support
- [ ] YubiKey integration
- [ ] TPM/secure enclave support
- [ ] HSM compatibility

### Multi-Signature
- [ ] Threshold signatures
- [ ] Key rotation
- [ ] Social recovery schemes

**Target:** v0.5.0 (Q4 2026)

---

## 🌐 Phase 6: Cross-Platform & Interop (PLANNED)

**Priority: LOW**

### WebAssembly
- [ ] WASI build target
- [ ] Browser compatibility layer
- [ ] JavaScript bindings
- [ ] NPM package

### C FFI
- [ ] C header generation
- [ ] Shared library builds
- [ ] Python bindings (via ctypes)
- [ ] Node.js native addon

### Mobile
- [ ] iOS framework
- [ ] Android JNI bindings
- [ ] React Native module

**Target:** v0.6.0 (2027)

---

## 🚀 Phase 7: Ecosystem & Tooling (FUTURE)

### Developer Experience
- [ ] CLI tool (`zelix-cli`)
- [ ] VS Code extension
- [ ] Language server protocol (LSP)
- [ ] Code generators

### Infrastructure
- [ ] Hosted Block Node service
- [ ] Mirror node indexer
- [ ] Transaction explorer
- [ ] Analytics dashboard

### Community
- [ ] Plugin system
- [ ] Third-party integrations
- [ ] Developer tutorials
- [ ] Example dApps

**Target:** v1.0.0 (2027+)

---

## Immediate Next Steps (Priority Order)

### 1. Transaction Submission (Week 1-2)
```zig
// Goal: This should work
const transfer = zelix.TransferTransaction{};
transfer.addHbarTransfer(.{ .shard = 0, .realm = 0, .num = 2 }, hbar(-10));
transfer.addHbarTransfer(.{ .shard = 0, .realm = 0, .num = 3 }, hbar(10));

const receipt = try transfer.execute(&client);
```

**Tasks:**
- [ ] Implement `ConsensusClient` with gRPC
- [ ] Add transaction builders
- [ ] Sign and submit transactions
- [ ] Poll for receipts

### 2. Block Stream Protobuf Parser (Week 3-4)
```zig
// Goal: Parse actual transactions from block items
const tx_record = try parseBlockItemTransaction(allocator, block_item_data);
defer tx_record.deinit(allocator);
```

**Tasks:**
- [ ] Implement protobuf wire format parser
- [ ] Map `event_transaction` to `TransactionRecord`
- [ ] Extract consensus timestamp, result, fee
- [ ] Parse transfer lists

### 3. Testing & Examples (Week 5-6)
```bash
# Goal: Comprehensive test coverage
zig build test                    # Unit tests pass
zig build integration             # Live network tests pass
zig run examples/send_hbar.zig    # Transaction submission works
```

**Tasks:**
- [ ] Add transaction submission tests
- [ ] Block stream parsing tests
- [ ] End-to-end integration tests
- [ ] Performance benchmarks

### 4. Documentation & Release (Week 7-8)
```markdown
# Goal: v0.2.0 release with transaction support
- Updated README with transaction examples
- Migration guide from v0.1 → v0.2
- Blog post announcing release
- Community feedback collection
```

**Tasks:**
- [ ] Update all documentation
- [ ] Create migration guide
- [ ] Write release notes
- [ ] Tag v0.2.0 release

---

## Success Metrics

### Technical
- ✅ Zero segfaults
- ✅ <1% test failure rate
- [ ] >80% code coverage
- [ ] <10ms average query latency
- [ ] <100ms p99 transaction submission

### Adoption
- [ ] 10+ GitHub stars
- [ ] 5+ external contributors
- [ ] 3+ production users
- [ ] Listed on Hedera developer portal

### Community
- [ ] Discord with 50+ members
- [ ] 100+ downloads
- [ ] Featured in Hedera blog
- [ ] Conference presentation

---

## Contributing to the Roadmap

Have ideas for Zelix? We'd love to hear from you!

1. **Vote on priorities:** Comment on issues with 👍/👎
2. **Suggest features:** Open an issue with the `enhancement` label
3. **Contribute code:** Pick an item from Phase 2 and submit a PR
4. **Provide feedback:** Share your use case in Discussions

---

**Last Updated:** 2025-11-16
**Next Review:** 2026-01-01
