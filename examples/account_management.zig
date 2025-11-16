const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize client
    var client = try zelix.Client.init(allocator, .testnet);

    // Example 1: Query account balance
    std.debug.print("=== Account Balance Query ===\n", .{});
    const account_id = try zelix.AccountId.fromString("0.0.3");
    var balance_query = zelix.AccountBalanceQuery{};
    _ = balance_query.setAccountId(account_id);
    const balance = try balance_query.execute(&client);
    std.debug.print("Account {} balance: {}\n\n", .{ account_id, balance.hbars });

    // Example 2: Query account info
    std.debug.print("=== Account Info Query ===\n", .{});
    var info_query = zelix.AccountInfoQuery{};
    _ = info_query.setAccountId(account_id);
    const account_info = try info_query.execute(&client);
    std.debug.print("Account {} info: memo='{}', receiver_sig_required={}\n\n", .{
        account_info.account_id,
        std.zig.fmtEscapes(account_info.memo),
        account_info.receiver_sig_required,
    });

    // Example 3: Query account records
    std.debug.print("=== Account Records Query ===\n", .{});
    var records_query = zelix.AccountRecordsQuery{};
    _ = records_query.setAccountId(account_id);
    const account_records = try records_query.execute(&client);
    std.debug.print("Account {} has {} transaction records\n\n", .{
        account_id,
        account_records.records.len,
    });

    // Example 4: Create account transaction (builder pattern)
    std.debug.print("=== Account Create Transaction ===\n", .{});
    const private_key = zelix.PrivateKey.generateEd25519();
    const public_key = private_key.publicKey();

    var create_tx = zelix.AccountCreateTransaction{};
    _ = create_tx
        .setKey(public_key)
        .setInitialBalance(zelix.Hbar.fromHbars(10))
        .setReceiverSigRequired(true)
        .setMemo("Created by Zelix SDK")
        .setMaxAutomaticTokenAssociations(10)
        .setAutoRenewPeriod(7776000); // 90 days

    // Set transaction ID and freeze
    const tx_id = zelix.TransactionId.generate(account_id);
    _ = create_tx.setTransactionId(tx_id);
    try create_tx.freeze();

    // Sign the transaction
    try create_tx.sign(private_key);

    std.debug.print("Created account creation transaction with ID: {}\n", .{tx_id});
    std.debug.print("Transaction bytes length: {}\n\n", .{(try create_tx.toBytes(allocator)).len});

    // Example 5: Update account transaction
    std.debug.print("=== Account Update Transaction ===\n", .{});
    const target_account_id = try zelix.AccountId.fromString("0.0.12345");

    var update_tx = zelix.AccountUpdateTransaction{};
    _ = update_tx
        .setAccountId(target_account_id)
        .setMemo("Updated by Zelix SDK")
        .setReceiverSigRequired(false)
        .setMaxAutomaticTokenAssociations(5);

    const update_tx_id = zelix.TransactionId.generate(account_id);
    _ = update_tx.setTransactionId(update_tx_id);
    try update_tx.freeze();
    try update_tx.sign(private_key);

    std.debug.print("Created account update transaction for account: {}\n\n", .{target_account_id});

    // Example 6: Delete account transaction
    std.debug.print("=== Account Delete Transaction ===\n", .{});
    const delete_account_id = try zelix.AccountId.fromString("0.0.12346");
    const transfer_to_account_id = try zelix.AccountId.fromString("0.0.12347");

    var delete_tx = zelix.AccountDeleteTransaction{};
    _ = delete_tx
        .setAccountId(delete_account_id)
        .setTransferAccountId(transfer_to_account_id);

    const delete_tx_id = zelix.TransactionId.generate(account_id);
    _ = delete_tx.setTransactionId(delete_tx_id);
    try delete_tx.freeze();
    try delete_tx.sign(private_key);

    std.debug.print("Created account deletion transaction for account: {} (transferring to {})\n", .{
        delete_account_id,
        transfer_to_account_id,
    });

    // Example 7: Submit transaction (when consensus client is fully implemented)
    std.debug.print("=== Transaction Submission ===\n", .{});
    std.debug.print("Note: Consensus client returns stub responses until gRPC implementation is complete\n", .{});

    // Submit the create account transaction
    const tx_bytes = try create_tx.toBytes(allocator);
    defer allocator.free(tx_bytes);

    const response = try client.submitTransaction(tx_bytes);
    std.debug.print("Transaction submitted with ID: {}\n", .{response.transaction_id});

    // Get transaction receipt
    const receipt = try client.getTransactionReceipt(response.transaction_id);
    std.debug.print("Transaction status: {}\n", .{@tagName(receipt.status)});

    std.debug.print("\n🎉 All account management operations demonstrated successfully!\n", .{});
}
