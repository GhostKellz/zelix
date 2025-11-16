const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Zelix Block Stream Parsing Examples ===\n\n", .{});

    // Initialize Block Stream client
    var block_client = try zelix.BlockStreamClient.init(.{
        .allocator = allocator,
        .block_node_endpoint = "testnet.block.hedera.com:443",
    });
    defer block_client.deinit();

    // Example 1: Query a single block and parse its contents
    std.debug.print("=== Example 1: Single Block Query with Parsing ===\n", .{});

    const block_number: u64 = 1000;
    const block = try block_client.getBlock(block_number);
    defer {
        var mutable_block = block;
        mutable_block.deinit(allocator);
    }

    std.debug.print("Block #{d} contains {d} items\n", .{ block.block_number, block.items.len });

    // Parse each item in the block
    for (block.items) |item| {
        switch (item.item_type) {
            .event_transaction => {
                std.debug.print("  Found transaction event\n", .{});
                var tx = try item.parseEventTransaction(allocator);
                defer tx.deinit(allocator);

                std.debug.print("    Transaction ID: 0.0.{d}@{d}.{d}\n", .{
                    tx.transaction_id.account_id.num,
                    tx.transaction_id.valid_start.seconds,
                    tx.transaction_id.valid_start.nanos,
                });
                std.debug.print("    Consensus Timestamp: {d}.{d}\n", .{
                    tx.consensus_timestamp.seconds,
                    tx.consensus_timestamp.nanos,
                });
                std.debug.print("    Transaction Fee: {d} tinybars\n", .{tx.transaction_fee});
                std.debug.print("    Transfers: {d}\n", .{tx.transfers.items.len});

                for (tx.transfers.items) |transfer| {
                    std.debug.print("      0.0.{d}: {d} tinybars\n", .{
                        transfer.account_id.num,
                        transfer.amount,
                    });
                }
            },
            .transaction_result => {
                std.debug.print("  Found transaction result\n", .{});
                const result = try item.parseTransactionResult();

                std.debug.print("    Status: {s}\n", .{@tagName(result.status)});
                std.debug.print("    Fee Charged: {d} tinybars\n", .{result.transaction_fee_charged});
                std.debug.print("    Timestamp: {d}.{d}\n", .{
                    result.consensus_timestamp.seconds,
                    result.consensus_timestamp.nanos,
                });
            },
            .transaction_output => {
                std.debug.print("  Found transaction output (contract call)\n", .{});
                const output = try item.parseTransactionOutput();

                if (output.contract_call_result) |ccr| {
                    std.debug.print("    Contract: 0.0.{d}\n", .{ccr.contract_id.num});
                    std.debug.print("    Gas Used: {d}\n", .{ccr.gas_used});
                    std.debug.print("    Output Length: {d} bytes\n", .{ccr.output.len});
                    if (ccr.error_message) |err| {
                        std.debug.print("    Error: {s}\n", .{err});
                    }
                }
            },
            .state_changes => {
                std.debug.print("  Found state changes\n", .{});
                var changes = try item.parseStateChanges(allocator);
                defer changes.deinit(allocator);

                std.debug.print("    Total changes: {d}\n", .{changes.items.len});
                for (changes.items) |change| {
                    std.debug.print("      Type: {s}\n", .{@tagName(change.change_type)});
                }
            },
            .header => std.debug.print("  Block header\n", .{}),
            .start_event => std.debug.print("  Start event\n", .{}),
            .state_proof => std.debug.print("  State proof\n", .{}),
            .unknown => std.debug.print("  Unknown item type\n", .{}),
        }
    }

    // Example 2: Block range queries
    std.debug.print("\n=== Example 2: Block Range Query ===\n", .{});

    const start_block: u64 = 1000;
    const end_block: u64 = 1005;

    var blocks = try block_client.getBlockRange(start_block, end_block);
    defer {
        for (blocks.items) |*b| {
            b.deinit(allocator);
        }
        blocks.deinit();
    }

    std.debug.print("Fetched {d} blocks from {d} to {d}\n", .{
        blocks.items.len,
        start_block,
        end_block,
    });

    for (blocks.items) |b| {
        std.debug.print("  Block #{d}: {d} items\n", .{ b.block_number, b.items.len });
    }

    // Example 3: Block number to timestamp conversion
    std.debug.print("\n=== Example 3: Block Number ↔ Timestamp Conversion ===\n", .{});

    // Hedera testnet started approximately at this time
    const testnet_start = zelix.Timestamp{
        .seconds = 1580428800, // Example: Feb 1, 2020
        .nanos = 0,
    };

    const test_block_num: u64 = 50000;
    const estimated_timestamp = zelix.BlockStreamClient.blockNumberToTimestamp(
        test_block_num,
        testnet_start,
    );

    std.debug.print("Block #{d} → Estimated timestamp: {d}.{d}\n", .{
        test_block_num,
        estimated_timestamp.seconds,
        estimated_timestamp.nanos,
    });

    const reverse_block_num = zelix.BlockStreamClient.timestampToBlockNumber(
        estimated_timestamp,
        testnet_start,
    );

    std.debug.print("Timestamp {d}.{d} → Block #{d}\n", .{
        estimated_timestamp.seconds,
        estimated_timestamp.nanos,
        reverse_block_num,
    });

    // Example 4: Subscribe to block stream (with callback)
    std.debug.print("\n=== Example 4: Block Stream Subscription ===\n", .{});
    std.debug.print("(Skipped in example - requires live network connection)\n", .{});

    // Uncomment to actually subscribe (requires Block Node connection):
    // const Handler = struct {
    //     pub fn handle(self: *@This(), items: []zelix.BlockItem) !void {
    //         _ = self;
    //         for (items) |item| {
    //             if (item.item_type == .event_transaction) {
    //                 std.debug.print("Received transaction in block stream\n", .{});
    //             }
    //         }
    //     }
    // };
    //
    // var handler = Handler{};
    // try block_client.subscribeBlocks(0, 0, &handler);

    std.debug.print("\n✅ All Block Stream parsing examples completed!\n", .{});
}
