const std = @import("std");
const zelix = @import("zelix");

fn getEnvOwned(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.EnvironmentVariableNotFound,
        else => return err,
    };
}

test "mirror token info lookup" {
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

    const token_id = try zelix.TokenId.fromString(token_id_str);

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    var token_info = try client.getTokenInfo(token_id);
    defer token_info.deinit(allocator);

    try std.testing.expectEqual(token_id.shard, token_info.token_id.shard);
    try std.testing.expectEqual(token_id.realm, token_info.token_id.realm);
    try std.testing.expectEqual(token_id.num, token_info.token_id.num);

    // Token should have basic properties
    try std.testing.expect(token_info.name.len > 0 or token_info.symbol.len > 0);
}
