const std = @import("std");
const zelix = @import("zelix");

fn getEnvOwned(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.EnvironmentVariableNotFound,
        else => return err,
    };
}

test "mirror transaction history" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const run_flag = std.process.getEnvVarOwned(allocator, "ZELIX_INTEGRATION") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(run_flag);

    if (run_flag.len == 0 or std.ascii.eqlIgnoreCase(run_flag, "0")) return error.SkipZigTest;

    const account_id_str = getEnvOwned(allocator, "ZELIX_TEST_ACCOUNT_ID") catch return error.SkipZigTest;
    defer allocator.free(account_id_str);

    const account_id = try zelix.AccountId.fromString(account_id_str);

    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    var records = try client.getAccountRecords(account_id);
    defer records.deinit(allocator);

    // Should have some records for any active account
    if (records.records.items.len > 0) {
        const first_record = &records.records.items[0];
        try std.testing.expect(first_record.consensus_timestamp.seconds > 0);
    }
}
