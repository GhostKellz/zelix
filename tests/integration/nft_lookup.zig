const std = @import("std");
const zelix = @import("zelix");

fn getEnvOwned(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.EnvironmentVariableNotFound,
        else => return err,
    };
}

test "mirror nft lookup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const run_flag = std.process.getEnvVarOwned(allocator, "ZELIX_INTEGRATION") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(run_flag);

    if (run_flag.len == 0 or std.ascii.eqlIgnoreCase(run_flag, "0")) return error.SkipZigTest;

    const token_id_str = getEnvOwned(allocator, "ZELIX_TEST_TOKEN_ID") catch return error.SkipZigTest;
    defer allocator.free(token_id_str);

    const serial_str = getEnvOwned(allocator, "ZELIX_TEST_TOKEN_SERIAL") catch return error.SkipZigTest;
    defer allocator.free(serial_str);

    const token_id = try zelix.TokenId.fromString(token_id_str);
    const serial = std.fmt.parseInt(u64, serial_str, 10) catch return error.SkipZigTest;

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    var nft_info = try client.getNftInfo(token_id, serial);
    defer nft_info.deinit(allocator);

    try std.testing.expectEqual(token_id.shard, nft_info.id.token_id.shard);
    try std.testing.expect(nft_info.metadata.len >= 0);

    if (std.mem.startsWith(u8, nft_info.metadata, "file:")) {
        const file_slice = nft_info.metadata[5..];
        if (file_slice.len > 0) {
            const file_id = zelix.FileId.fromString(file_slice) catch null;
            if (file_id) |fid| {
                const contents = client.getFileContents(fid) catch null;
                if (contents) |bytes| {
                    defer allocator.free(bytes);
                    try std.testing.expect(bytes.len > 0);
                }
            }
        }
    }
}
