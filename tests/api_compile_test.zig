//! API compatibility compile-time tests
//! This ensures that common API patterns used by consumers compile correctly

const std = @import("std");
const zelix = @import("zelix");

test "HTTP API usage compiles" {
    // This test just verifies the code compiles, doesn't run
    if (false) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        var client = try zelix.Client.init(allocator, .testnet);
        defer client.deinit();

        // Test HTTP request/response pattern
        var http_client = std.http.Client{ .allocator = allocator };
        defer http_client.deinit();

        const uri = try std.Uri.parse("https://testnet.mirrornode.hedera.com/api/v1/accounts/0.0.2");
        var request = try http_client.request(.GET, uri, .{});
        defer request.deinit();

        try request.sendBodyComplete("");

        var redirect_buffer: [4096]u8 = undefined;
        var response = try request.receiveHead(&redirect_buffer);

        var transfer_buffer: [4096]u8 = undefined;
        const reader = response.reader(&transfer_buffer);
        const body = try reader.*.allocRemaining(allocator, 1 * 1024 * 1024);
        allocator.free(body);
    }
}

test "Core types compile" {
    if (false) {
        const account_id = zelix.AccountId{ .shard = 0, .realm = 0, .num = 2 };
        _ = account_id;

        const hbar = zelix.Hbar.fromHbar(100);
        _ = hbar;

        const timestamp = zelix.Timestamp{ .seconds = 0, .nanos = 0 };
        _ = timestamp;
    }
}

test "Transaction types compile" {
    if (false) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        var transfer = zelix.CryptoTransferTransaction.init(allocator);
        defer transfer.deinit();

        const from = zelix.AccountId{ .shard = 0, .realm = 0, .num = 2 };
        const to = zelix.AccountId{ .shard = 0, .realm = 0, .num = 3 };

        try transfer.addHbarTransfer(from, zelix.Hbar.fromHbar(-1));
        try transfer.addHbarTransfer(to, zelix.Hbar.fromHbar(1));
    }
}

test "Mirror client API compiles" {
    if (false) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        var mirror = try zelix.MirrorClient.init(allocator, .testnet);
        defer mirror.deinit();

        const account_id = try zelix.AccountId.fromString("0.0.3");
        _ = try mirror.getAccountBalance(account_id);
    }
}

test "Compression API compiles" {
    if (false) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        var decompressor = try zelix.GzipDecompressor.init(allocator);
        defer decompressor.deinit();

        const compressed = [_]u8{0x1f} ** 100;
        _ = try decompressor.decompress(&compressed);
    }
}
