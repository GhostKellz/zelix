const std = @import("std");
const zelix = @import("zelix");

fn parseSerial(arg: []const u8) !u64 {
    return std.fmt.parseInt(u64, std.mem.trim(u8, arg, " \t\r\n"), 10);
}

fn metadataPreview(allocator: std.mem.Allocator, metadata: []const u8) ![]const u8 {
    if (metadata.len == 0) return allocator.dupe(u8, "<empty>");

    var printable = true;
    for (metadata) |c| {
        if (!std.ascii.isPrint(c)) {
            printable = false;
            break;
        }
    }

    if (printable) {
        return allocator.dupe(u8, metadata);
    }

    return std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexUpper(metadata)});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    _ = args_iter.next();
    const token_arg = args_iter.next() orelse "0.0.6001";
    const serial_arg = args_iter.next() orelse "1";

    const token_id = try zelix.TokenId.fromString(token_arg);
    const serial = try parseSerial(serial_arg);

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    var nft_info = try client.getNftInfo(token_id, serial);
    defer nft_info.deinit(allocator);

    std.debug.print("NFT {} serial {}\n", .{ token_id, serial });
    std.debug.print("  Owner: {}\n", .{nft_info.owner_account_id});
    if (nft_info.spender_account_id) |spender| {
        std.debug.print("  Approved spender: {}\n", .{spender});
    }
    if (nft_info.delegating_spender_account_id) |delegate| {
        std.debug.print("  Delegating spender: {}\n", .{delegate});
    }
    std.debug.print("  Created: {}\n", .{nft_info.created_timestamp});
    if (nft_info.modified_timestamp) |ts| {
        std.debug.print("  Updated: {}\n", .{ts});
    }

    const preview = try metadataPreview(allocator, nft_info.metadata);
    defer allocator.free(preview);
    std.debug.print("  Metadata: {s}\n", .{preview});

    var allowances = try client.getTokenNftAllowances(nft_info.owner_account_id, .{
        .token_id = token_id,
        .limit = 5,
    });
    defer allowances.deinit(allocator);

    if (allowances.allowances.len == 0) {
        std.debug.print("  No NFT allowances found for owner.\n", .{});
    } else {
        std.debug.print("  NFT allowances (first {}):\n", .{allowances.allowances.len});
        for (allowances.allowances) |allowance| {
            std.debug.print(
                "    spender={} approvedForAll={} serials=[",
                .{ allowance.spender_account_id, allowance.approved_for_all },
            );
            for (allowance.serial_numbers, 0..) |serial_number, idx| {
                if (idx != 0) std.debug.print(", ", .{});
                std.debug.print("{}", .{serial_number});
            }
            std.debug.print("]\n", .{});
        }
    }

    // Optional: resolve file contents if metadata encodes a file identifier like "file:0.0.1234".
    if (std.mem.startsWith(u8, nft_info.metadata, "file:")) {
        const file_slice = nft_info.metadata[5..];
        if (file_slice.len > 0 and std.mem.indexOfScalar(u8, file_slice, '/') == null) {
            const maybe_file_id = zelix.FileId.fromString(file_slice) catch null;
            if (maybe_file_id) |file_id| {
                const contents = client.getFileContents(file_id) catch null;
                if (contents) |bytes| {
                    defer allocator.free(bytes);
                    std.debug.print("  Fetched HFS file {} ({} bytes)\n", .{ file_id, bytes.len });
                }
            }
        }
    }
}
