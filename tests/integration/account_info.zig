const std = @import("std");
const zelix = @import("zelix");

fn getEnvOwned(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.EnvironmentVariableNotFound,
        else => return err,
    };
}

test "mirror account info lookup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const run_flag = std.process.getEnvVarOwned(allocator, "ZELIX_INTEGRATION") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(run_flag);

    if (run_flag.len == 0 or std.ascii.eqlIgnoreCase(run_flag, "0")) return error.SkipZigTest;

    const account_id_str = getEnvOwned(allocator, "ZELIX_TEST_ACCOUNT_ID") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            // Default to Hedera treasury account if not set
            return error.SkipZigTest;
        },
        else => return err,
    };
    defer allocator.free(account_id_str);

    const account_id = try zelix.AccountId.fromString(account_id_str);

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    const account_info = try client.getAccountInfo(account_id);
    defer account_info.deinit(allocator);

    try std.testing.expectEqual(account_id.shard, account_info.account_id.shard);
    try std.testing.expectEqual(account_id.realm, account_info.account_id.realm);
    try std.testing.expectEqual(account_id.num, account_info.account_id.num);
    try std.testing.expect(account_info.balance >= 0);
}
