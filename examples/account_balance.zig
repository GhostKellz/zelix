const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try zelix.Client.init(allocator, .testnet);

    const account_id = try zelix.AccountId.fromString("0.0.3");
    var query = zelix.AccountBalanceQuery{};
    _ = query.setAccountId(account_id);
    const balance = try query.execute(&client);

    std.debug.print("Account {d}.{d}.{d} balance: {}\n", .{
        account_id.shard,
        account_id.realm,
        account_id.num,
        balance.hbars,
    });
}
