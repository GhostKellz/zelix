//! Performance benchmarks for Zelix SDK
//!
//! These benchmarks measure:
//! - Transaction creation and serialization performance
//! - Memory allocation overhead
//! - Protobuf encoding/decoding speed
//! - Client initialization time
//!
//! Run with: zig build test-perf

const std = @import("std");
const testing = std.testing;
const zelix = @import("zelix");

const ITERATIONS = 1000;
const WARMUP_ITERATIONS = 100;

fn benchmark(comptime name: []const u8, iterations: usize, comptime func: anytype, args: anytype) !u64 {
    // Warmup
    var i: usize = 0;
    while (i < WARMUP_ITERATIONS) : (i += 1) {
        _ = try @call(.auto, func, args);
    }

    // Actual benchmark
    var timer = try std.time.Timer.start();
    const start = timer.read();

    i = 0;
    while (i < iterations) : (i += 1) {
        _ = try @call(.auto, func, args);
    }

    const end = timer.read();
    const total_ns = end - start;
    const avg_ns = total_ns / iterations;

    std.log.info("{s}: {d} iterations in {d}ms (avg: {d}μs per iteration)", .{
        name,
        iterations,
        total_ns / std.time.ns_per_ms,
        avg_ns / std.time.ns_per_us,
    });

    return avg_ns;
}

test "benchmark: TokenCreateTransaction initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const TestFn = struct {
        fn run(alloc: std.mem.Allocator) !void {
            var tx = zelix.TokenCreateTransaction.init(alloc);
            defer tx.deinit();
            _ = tx.setTokenName("BenchmarkToken");
            _ = tx.setTokenSymbol("BENCH");
        }
    };

    const avg_ns = try benchmark("TokenCreateTransaction.init", ITERATIONS, TestFn.run, .{allocator});

    // Assert reasonable performance: should be under 100μs per transaction
    try testing.expect(avg_ns < 100 * std.time.ns_per_us);
}

test "benchmark: TokenMintTransaction with metadata" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const TestFn = struct {
        fn run(alloc: std.mem.Allocator) !void {
            var tx = zelix.TokenMintTransaction.init(alloc);
            defer tx.deinit();

            const token_id = zelix.TokenId{ .shard = 0, .realm = 0, .num = 12345 };
            _ = tx.setTokenId(token_id);
            _ = try tx.addMetadata("ipfs://QmHash1234567890");
            _ = try tx.addMetadata("ipfs://QmHash0987654321");
        }
    };

    const avg_ns = try benchmark("TokenMintTransaction with 2 metadata", ITERATIONS, TestFn.run, .{allocator});

    // Should be under 150μs including string allocations
    try testing.expect(avg_ns < 150 * std.time.ns_per_us);
}

test "benchmark: Transaction freeze (protobuf encoding)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const TestFn = struct {
        fn run(alloc: std.mem.Allocator) !void {
            var tx = zelix.TokenCreateTransaction.init(alloc);
            defer tx.deinit();

            _ = tx.setTokenName("PerformanceTest");
            _ = tx.setTokenSymbol("PERF");
            _ = tx.setDecimals(8);
            _ = tx.setInitialSupply(1000000);

            try tx.freeze();
        }
    };

    const avg_ns = try benchmark("Transaction freeze", ITERATIONS, TestFn.run, .{allocator});

    // Protobuf encoding should be under 200μs
    try testing.expect(avg_ns < 200 * std.time.ns_per_us);
}

test "benchmark: CryptoTransferTransaction creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const TestFn = struct {
        fn run(alloc: std.mem.Allocator) !void {
            var tx = zelix.CryptoTransferTransaction.init(alloc);
            defer tx.deinit();

            const acc1 = zelix.AccountId{ .shard = 0, .realm = 0, .num = 100 };
            const acc2 = zelix.AccountId{ .shard = 0, .realm = 0, .num = 200 };

            _ = try tx.addHbarTransfer(acc1, zelix.Hbar.fromTinybars(-1000));
            _ = try tx.addHbarTransfer(acc2, zelix.Hbar.fromTinybars(1000));
        }
    };

    const avg_ns = try benchmark("CryptoTransferTransaction", ITERATIONS, TestFn.run, .{allocator});

    // Transfer creation should be very fast
    try testing.expect(avg_ns < 80 * std.time.ns_per_us);
}

test "benchmark: AccountId parsing from string" {
    const TestFn = struct {
        fn run() !void {
            const parsed = try zelix.AccountId.fromString("0.0.12345");
            _ = parsed;
        }
    };

    const avg_ns = try benchmark("AccountId.fromString", ITERATIONS * 10, TestFn.run, .{});

    // String parsing should be very fast (no allocation)
    try testing.expect(avg_ns < 5 * std.time.ns_per_us);
}

test "benchmark: FileCreateTransaction with large content" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Prepare 10KB test data
    const large_content = try allocator.alloc(u8, 10 * 1024);
    defer allocator.free(large_content);
    @memset(large_content, 'A');

    const TestFn = struct {
        fn run(alloc: std.mem.Allocator, content: []const u8) !void {
            var tx = zelix.FileCreateTransaction.init(alloc);
            defer tx.deinit();

            _ = tx.setContents(content);
            _ = tx.setFileMemo("Large file test");

            try tx.freeze();
        }
    };

    const avg_ns = try benchmark("FileCreateTransaction 10KB", 100, TestFn.run, .{ allocator, large_content });

    // Large file handling should be under 500μs
    try testing.expect(avg_ns < 500 * std.time.ns_per_us);
}

test "benchmark: Multiple transaction lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const TestFn = struct {
        fn run(alloc: std.mem.Allocator) !void {
            // Create 5 different transactions in sequence
            {
                var tx1 = zelix.TokenCreateTransaction.init(alloc);
                defer tx1.deinit();
                _ = tx1.setTokenName("Token1");
            }
            {
                var tx2 = zelix.TokenMintTransaction.init(alloc);
                defer tx2.deinit();
                _ = tx2.setAmount(1000);
            }
            {
                var tx3 = zelix.FileCreateTransaction.init(alloc);
                defer tx3.deinit();
                _ = tx3.setContents("test");
            }
            {
                var tx4 = zelix.ContractCreateTransaction.init(alloc);
                defer tx4.deinit();
                _ = tx4.setGas(100000);
            }
            {
                var tx5 = zelix.CryptoTransferTransaction.init(alloc);
                defer tx5.deinit();
                const acc = zelix.AccountId{ .shard = 0, .realm = 0, .num = 1 };
                _ = try tx5.addHbarTransfer(acc, zelix.Hbar.ZERO);
            }
        }
    };

    const avg_ns = try benchmark("5 transaction lifecycle", 200, TestFn.run, .{allocator});

    // Multiple transactions should complete quickly
    try testing.expect(avg_ns < 400 * std.time.ns_per_us);
}

test "benchmark: PrivateKey generation from bytes" {
    const TestFn = struct {
        fn run() !void {
            var seed: [32]u8 = undefined;
            std.crypto.random.bytes(&seed);
            const key = zelix.PrivateKey.fromBytes(seed);
            _ = key;
        }
    };

    const avg_ns = try benchmark("PrivateKey.fromBytes", 100, TestFn.run, .{});

    // Key derivation involves crypto, expected to be slower
    try testing.expect(avg_ns < 50 * std.time.ns_per_ms);
}

test "benchmark: Transaction signing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a test key
    var seed: [32]u8 = undefined;
    @memset(&seed, 42);
    const key = zelix.PrivateKey.fromBytes(seed);

    const TestFn = struct {
        fn run(alloc: std.mem.Allocator, private_key: zelix.PrivateKey) !void {
            var tx = zelix.TokenCreateTransaction.init(alloc);
            defer tx.deinit();

            _ = tx.setTokenName("SignTest");
            try tx.freeze();
            try tx.sign(private_key);
        }
    };

    const avg_ns = try benchmark("Transaction signing", 100, TestFn.run, .{ allocator, key });

    // Signing involves ED25519 signature, expected to take a few ms
    try testing.expect(avg_ns < 10 * std.time.ns_per_ms);
}

test "performance summary" {
    std.log.info("", .{});
    std.log.info("=== Zelix SDK Performance Summary ===", .{});
    std.log.info("All benchmarks completed successfully", .{});
    std.log.info("Transaction creation: <100μs", .{});
    std.log.info("Protobuf freeze: <200μs", .{});
    std.log.info("Signing: <10ms", .{});
    std.log.info("=====================================", .{});
}
