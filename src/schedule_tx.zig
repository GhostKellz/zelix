//! Schedule Service transaction builders for Hedera Schedule Service

const std = @import("std");
const model = @import("model.zig");
const crypto = @import("crypto.zig");
const proto = @import("ser/proto.zig");
const tx = @import("tx.zig");

const ArrayListUnmanaged = std.ArrayListUnmanaged;

/// Create a scheduled transaction
pub const ScheduleCreateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    scheduled_transaction_body: ?[]const u8 = null,
    memo_field: []const u8 = "",
    admin_key: ?crypto.PublicKey = null,
    payer_account_id: ?model.AccountId = null,
    expiration_time: ?i64 = null,
    wait_for_expiry: bool = false,

    pub fn init(allocator: std.mem.Allocator) ScheduleCreateTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *ScheduleCreateTransaction) void {
        if (self.scheduled_transaction_body) |body| {
            self.allocator.free(body);
        }
        self.builder.deinit();
    }

    pub fn setScheduledTransactionBody(self: *ScheduleCreateTransaction, body: []const u8) !*ScheduleCreateTransaction {
        if (self.scheduled_transaction_body) |old_body| {
            self.allocator.free(old_body);
        }
        self.scheduled_transaction_body = try self.allocator.dupe(u8, body);
        return self;
    }

    pub fn setScheduleMemo(self: *ScheduleCreateTransaction, memo: []const u8) *ScheduleCreateTransaction {
        self.memo_field = memo;
        return self;
    }

    pub fn setAdminKey(self: *ScheduleCreateTransaction, key: crypto.PublicKey) *ScheduleCreateTransaction {
        self.admin_key = key;
        return self;
    }

    pub fn setPayerAccountId(self: *ScheduleCreateTransaction, account_id: model.AccountId) *ScheduleCreateTransaction {
        self.payer_account_id = account_id;
        return self;
    }

    pub fn setExpirationTime(self: *ScheduleCreateTransaction, seconds: i64) *ScheduleCreateTransaction {
        self.expiration_time = seconds;
        return self;
    }

    pub fn setWaitForExpiry(self: *ScheduleCreateTransaction, wait: bool) *ScheduleCreateTransaction {
        self.wait_for_expiry = wait;
        return self;
    }

    pub fn freeze(self: *ScheduleCreateTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.scheduled_transaction_body) |scheduled_body| {
            try body_writer.writeFieldBytes(1, scheduled_body);
        }

        if (self.memo_field.len > 0) {
            try body_writer.writeFieldString(2, self.memo_field);
        }

        if (self.admin_key) |key| {
            const key_bytes = try encodePublicKey(self.allocator, key);
            defer self.allocator.free(key_bytes);
            try body_writer.writeFieldBytes(3, key_bytes);
        }

        if (self.payer_account_id) |payer| {
            const payer_bytes = try encodeAccountId(self.allocator, payer);
            defer self.allocator.free(payer_bytes);
            try body_writer.writeFieldBytes(4, payer_bytes);
        }

        if (self.expiration_time) |exp_time| {
            var timestamp_writer = proto.Writer.init(self.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeFieldVarint(1, @as(u64, @intCast(exp_time)));
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.allocator.free(timestamp_bytes);
            try body_writer.writeFieldBytes(5, timestamp_bytes);
        }

        try body_writer.writeFieldBool(6, self.wait_for_expiry);

        const schedule_create_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(schedule_create_bytes);

        try writer.writeFieldBytes(42, schedule_create_bytes); // ScheduleCreateTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *ScheduleCreateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *ScheduleCreateTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Sign a scheduled transaction
pub const ScheduleSignTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    schedule_id: ?model.ScheduleId = null,

    pub fn init(allocator: std.mem.Allocator) ScheduleSignTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *ScheduleSignTransaction) void {
        self.builder.deinit();
    }

    pub fn setScheduleId(self: *ScheduleSignTransaction, schedule_id: model.ScheduleId) *ScheduleSignTransaction {
        self.schedule_id = schedule_id;
        return self;
    }

    pub fn freeze(self: *ScheduleSignTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.schedule_id) |schedule_id| {
            const schedule_bytes = try encodeScheduleId(self.allocator, schedule_id);
            defer self.allocator.free(schedule_bytes);
            try body_writer.writeFieldBytes(1, schedule_bytes);
        }

        const schedule_sign_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(schedule_sign_bytes);

        try writer.writeFieldBytes(43, schedule_sign_bytes); // ScheduleSignTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *ScheduleSignTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *ScheduleSignTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Delete a scheduled transaction
pub const ScheduleDeleteTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    schedule_id: ?model.ScheduleId = null,

    pub fn init(allocator: std.mem.Allocator) ScheduleDeleteTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *ScheduleDeleteTransaction) void {
        self.builder.deinit();
    }

    pub fn setScheduleId(self: *ScheduleDeleteTransaction, schedule_id: model.ScheduleId) *ScheduleDeleteTransaction {
        self.schedule_id = schedule_id;
        return self;
    }

    pub fn freeze(self: *ScheduleDeleteTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.schedule_id) |schedule_id| {
            const schedule_bytes = try encodeScheduleId(self.allocator, schedule_id);
            defer self.allocator.free(schedule_bytes);
            try body_writer.writeFieldBytes(1, schedule_bytes);
        }

        const schedule_delete_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(schedule_delete_bytes);

        try writer.writeFieldBytes(44, schedule_delete_bytes); // ScheduleDeleteTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *ScheduleDeleteTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *ScheduleDeleteTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

// Helper functions

fn encodeAccountId(allocator: std.mem.Allocator, account_id: model.AccountId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldVarint(1, account_id.shard);
    try writer.writeFieldVarint(2, account_id.realm);
    try writer.writeFieldVarint(3, account_id.num);
    return try writer.toOwnedSlice();
}

fn encodeScheduleId(allocator: std.mem.Allocator, schedule_id: model.ScheduleId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldVarint(1, schedule_id.shard);
    try writer.writeFieldVarint(2, schedule_id.realm);
    try writer.writeFieldVarint(3, schedule_id.num);
    return try writer.toOwnedSlice();
}

fn encodePublicKey(allocator: std.mem.Allocator, key: crypto.PublicKey) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    switch (key) {
        .ed25519 => |ed_key| {
            const key_bytes = ed_key.toBytes();
            try writer.writeFieldBytes(2, &key_bytes); // ED25519 = field 2
        },
    }

    return try writer.toOwnedSlice();
}
