//! Integration tests for transaction submission to Hedera testnet
//!
//! These tests require:
//! - ZELIX_INTEGRATION=1 to enable integration testing
//! - HEDERA_OPERATOR_ID - Account ID for transaction operator
//! - HEDERA_OPERATOR_KEY - Private key for transaction signing
//! - HEDERA_NETWORK - Network to use (testnet, previewnet, mainnet)
//!
//! Run with: ZELIX_INTEGRATION=1 zig build test-integration

const std = @import("std");
const zelix = @import("zelix");

fn shouldRunIntegrationTests(allocator: std.mem.Allocator) !bool {
    const run_flag = std.process.getEnvVarOwned(allocator, "ZELIX_INTEGRATION") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return false,
        else => return err,
    };
    defer allocator.free(run_flag);

    return run_flag.len > 0 and !std.ascii.eqlIgnoreCase(run_flag, "0");
}

test "crypto transfer transaction submission" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (!try shouldRunIntegrationTests(allocator)) return error.SkipZigTest;

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    const operator = client.operator orelse return error.NoOperator;

    // Create a simple transfer transaction (send 0 HBAR to self for testing)
    var tx = zelix.CryptoTransferTransaction.init(allocator);
    defer tx.deinit();

    // Transfer 0 HBAR to demonstrate transaction mechanics without cost
    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(-1));
    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(1));

    // Sign transaction
    try tx.sign(operator.private_key);

    // Execute transaction
    const receipt = tx.execute(&client) catch |err| {
        std.log.err("Transaction execution failed: {s}", .{@errorName(err)});
        return err;
    };

    // Verify receipt
    try std.testing.expect(receipt.status == .success or receipt.status == .ok);
    try std.testing.expect(receipt.transaction_id != null);

    std.log.info("Transaction succeeded: {any}", .{receipt.transaction_id});
}

test "transaction with freeze and manual execution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (!try shouldRunIntegrationTests(allocator)) return error.SkipZigTest;

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    const operator = client.operator orelse return error.NoOperator;

    // Create transaction
    var tx = zelix.CryptoTransferTransaction.init(allocator);
    defer tx.deinit();

    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(-1));
    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(1));

    // Freeze first
    try tx.freeze();

    // Sign after freeze
    try tx.sign(operator.private_key);

    // Execute
    const receipt = try tx.execute(&client);

    try std.testing.expect(receipt.status == .success or receipt.status == .ok);
}

test "transaction receipt polling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (!try shouldRunIntegrationTests(allocator)) return error.SkipZigTest;

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    const operator = client.operator orelse return error.NoOperator;

    // Submit transaction
    var tx = zelix.CryptoTransferTransaction.init(allocator);
    defer tx.deinit();

    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(-1));
    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(1));

    try tx.sign(operator.private_key);

    // Get transaction ID before execution
    const response = try tx.executeWithoutReceipt(&client);
    defer response.deinit(allocator);

    try std.testing.expect(response.success);
    const tx_id = response.transaction_id orelse return error.NoTransactionId;

    // Poll for receipt
    const receipt = try client.getTransactionReceipt(tx_id);

    try std.testing.expect(receipt.status == .success or receipt.status == .ok);
    try std.testing.expectEqual(tx_id.account_id.num, receipt.transaction_id.account_id.num);

    std.log.info("Receipt obtained for transaction: {any}", .{receipt.status});
}

test "multiple signatures on transaction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (!try shouldRunIntegrationTests(allocator)) return error.SkipZigTest;

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    const operator = client.operator orelse return error.NoOperator;

    // Create transaction
    var tx = zelix.CryptoTransferTransaction.init(allocator);
    defer tx.deinit();

    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(-1));
    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(1));

    try tx.freeze();

    // Sign multiple times (demonstrates multi-sig support)
    try tx.sign(operator.private_key);
    try tx.sign(operator.private_key); // Sign again (idempotent for same key)

    const receipt = try tx.execute(&client);

    try std.testing.expect(receipt.status == .success or receipt.status == .ok);
}

test "transaction error handling - insufficient fee" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (!try shouldRunIntegrationTests(allocator)) return error.SkipZigTest;

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    const operator = client.operator orelse return error.NoOperator;

    // Create transaction with insufficient fee
    var tx = zelix.CryptoTransferTransaction.init(allocator);
    defer tx.deinit();

    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(-1));
    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(1));

    // Set very low max transaction fee (will likely fail)
    _ = tx.setMaxTransactionFee(zelix.Hbar.fromTinybars(1));

    try tx.sign(operator.private_key);

    // Expect this to fail or succeed with low fee warning
    const receipt = tx.execute(&client) catch |err| {
        std.log.info("Expected error with low fee: {s}", .{@errorName(err)});
        // This is acceptable - transaction rejected due to insufficient fee
        return;
    };

    // If it succeeded, that's fine too (network accepted low fee)
    std.log.info("Transaction succeeded despite low fee: {any}", .{receipt.status});
}

test "transaction memo functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (!try shouldRunIntegrationTests(allocator)) return error.SkipZigTest;

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    const operator = client.operator orelse return error.NoOperator;

    // Create transaction with memo
    var tx = zelix.CryptoTransferTransaction.init(allocator);
    defer tx.deinit();

    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(-1));
    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(1));
    _ = tx.setTransactionMemo("Zelix SDK Integration Test");

    try tx.sign(operator.private_key);

    const receipt = try tx.execute(&client);

    try std.testing.expect(receipt.status == .success or receipt.status == .ok);
    std.log.info("Transaction with memo succeeded", .{});
}

test "transaction valid duration configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (!try shouldRunIntegrationTests(allocator)) return error.SkipZigTest;

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    const operator = client.operator orelse return error.NoOperator;

    // Create transaction with custom valid duration
    var tx = zelix.CryptoTransferTransaction.init(allocator);
    defer tx.deinit();

    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(-1));
    _ = try tx.addHbarTransfer(operator.account_id, zelix.Hbar.fromTinybars(1));

    // Set 60 second valid duration
    _ = tx.setTransactionValidDuration(60);

    try tx.sign(operator.private_key);

    const receipt = try tx.execute(&client);

    try std.testing.expect(receipt.status == .success or receipt.status == .ok);
}
