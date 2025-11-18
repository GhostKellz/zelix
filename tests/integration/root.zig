const std = @import("std");

pub fn main() void {}

test "integration suite" {
    _ = @import("nft_lookup.zig");
    _ = @import("account_info.zig");
    _ = @import("transaction_history.zig");
    _ = @import("token_info.zig");
    _ = @import("transaction_submit.zig");
}
