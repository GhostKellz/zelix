const std = @import("std");
const zelix = @import("zelix");

const Command = enum {
    account,
    token,
    nft,
    transaction,
    help,

    fn fromString(s: []const u8) ?Command {
        if (std.mem.eql(u8, s, "account")) return .account;
        if (std.mem.eql(u8, s, "token")) return .token;
        if (std.mem.eql(u8, s, "nft")) return .nft;
        if (std.mem.eql(u8, s, "tx") or std.mem.eql(u8, s, "transaction")) return .transaction;
        if (std.mem.eql(u8, s, "help") or std.mem.eql(u8, s, "--help") or std.mem.eql(u8, s, "-h")) return .help;
        return null;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printHelp();
        std.process.exit(1);
    }

    const command = Command.fromString(args[1]) orelse {
        std.debug.print("Unknown command: {s}\n\n", .{args[1]});
        printHelp();
        std.process.exit(1);
    };

    switch (command) {
        .help => {
            printHelp();
            return;
        },
        .account => try cmdAccount(allocator, args[2..]),
        .token => try cmdToken(allocator, args[2..]),
        .nft => try cmdNft(allocator, args[2..]),
        .transaction => try cmdTransaction(allocator, args[2..]),
    }
}

fn printHelp() void {
    std.debug.print(
        \\zelix - Hedera SDK CLI
        \\
        \\Usage: zelix <command> [options]
        \\
        \\Commands:
        \\  account <account-id>              Get account info and balance
        \\  token <token-id>                  Get token info
        \\  nft <token-id> <serial>           Get NFT info and metadata
        \\  transaction <tx-id>               Get transaction receipt/record
        \\  help                              Show this help message
        \\
        \\Environment Variables:
        \\  HEDERA_NETWORK                    Network to use (mainnet, testnet, previewnet)
        \\  HEDERA_MIRROR_URL                 Custom mirror node URL
        \\
        \\Examples:
        \\  zelix account 0.0.123456
        \\  zelix token 0.0.789012
        \\  zelix nft 0.0.789012 1
        \\  zelix transaction 0.0.123@1234567890.123456789
        \\
    , .{});
}

fn cmdAccount(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len < 1) {
        std.debug.print("Error: account command requires account ID\n", .{});
        std.debug.print("Usage: zelix account <account-id>\n", .{});
        std.process.exit(1);
    }

    const account_id = zelix.AccountId.fromString(args[0]) catch |err| {
        std.debug.print("Error: Invalid account ID '{s}': {s}\n", .{ args[0], @errorName(err) });
        std.process.exit(1);
    };

    var client = zelix.Client.initFromEnv(allocator) catch |err| {
        std.debug.print("Error: Failed to initialize client: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer client.deinit();

    std.debug.print("Fetching account info for {d}.{d}.{d}...\n", .{
        account_id.shard,
        account_id.realm,
        account_id.num,
    });

    const info = client.getAccountInfo(account_id) catch |err| {
        std.debug.print("Error: Failed to get account info: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer info.deinit(allocator);

    std.debug.print("\nAccount: {d}.{d}.{d}\n", .{ info.account_id.shard, info.account_id.realm, info.account_id.num });
    std.debug.print("Balance: {} tinybar\n", .{info.balance});

    if (info.alias.len > 0) {
        std.debug.print("Alias: ", .{});
        for (info.alias) |byte| {
            std.debug.print("{x:0>2}", .{byte});
        }
        std.debug.print("\n", .{});
    }

    if (info.key) |key| {
        std.debug.print("Key: {s}\n", .{key});
    }

    std.debug.print("Deleted: {}\n", .{info.deleted});
    std.debug.print("Auto Renew Period: {} seconds\n", .{info.auto_renew_period_seconds});
}

fn cmdToken(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len < 1) {
        std.debug.print("Error: token command requires token ID\n", .{});
        std.debug.print("Usage: zelix token <token-id>\n", .{});
        std.process.exit(1);
    }

    const token_id = zelix.TokenId.fromString(args[0]) catch |err| {
        std.debug.print("Error: Invalid token ID '{s}': {s}\n", .{ args[0], @errorName(err) });
        std.process.exit(1);
    };

    var client = zelix.Client.initFromEnv(allocator) catch |err| {
        std.debug.print("Error: Failed to initialize client: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer client.deinit();

    std.debug.print("Fetching token info for {d}.{d}.{d}...\n", .{
        token_id.shard,
        token_id.realm,
        token_id.num,
    });

    var info = client.getTokenInfo(token_id) catch |err| {
        std.debug.print("Error: Failed to get token info: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer info.deinit(allocator);

    std.debug.print("\nToken: {d}.{d}.{d}\n", .{ info.token_id.shard, info.token_id.realm, info.token_id.num });
    std.debug.print("Name: {s}\n", .{info.name});
    std.debug.print("Symbol: {s}\n", .{info.symbol});
    std.debug.print("Decimals: {}\n", .{info.decimals});
    std.debug.print("Total Supply: {}\n", .{info.total_supply});
    std.debug.print("Type: {s}\n", .{@tagName(info.token_type)});

    if (info.treasury_account_id) |treasury| {
        std.debug.print("Treasury: {d}.{d}.{d}\n", .{ treasury.shard, treasury.realm, treasury.num });
    }
}

fn cmdNft(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len < 2) {
        std.debug.print("Error: nft command requires token ID and serial number\n", .{});
        std.debug.print("Usage: zelix nft <token-id> <serial>\n", .{});
        std.process.exit(1);
    }

    const token_id = zelix.TokenId.fromString(args[0]) catch |err| {
        std.debug.print("Error: Invalid token ID '{s}': {s}\n", .{ args[0], @errorName(err) });
        std.process.exit(1);
    };

    const serial = std.fmt.parseInt(u64, args[1], 10) catch |err| {
        std.debug.print("Error: Invalid serial number '{s}': {s}\n", .{ args[1], @errorName(err) });
        std.process.exit(1);
    };

    var client = zelix.Client.initFromEnv(allocator) catch |err| {
        std.debug.print("Error: Failed to initialize client: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer client.deinit();

    std.debug.print("Fetching NFT info for {d}.{d}.{d} serial {}...\n", .{
        token_id.shard,
        token_id.realm,
        token_id.num,
        serial,
    });

    var info = client.getNftInfo(token_id, serial) catch |err| {
        std.debug.print("Error: Failed to get NFT info: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer info.deinit(allocator);

    std.debug.print("\nNFT: {d}.{d}.{d} serial {}\n", .{
        info.id.token_id.shard,
        info.id.token_id.realm,
        info.id.token_id.num,
        info.id.serial,
    });

    if (info.account_id) |owner| {
        std.debug.print("Owner: {d}.{d}.{d}\n", .{ owner.shard, owner.realm, owner.num });
    }

    std.debug.print("Created: {}\n", .{info.created_timestamp.seconds});

    if (info.metadata.len > 0) {
        std.debug.print("Metadata ({} bytes): ", .{info.metadata.len});
        if (std.mem.startsWith(u8, info.metadata, "file:")) {
            std.debug.print("{s}\n", .{info.metadata});
        } else if (std.mem.allEqual(u8, info.metadata, 0x20) or
                   std.mem.allEqual(u8, info.metadata, 0x00)) {
            std.debug.print("<binary data>\n", .{});
        } else {
            // Try to print as string if it looks like text
            var is_text = true;
            for (info.metadata) |byte| {
                if (byte < 0x20 and byte != '\n' and byte != '\r' and byte != '\t') {
                    is_text = false;
                    break;
                }
            }
            if (is_text) {
                std.debug.print("{s}\n", .{info.metadata});
            } else {
                for (info.metadata[0..@min(info.metadata.len, 64)]) |byte| {
                    std.debug.print("{x:0>2}", .{byte});
                }
                if (info.metadata.len > 64) {
                    std.debug.print("... ({} more bytes)", .{info.metadata.len - 64});
                }
                std.debug.print("\n", .{});
            }
        }
    }
}

fn cmdTransaction(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len < 1) {
        std.debug.print("Error: transaction command requires transaction ID\n", .{});
        std.debug.print("Usage: zelix transaction <tx-id>\n", .{});
        std.process.exit(1);
    }

    const tx_id = zelix.TransactionId.fromString(args[0]) catch |err| {
        std.debug.print("Error: Invalid transaction ID '{s}': {s}\n", .{ args[0], @errorName(err) });
        std.process.exit(1);
    };

    var client = zelix.Client.initFromEnv(allocator) catch |err| {
        std.debug.print("Error: Failed to initialize client: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer client.deinit();

    std.debug.print("Fetching transaction receipt...\n", .{});

    const receipt = client.getTransactionReceipt(tx_id) catch |err| {
        std.debug.print("Error: Failed to get transaction receipt: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer receipt.deinit(allocator);

    std.debug.print("\nTransaction: {d}.{d}.{d}@{}.{}\n", .{
        receipt.transaction_id.account_id.shard,
        receipt.transaction_id.account_id.realm,
        receipt.transaction_id.account_id.num,
        receipt.transaction_id.valid_start.seconds,
        receipt.transaction_id.valid_start.nanos,
    });

    std.debug.print("Status: {s}\n", .{@tagName(receipt.status)});

    if (receipt.account_id) |account| {
        std.debug.print("Account: {d}.{d}.{d}\n", .{ account.shard, account.realm, account.num });
    }

    if (receipt.token_id) |token| {
        std.debug.print("Token: {d}.{d}.{d}\n", .{ token.shard, token.realm, token.num });
    }

    if (receipt.serial_numbers.items.len > 0) {
        std.debug.print("Serial Numbers: ", .{});
        for (receipt.serial_numbers.items, 0..) |serial, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{}", .{serial});
        }
        std.debug.print("\n", .{});
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
