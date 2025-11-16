# Examples

This document shows common Zelix usage patterns, inspired by the official Hedera SDKs.

## Setup

```zig
const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize client
    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    // Or specify network
    // var client = try zelix.Client.init(allocator, .testnet);
}
```

## Account Operations

### Get Account Balance

```zig
// Parse account ID
const account_id = try zelix.AccountId.fromString("0.0.12345");

// Query balance
var query = zelix.AccountBalanceQuery{};
query.setAccountId(account_id);
const balance = try query.execute(&client);

std.debug.print("Balance: {}\n", .{balance.hbars});
```

### Get Account Info

```zig
// Query detailed account information
var info_query = zelix.AccountInfoQuery{};
_ = info_query.setAccountId(account_id);
const account_info = try info_query.execute(&client);

std.debug.print("Account: {}\n", .{account_info.account_id});
std.debug.print("Memo: {s}\n", .{account_info.memo});
std.debug.print("Receiver sig required: {}\n", .{account_info.receiver_sig_required});
std.debug.print("Ethereum nonce: {}\n", .{account_info.ethereum_nonce});
```

### Get Account Records

```zig
// Query transaction records for an account
var records_query = zelix.AccountRecordsQuery{};
_ = records_query.setAccountId(account_id);
const account_records = try records_query.execute(&client);

std.debug.print("Found {} transaction records\n", .{account_records.records.len});
for (account_records.records) |record| {
    std.debug.print("TX: {} - Fee: {}\n", .{record.transaction_id, record.transaction_fee});
}
```

### Create Account

```zig
// Generate new key pair
const private_key = zelix.PrivateKey.generateEd25519();
const public_key = private_key.publicKey();

// Create account with initial balance and settings
var create_tx = zelix.AccountCreateTransaction{};
_ = create_tx
    .setKey(public_key)
    .setInitialBalance(zelix.Hbar.fromHbars(10))  // 10 HBAR
    .setReceiverSigRequired(true)
    .setMemo("Created by Zelix SDK")
    .setMaxAutomaticTokenAssociations(10)
    .setAutoRenewPeriod(7776000)  // 90 days in seconds
    .setDeclineStakingReward(false);

// Set transaction ID
const tx_id = zelix.TransactionId.generate(your_account_id);
_ = create_tx.setTransactionId(tx_id);

// Freeze and sign
try create_tx.freeze();
try create_tx.sign(your_private_key);

// Submit (when consensus client is implemented)
// const response = try client.submitTransaction(try create_tx.toBytes(allocator));
```

### Update Account

```zig
// Update account properties
var update_tx = zelix.AccountUpdateTransaction{};
_ = update_tx
    .setAccountId(target_account_id)
    .setMemo("Updated account memo")
    .setReceiverSigRequired(false)
    .setMaxAutomaticTokenAssociations(5)
    .setAutoRenewPeriod(2592000)  // 30 days
    .setDeclineStakingReward(true);

// Set transaction ID
const tx_id = zelix.TransactionId.generate(your_account_id);
_ = update_tx.setTransactionId(tx_id);

// Freeze and sign
try update_tx.freeze();
try update_tx.sign(your_private_key);

// Submit transaction
```

### Delete Account

```zig
// Delete account and transfer remaining balance
var delete_tx = zelix.AccountDeleteTransaction{};
_ = delete_tx
    .setAccountId(account_to_delete_id)
    .setTransferAccountId(transfer_to_account_id);

// Set transaction ID
const tx_id = zelix.TransactionId.generate(your_account_id);
_ = delete_tx.setTransactionId(tx_id);

// Freeze and sign
try delete_tx.freeze();
try delete_tx.sign(account_private_key);  // Must be signed by account being deleted

// Submit transaction
```

## Token Operations

### Transfer Tokens

```zig
var tx = zelix.CryptoTransferTransaction.init(allocator);
defer tx.deinit();

// Add token transfer
try tx.addTokenTransfer(token_id, sender_account, -100);
try tx.addTokenTransfer(token_id, receiver_account, 100);

// Add hbar fee
try tx.addHbarTransfer(sender_account, zelix.Hbar.fromTinybars(-1000));
try tx.addHbarTransfer(receiver_account, zelix.Hbar.fromTinybars(1000));

try tx.setTransactionId(zelix.TransactionId.generate(sender_account));
try tx.freeze();
try tx.sign(sender_private_key);

// Submit transaction
```

### Inspect NFT Ownership

```zig
var client = try zelix.Client.initFromEnv(allocator);
defer client.deinit();

const token_id = try zelix.TokenId.fromString("0.0.6001");
const serial: u64 = 42;

var nft = try client.getNftInfo(token_id, serial);
defer nft.deinit(allocator);

std.debug.print("Owner: {}\n", .{nft.owner_account_id});
if (nft.spender_account_id) |spender| {
    std.debug.print("Approved spender: {}\n", .{spender});
}

var allowances = try client.getTokenNftAllowances(nft.owner_account_id, .{
    .token_id = token_id,
    .limit = 10,
});
defer allowances.deinit(allocator);

std.debug.print("Allowance entries: {}\n", .{allowances.allowances.len});
```

## Consensus Service (HCS)

A full end-to-end topic message walkthrough is available in `examples/topic_message.zig`.

### Submit Topic Message

```zig
var tx = zelix.TopicMessageSubmitTransaction.init(allocator);
defer tx.deinit();

try tx.setTopicId(topic_id);
try tx.setMessage("Hello, Hedera!");
try tx.setTransactionId(zelix.TransactionId.generate(sender_account));

try tx.freeze();
try tx.sign(sender_private_key);

// Submit
```

### Read Topic Messages

```zig
var mirror = try zelix.MirrorClient.init(allocator, .testnet);
defer mirror.deinit();

// Get recent messages
const result = try mirror.getTopicMessages(topic_id, 10, null);
defer {
    allocator.free(result.messages);
    if (result.next) |n| allocator.free(n);
}

for (result.messages) |msg| {
    std.debug.print("Seq {}: {s}\n", .{msg.sequence_number, msg.message});
}
```

### Subscribe to Topic

```zig
// Polling subscription
try mirror.subscribeTopic(topic_id, struct {
    fn callback(msg: zelix.TopicMessage) void {
        std.debug.print("New message: {s}\n", .{msg.message});
    }
}.callback);
```

## Smart Contracts

*(Planned - not yet implemented)*

```zig
// Query contract
const query = zelix.ContractCallQuery.init()
    .setContractId(contract_id)
    .setGas(100000)
    .setFunction("getValue");

const result = try query.execute(&client);

// Execute contract
const tx = zelix.ContractExecuteTransaction.init()
    .setContractId(contract_id)
    .setGas(1000000)
    .setFunction("setValue", .{new_value});

try tx.freeze();
try tx.sign(private_key);
// Submit
```

## Key Management

### Generate Keys

```zig
// ED25519 (recommended)
const private_key = zelix.PrivateKey.generateEd25519();
const public_key = private_key.publicKey();

// From bytes
const private_key = zelix.PrivateKey.fromBytes(raw_bytes_32);
```

### Sign/Verify

```zig
const message = "data to sign";
const signature = try private_key.sign(message);
try public_key.verify(message, signature);
```

## Error Handling

```zig
const result = client.getAccountBalance(account_id) catch |err| {
    switch (err) {
        error.Network => std.debug.print("Network error\n", .{}),
        error.Decode => std.debug.print("JSON parse error\n", .{}),
        error.InvalidId => std.debug.print("Invalid account ID\n", .{}),
        else => std.debug.print("Other error: {}\n", .{err}),
    }
    return err;
};
```

## Environment Configuration

```bash
# Set network
export HEDERA_NETWORK=testnet  # mainnet, testnet, previewnet

# Optional: operator account (for transactions)
export HEDERA_OPERATOR_ID=0.0.12345
export HEDERA_OPERATOR_KEY=302e020100300506032b657004220420...
```

## Complete Example

See `examples/account_balance.zig`, `examples/topic_message.zig`, and `examples/nft_lookup.zig` for runnable examples.