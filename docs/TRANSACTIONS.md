# Zelix Transaction API Documentation

## Overview
Zelix provides comprehensive support for all Hedera transaction types. All transactions follow a consistent builder pattern with fluent APIs.

## Common Pattern

All transactions follow this pattern:

```zig
const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Initialize client
    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    // 2. Create transaction
    var tx = zelix.TokenCreateTransaction.init(allocator);
    defer tx.deinit();

    // 3. Set parameters (fluent API)
    _ = tx.setTokenName("MyToken");
    _ = tx.setTokenSymbol("MTK");

    // 4. Sign transaction
    const operator = client.operator orelse return error.NoOperator;
    try tx.sign(operator.private_key);

    // 5. Execute
    const receipt = try tx.execute(&client);
}
```

---

## Token Transactions (HTS)

### TokenCreateTransaction

Create a new fungible or non-fungible token.

**Required Fields:**
- `name` - Token name
- `symbol` - Token symbol
- `tokenType` - `.fungible_common` or `.non_fungible_unique`
- `treasuryAccountId` - Treasury account

**Optional Fields:**
- `decimals` - For fungible tokens (default: 0)
- `initialSupply` - Initial token supply
- `supplyType` - `.infinite` or `.finite`
- `maxSupply` - Maximum supply (required if finite)
- `adminKey` - Admin key for token management
- `kycKey` - KYC key
- `freezeKey` - Freeze key
- `wipeKey` - Wipe key
- `supplyKey` - Supply key (required for minting)
- `freezeDefault` - Default freeze status
- `expirationTime` - Token expiration timestamp
- `autoRenewAccount` - Auto-renew account
- `autoRenewPeriod` - Auto-renew period in seconds
- `memo` - Token memo

**Example:**
```zig
var tx = zelix.TokenCreateTransaction.init(allocator);
defer tx.deinit();

_ = tx.setTokenName("My NFT Collection");
_ = tx.setTokenSymbol("MNFT");
_ = tx.setTokenType(.non_fungible_unique);
_ = tx.setSupplyType(.infinite);
_ = tx.setTreasuryAccountId(treasury_account);
_ = tx.setAdminKey(admin_key);
_ = tx.setSupplyKey(supply_key);

try tx.sign(private_key);
const receipt = try tx.execute(&client);
const token_id = receipt.token_id orelse return error.NoTokenId;
```

---

### TokenMintTransaction

Mint new tokens or NFTs.

**Required Fields:**
- `tokenId` - The token to mint

**For Fungible Tokens:**
- `amount` - Amount to mint

**For NFTs:**
- `metadata` - Array of metadata (one per NFT)

**Example (NFT):**
```zig
var tx = zelix.TokenMintTransaction.init(allocator);
defer tx.deinit();

_ = tx.setTokenId(token_id);
_ = try tx.addMetadata("ipfs://QmHash1");
_ = try tx.addMetadata("ipfs://QmHash2");

try tx.sign(supply_key);
const receipt = try tx.execute(&client);
const serial_numbers = receipt.serial_numbers orelse return error.NoSerialNumbers;
```

**Example (Fungible):**
```zig
var tx = zelix.TokenMintTransaction.init(allocator);
defer tx.deinit();

_ = tx.setTokenId(token_id);
_ = tx.setAmount(1000000); // Mint 1,000,000 tokens

try tx.sign(supply_key);
const receipt = try tx.execute(&client);
```

---

### TokenBurnTransaction

Burn tokens or NFTs from the treasury.

**Required Fields:**
- `tokenId` - The token to burn

**For Fungible:**
- `amount` - Amount to burn

**For NFTs:**
- `serialNumbers` - Array of serial numbers to burn

**Example:**
```zig
var tx = zelix.TokenBurnTransaction.init(allocator);
defer tx.deinit();

_ = tx.setTokenId(token_id);
_ = try tx.addSerialNumber(1);
_ = try tx.addSerialNumber(2);

try tx.sign(supply_key);
const receipt = try tx.execute(&client);
```

---

### TokenAssociateTransaction

Associate tokens with an account before it can receive them.

**Required Fields:**
- `accountId` - Account to associate
- `tokenIds` - List of tokens to associate

**Example:**
```zig
var tx = zelix.TokenAssociateTransaction.init(allocator);
defer tx.deinit();

_ = tx.setAccountId(account_id);
_ = try tx.addTokenId(token_id1);
_ = try tx.addTokenId(token_id2);

try tx.sign(account_private_key);
const receipt = try tx.execute(&client);
```

---

### TokenDissociateTransaction

Remove token association from an account.

**Required Fields:**
- `accountId` - Account to dissociate
- `tokenIds` - List of tokens to dissociate

**Example:**
```zig
var tx = zelix.TokenDissociateTransaction.init(allocator);
defer tx.deinit();

_ = tx.setAccountId(account_id);
_ = try tx.addTokenId(token_id);

try tx.sign(account_private_key);
const receipt = try tx.execute(&client);
```

---

### Other Token Transactions

- **TokenUpdateTransaction** - Update token properties
- **TokenDeleteTransaction** - Mark token as deleted
- **TokenWipeTransaction** - Wipe token balance from account
- **TokenFreezeTransaction** - Freeze account for token
- **TokenUnfreezeTransaction** - Unfreeze account
- **TokenPauseTransaction** - Pause all token operations
- **TokenUnpauseTransaction** - Unpause token

See source code for detailed field documentation.

---

## File Service Transactions (HFS)

### FileCreateTransaction

Create a new file on Hedera File Service.

**Required Fields:**
- `contents` - File contents (bytes)

**Optional Fields:**
- `keys` - List of keys that can modify the file
- `expirationTime` - File expiration timestamp
- `memo` - File memo

**Example:**
```zig
var tx = zelix.FileCreateTransaction.init(allocator);
defer tx.deinit();

const content = "Hello, Hedera!";
_ = tx.setContents(content);
_ = try tx.addKey(admin_key);
_ = tx.setFileMemo("My first file");

try tx.sign(private_key);
const receipt = try tx.execute(&client);
const file_id = receipt.file_id orelse return error.NoFileId;
```

---

### FileAppendTransaction

Append data to an existing file.

**Required Fields:**
- `fileId` - The file to append to
- `contents` - Data to append

**Example:**
```zig
var tx = zelix.FileAppendTransaction.init(allocator);
defer tx.deinit();

_ = tx.setFileId(file_id);
_ = tx.setContents("\nAppended data");

try tx.sign(file_key);
const receipt = try tx.execute(&client);
```

---

### FileUpdateTransaction

Update file contents, keys, or expiration.

**Required Fields:**
- `fileId` - The file to update

**Optional Fields:**
- `contents` - New contents
- `keys` - New key list
- `expirationTime` - New expiration
- `memo` - New memo

---

### FileDeleteTransaction

Mark a file as deleted.

**Required Fields:**
- `fileId` - The file to delete

---

## Schedule Service Transactions

### ScheduleCreateTransaction

Create a scheduled transaction for future execution.

**Required Fields:**
- `scheduledTransactionBody` - The transaction to schedule

**Optional Fields:**
- `memo` - Schedule memo
- `adminKey` - Admin key to manage schedule
- `payerAccountId` - Payer for the scheduled transaction
- `expirationTime` - When schedule expires
- `waitForExpiry` - Wait until expiry before executing

**Example:**
```zig
// First, create the transaction to schedule
var transfer_tx = zelix.CryptoTransferTransaction.init(allocator);
_ = try transfer_tx.addHbarTransfer(from, zelix.Hbar.fromHbar(-10));
_ = try transfer_tx.addHbarTransfer(to, zelix.Hbar.fromHbar(10));
try transfer_tx.freeze();
const tx_bytes = try transfer_tx.builder.toBytes();
defer allocator.free(tx_bytes);

// Schedule it
var schedule_tx = zelix.ScheduleCreateTransaction.init(allocator);
defer schedule_tx.deinit();

_ = try schedule_tx.setScheduledTransactionBody(tx_bytes);
_ = schedule_tx.setScheduleMemo("Delayed payment");

try schedule_tx.sign(private_key);
const receipt = try schedule_tx.execute(&client);
const schedule_id = receipt.schedule_id orelse return error.NoScheduleId;
```

---

### ScheduleSignTransaction

Add signature to a scheduled transaction.

**Required Fields:**
- `scheduleId` - The schedule to sign

---

### ScheduleDeleteTransaction

Delete a scheduled transaction.

**Required Fields:**
- `scheduleId` - The schedule to delete

---

## Smart Contract Transactions

### ContractCreateTransaction

Deploy a smart contract.

**Required Fields:**
- `bytecode` - Contract bytecode
- `gas` - Gas limit

**Optional Fields:**
- `constructorParameters` - Constructor params
- `initialBalance` - Initial HBAR balance
- `adminKey` - Contract admin key
- `memo` - Contract memo
- `maxAutomaticTokenAssociations` - Max auto token associations
- `autoRenewPeriod` - Auto-renew period
- `autoRenewAccountId` - Auto-renew account
- `stakedAccountId` / `stakedNodeId` - Staking settings

**Example:**
```zig
var tx = zelix.ContractCreateTransaction.init(allocator);
defer tx.deinit();

_ = tx.setBytecode(contract_bytecode);
_ = tx.setGas(100_000);
_ = tx.setInitialBalance(1_000_000); // 0.01 HBAR in tinybars

try tx.sign(private_key);
const receipt = try tx.execute(&client);
const contract_id = receipt.contract_id orelse return error.NoContractId;
```

---

### ContractExecuteTransaction

Call a smart contract function.

**Required Fields:**
- `contractId` - Contract to call
- `gas` - Gas limit

**Optional Fields:**
- `functionParameters` - Encoded function parameters
- `payableAmount` - HBAR to send with call

**Example:**
```zig
var tx = zelix.ContractExecuteTransaction.init(allocator);
defer tx.deinit();

_ = tx.setContractId(contract_id);
_ = tx.setGas(50_000);
_ = tx.setFunctionParameters(encoded_params);

try tx.sign(private_key);
const receipt = try tx.execute(&client);
```

---

### ContractUpdateTransaction

Update contract properties.

**Required Fields:**
- `contractId` - Contract to update

**Optional Fields:**
- `adminKey` - New admin key
- `expirationTime` - New expiration
- `autoRenewPeriod` - New auto-renew period
- `memo` - New memo
- (and other update fields)

---

### ContractDeleteTransaction

Delete a contract and transfer remaining balance.

**Required Fields:**
- `contractId` - Contract to delete

**Optional Fields:**
- `transferAccountId` - Account to receive remaining balance
- `transferContractId` - Contract to receive remaining balance
- `permanentRemoval` - Permanent removal flag

---

## Error Handling

All transactions return errors in the following cases:

1. **Allocation Errors**: `error.OutOfMemory`
2. **Network Errors**: `error.HttpError`, `error.GrpcError`
3. **Validation Errors**: `error.InvalidAccountId`, etc.
4. **Transaction Errors**: Check `receipt.status`

**Example Error Handling:**
```zig
const receipt = tx.execute(&client) catch |err| {
    std.log.err("Transaction failed: {}", .{err});
    return err;
};

if (receipt.status != .success) {
    std.log.err("Transaction rejected: {}", .{receipt.status});
    return error.TransactionFailed;
}
```

---

## Best Practices

1. **Always use defer for cleanup**
   ```zig
   var tx = zelix.TokenCreateTransaction.init(allocator);
   defer tx.deinit(); // Ensures cleanup
   ```

2. **Check receipts for created IDs**
   ```zig
   const token_id = receipt.token_id orelse return error.NoTokenId;
   ```

3. **Use environment variables for configuration**
   ```zig
   var client = try zelix.Client.initFromEnv(allocator);
   ```

4. **Sign with appropriate keys**
   - Token operations: Use supply/admin keys
   - Account operations: Use account private key
   - Multi-sig: Call sign() multiple times

5. **Handle network retries**
   - Client has built-in retry logic
   - Configure with `client.setOptions()`

---

## See Also

- [Client Configuration](./CLIENT.md)
- [Key Management](./KEYS.md)
- [Query API](./QUERIES.md)
- [Error Handling Guide](./ERROR_HANDLING_AUDIT.md)
