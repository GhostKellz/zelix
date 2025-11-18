//! Memory leak tests for all zelix transaction types
//! Run with: zig build test-leaks

const std = @import("std");
const testing = std.testing;
const zelix = @import("zelix");

test "TokenCreateTransaction - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var tx = zelix.TokenCreateTransaction.init(allocator);
        defer tx.deinit();

        _ = tx.setTokenName("TestToken");
        _ = tx.setTokenSymbol("TEST");
        _ = tx.setTokenType(.fungible_common);
        _ = tx.setSupplyType(.infinite);
    }

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "TokenMintTransaction - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var tx = zelix.TokenMintTransaction.init(allocator);
        defer tx.deinit();

        const token_id = zelix.TokenId{ .shard = 0, .realm = 0, .num = 12345 };
        _ = tx.setTokenId(token_id);
        _ = try tx.addMetadata("test metadata");
    }

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "FileCreateTransaction - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var tx = zelix.FileCreateTransaction.init(allocator);
        defer tx.deinit();

        _ = tx.setContents("test file contents");
        _ = tx.setFileMemo("test memo");
    }

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "ScheduleCreateTransaction - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var tx = zelix.ScheduleCreateTransaction.init(allocator);
        defer tx.deinit();

        _ = tx.setScheduleMemo("test schedule");
        _ = tx.setWaitForExpiry(false);
    }

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "ContractCreateTransaction - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var tx = zelix.ContractCreateTransaction.init(allocator);
        defer tx.deinit();

        _ = tx.setBytecode(&[_]u8{ 0x60, 0x60, 0x60, 0x40 }); // minimal bytecode
        _ = tx.setGas(100000);
        _ = tx.setContractMemo("test contract");
    }

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "CryptoTransferTransaction - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var tx = zelix.CryptoTransferTransaction.init(allocator);
        defer tx.deinit();

        const account1 = zelix.AccountId{ .shard = 0, .realm = 0, .num = 100 };
        const account2 = zelix.AccountId{ .shard = 0, .realm = 0, .num = 200 };

        _ = try tx.addHbarTransfer(account1, zelix.Hbar.fromTinybars(-100));
        _ = try tx.addHbarTransfer(account2, zelix.Hbar.fromTinybars(100));
    }

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Multiple transaction lifecycle - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        // Create and destroy multiple transactions
        for (0..10) |_| {
            var token_tx = zelix.TokenCreateTransaction.init(allocator);
            _ = token_tx.setTokenName("Test");
            token_tx.deinit();

            var file_tx = zelix.FileCreateTransaction.init(allocator);
            _ = file_tx.setContents("content");
            file_tx.deinit();

            var contract_tx = zelix.ContractCreateTransaction.init(allocator);
            _ = contract_tx.setGas(50000);
            contract_tx.deinit();
        }
    }

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}

test "Transaction with freeze - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var tx = zelix.TokenCreateTransaction.init(allocator);
        defer tx.deinit();

        _ = tx.setTokenName("FreezeTest");
        _ = tx.setTokenSymbol("FRZ");

        // Freeze allocates internal protobuf buffers
        try tx.freeze();
    }

    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}
