const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize client (combines both Mirror and Consensus clients)
    var client = try zelix.Client.init(allocator, .testnet);
    defer client.deinit();

    // Example 1: Create a simple Hbar transfer transaction
    std.debug.print("\n=== Example 1: Simple Hbar Transfer ===\n", .{});

    var transfer = zelix.CryptoTransferTransaction.init(allocator);
    defer transfer.deinit();

    // Add transfers (must balance to zero)
    const from_account = zelix.AccountId{ .shard = 0, .realm = 0, .num = 2 };
    const to_account = zelix.AccountId{ .shard = 0, .realm = 0, .num = 3 };

    try transfer.addHbarTransfer(from_account, zelix.Hbar.fromTinybars(-100_000_000)); // -1 HBAR
    try transfer.addHbarTransfer(to_account, zelix.Hbar.fromTinybars(100_000_000));    // +1 HBAR

    // Set transaction properties
    _ = transfer.setMaxTransactionFee(zelix.Hbar.fromHbar(2));
    _ = transfer.setMemo("Payment for services");

    // Generate operator key pair
    const operator_key = try zelix.PrivateKey.generateEd25519(allocator);
    defer operator_key.deinit(allocator);

    // Sign the transaction
    try transfer.sign(operator_key);

    // Execute and get receipt (synchronous)
    std.debug.print("Submitting transaction...\n", .{});
    const receipt = try transfer.execute(&client);

    std.debug.print("Transaction Status: {s}\n", .{@tagName(receipt.status)});
    if (receipt.transaction_id) |tx_id| {
        std.debug.print("Transaction ID: {s}\n", .{tx_id});
    }

    // Example 2: Execute asynchronously (submit without waiting for receipt)
    std.debug.print("\n=== Example 2: Async Transfer ===\n", .{});

    var transfer2 = zelix.CryptoTransferTransaction.init(allocator);
    defer transfer2.deinit();

    try transfer2.addHbarTransfer(from_account, zelix.Hbar.fromTinybars(-50_000_000)); // -0.5 HBAR
    try transfer2.addHbarTransfer(to_account, zelix.Hbar.fromTinybars(50_000_000));    // +0.5 HBAR

    try transfer2.sign(operator_key);

    // Execute asynchronously (returns immediately with transaction response)
    const response = try transfer2.executeAsync(&client);

    std.debug.print("Transaction submitted!\n", .{});
    if (response.transaction_id) |tx_id| {
        std.debug.print("Transaction ID: {s}\n", .{tx_id});

        // Optionally poll for receipt later
        std.debug.print("Polling for receipt...\n", .{});
        const receipt2 = try client.consensus_client.getTransactionReceipt(tx_id);
        std.debug.print("Transaction Status: {s}\n", .{@tagName(receipt2.status)});
    }

    // Example 3: Topic message submission
    std.debug.print("\n=== Example 3: Topic Message Submission ===\n", .{});

    var topic_msg = zelix.TopicMessageSubmitTransaction.init(allocator);
    defer topic_msg.deinit();

    const topic_id = zelix.TopicId{ .shard = 0, .realm = 0, .num = 12345 };
    _ = topic_msg.setTopicId(topic_id);
    _ = try topic_msg.setMessage("Hello from Zelix SDK!");

    try topic_msg.sign(operator_key);

    const topic_receipt = try topic_msg.execute(&client);
    std.debug.print("Topic message submitted: {s}\n", .{@tagName(topic_receipt.status)});

    // Example 4: Token transfer
    std.debug.print("\n=== Example 4: Token Transfer ===\n", .{});

    var token_transfer = try zelix.TokenTransferTransaction.init(allocator);
    defer token_transfer.deinit();

    const token_id = zelix.TokenId{ .shard = 0, .realm = 0, .num = 54321 };
    try token_transfer.addTokenTransfer(token_id, from_account, -1000); // -1000 tokens
    try token_transfer.addTokenTransfer(token_id, to_account, 1000);    // +1000 tokens

    try token_transfer.sign(operator_key);

    const token_receipt = try token_transfer.execute(&client);
    std.debug.print("Token transfer completed: {s}\n", .{@tagName(token_receipt.status)});

    std.debug.print("\n✅ All examples completed successfully!\n", .{});
}
