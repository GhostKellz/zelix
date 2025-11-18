//! Error handling tests for zelix transactions
//! Tests various error conditions and edge cases

const std = @import("std");
const testing = std.testing;
const zelix = @import("zelix");

test "TokenCreateTransaction - validates required fields" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var tx = zelix.TokenCreateTransaction.init(allocator);
    defer tx.deinit();

    // Should be able to freeze even with minimal fields
    // (network will reject, but SDK allows it)
    try tx.freeze();
}

test "TokenMintTransaction - handles empty metadata" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var tx = zelix.TokenMintTransaction.init(allocator);
    defer tx.deinit();

    const token_id = zelix.TokenId{ .shard = 0, .realm = 0, .num = 12345 };
    _ = tx.setTokenId(token_id);

    // Empty metadata should be allowed
    _ = try tx.addMetadata("");
    try tx.freeze();
}

test "FileCreateTransaction - handles large content" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var tx = zelix.FileCreateTransaction.init(allocator);
    defer tx.deinit();

    // Create 10KB of content
    const large_content = try allocator.alloc(u8, 10 * 1024);
    defer allocator.free(large_content);
    @memset(large_content, 'A');

    _ = tx.setContents(large_content);
    try tx.freeze();
}

test "AccountId - parsing validation" {
    // Valid format
    const valid = try zelix.AccountId.fromString("0.0.12345");
    try testing.expectEqual(@as(u64, 0), valid.shard);
    try testing.expectEqual(@as(u64, 0), valid.realm);
    try testing.expectEqual(@as(u64, 12345), valid.num);

    // Invalid formats should error
    const invalid_cases = [_][]const u8{
        "invalid",
        "0.0",
        "0.0.abc",
        ".0.12345",
        "0..12345",
    };

    for (invalid_cases) |invalid| {
        const result = zelix.AccountId.fromString(invalid);
        try testing.expectError(error.InvalidAccountId, result);
    }
}

test "Multiple freeze calls - idempotent" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var tx = zelix.TokenCreateTransaction.init(allocator);
    defer tx.deinit();

    _ = tx.setTokenName("Test");
    _ = tx.setTokenSymbol("TST");

    // Multiple freeze calls should be safe
    try tx.freeze();
    try tx.freeze();
    try tx.freeze();
}

test "Transaction builder - handles multiple signatures" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var tx = zelix.TokenCreateTransaction.init(allocator);
    defer tx.deinit();

    _ = tx.setTokenName("MultiSig");

    try tx.freeze();

    // Generate test keys
    var seed: [32]u8 = undefined;
    @memset(&seed, 42);
    const key1 = zelix.PrivateKey.fromBytes(seed);

    @memset(&seed, 43);
    const key2 = zelix.PrivateKey.fromBytes(seed);

    // Multiple signatures should be allowed
    try tx.sign(key1);
    try tx.sign(key2);
}

test "CryptoTransferTransaction - validates balanced transfers" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var tx = zelix.CryptoTransferTransaction.init(allocator);
    defer tx.deinit();

    const acc1 = zelix.AccountId{ .shard = 0, .realm = 0, .num = 100 };
    const acc2 = zelix.AccountId{ .shard = 0, .realm = 0, .num = 200 };

    // Balanced transfer
    _ = try tx.addHbarTransfer(acc1, zelix.Hbar.fromTinybars(-100));
    _ = try tx.addHbarTransfer(acc2, zelix.Hbar.fromTinybars(100));

    try tx.freeze();
}

test "Hbar - conversion functions" {
    const one_hbar = zelix.Hbar.fromHbar(1);
    const hundred_million_tinybars = zelix.Hbar.fromTinybars(100_000_000);

    try testing.expectEqual(one_hbar.tinybars, hundred_million_tinybars.tinybars);

    // Zero value
    const zero = zelix.Hbar.ZERO;
    try testing.expectEqual(@as(i64, 0), zero.tinybars);
}

test "ContractCreateTransaction - handles bytecode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var tx = zelix.ContractCreateTransaction.init(allocator);
    defer tx.deinit();

    // Empty bytecode
    _ = tx.setBytecode(&[_]u8{});
    try tx.freeze();

    // Valid bytecode
    const bytecode = [_]u8{ 0x60, 0x80, 0x60, 0x40, 0x52 };
    _ = tx.setBytecode(&bytecode);
}
