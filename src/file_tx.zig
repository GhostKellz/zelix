//! File Service transaction builders for Hedera File Service (HFS)

const std = @import("std");
const model = @import("model.zig");
const crypto = @import("crypto.zig");
const proto = @import("ser/proto.zig");
const tx = @import("tx.zig");

const ArrayListUnmanaged = std.ArrayListUnmanaged;

/// Create a new file
pub const FileCreateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    contents: []const u8 = "",
    keys: ArrayListUnmanaged(crypto.PublicKey) = .{},
    expiration_time: ?i64 = null,
    memo_field: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator) FileCreateTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *FileCreateTransaction) void {
        self.keys.deinit(self.allocator);
        self.builder.deinit();
    }

    pub fn setContents(self: *FileCreateTransaction, contents: []const u8) *FileCreateTransaction {
        self.contents = contents;
        return self;
    }

    pub fn addKey(self: *FileCreateTransaction, key: crypto.PublicKey) !*FileCreateTransaction {
        try self.keys.append(self.allocator, key);
        return self;
    }

    pub fn setExpirationTime(self: *FileCreateTransaction, seconds: i64) *FileCreateTransaction {
        self.expiration_time = seconds;
        return self;
    }

    pub fn setFileMemo(self: *FileCreateTransaction, memo: []const u8) *FileCreateTransaction {
        self.memo_field = memo;
        return self;
    }

    pub fn freeze(self: *FileCreateTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.expiration_time) |exp_time| {
            var timestamp_writer = proto.Writer.init(self.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeFieldVarint(1, @as(u64, @intCast(exp_time)));
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.allocator.free(timestamp_bytes);
            try body_writer.writeFieldBytes(2, timestamp_bytes);
        }

        if (self.keys.items.len > 0) {
            var keylist_writer = proto.Writer.init(self.allocator);
            defer keylist_writer.deinit();
            for (self.keys.items) |key| {
                const key_bytes = try encodePublicKey(self.allocator, key);
                defer self.allocator.free(key_bytes);
                try keylist_writer.writeFieldBytes(1, key_bytes);
            }
            const keylist_bytes = try keylist_writer.toOwnedSlice();
            defer self.allocator.free(keylist_bytes);
            try body_writer.writeFieldBytes(3, keylist_bytes);
        }

        if (self.contents.len > 0) {
            try body_writer.writeFieldBytes(4, self.contents);
        }

        if (self.memo_field.len > 0) {
            try body_writer.writeFieldString(6, self.memo_field);
        }

        const file_create_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(file_create_bytes);

        try writer.writeFieldBytes(16, file_create_bytes); // FileCreateTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *FileCreateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *FileCreateTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        return try client.executeTransaction(tx_bytes);
    }
};

/// Append to an existing file
pub const FileAppendTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    file_id: ?model.FileId = null,
    contents: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator) FileAppendTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *FileAppendTransaction) void {
        self.builder.deinit();
    }

    pub fn setFileId(self: *FileAppendTransaction, file_id: model.FileId) *FileAppendTransaction {
        self.file_id = file_id;
        return self;
    }

    pub fn setContents(self: *FileAppendTransaction, contents: []const u8) *FileAppendTransaction {
        self.contents = contents;
        return self;
    }

    pub fn freeze(self: *FileAppendTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.file_id) |file_id| {
            const file_bytes = try encodeFileId(self.allocator, file_id);
            defer self.allocator.free(file_bytes);
            try body_writer.writeFieldBytes(2, file_bytes);
        }

        if (self.contents.len > 0) {
            try body_writer.writeFieldBytes(4, self.contents);
        }

        const append_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(append_bytes);

        try writer.writeFieldBytes(17, append_bytes); // FileAppendTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *FileAppendTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *FileAppendTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        return try client.executeTransaction(tx_bytes);
    }
};

/// Update file properties
pub const FileUpdateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    file_id: ?model.FileId = null,
    contents: ?[]const u8 = null,
    keys: ArrayListUnmanaged(crypto.PublicKey) = .{},
    expiration_time: ?i64 = null,
    memo_field: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) FileUpdateTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *FileUpdateTransaction) void {
        self.keys.deinit(self.allocator);
        self.builder.deinit();
    }

    pub fn setFileId(self: *FileUpdateTransaction, file_id: model.FileId) *FileUpdateTransaction {
        self.file_id = file_id;
        return self;
    }

    pub fn setContents(self: *FileUpdateTransaction, contents: []const u8) *FileUpdateTransaction {
        self.contents = contents;
        return self;
    }

    pub fn addKey(self: *FileUpdateTransaction, key: crypto.PublicKey) !*FileUpdateTransaction {
        try self.keys.append(self.allocator, key);
        return self;
    }

    pub fn setExpirationTime(self: *FileUpdateTransaction, seconds: i64) *FileUpdateTransaction {
        self.expiration_time = seconds;
        return self;
    }

    pub fn setFileMemo(self: *FileUpdateTransaction, memo: []const u8) *FileUpdateTransaction {
        self.memo_field = memo;
        return self;
    }

    pub fn freeze(self: *FileUpdateTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.file_id) |file_id| {
            const file_bytes = try encodeFileId(self.allocator, file_id);
            defer self.allocator.free(file_bytes);
            try body_writer.writeFieldBytes(1, file_bytes);
        }

        if (self.expiration_time) |exp_time| {
            var timestamp_writer = proto.Writer.init(self.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeFieldVarint(1, @as(u64, @intCast(exp_time)));
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.allocator.free(timestamp_bytes);
            try body_writer.writeFieldBytes(2, timestamp_bytes);
        }

        if (self.keys.items.len > 0) {
            var keylist_writer = proto.Writer.init(self.allocator);
            defer keylist_writer.deinit();
            for (self.keys.items) |key| {
                const key_bytes = try encodePublicKey(self.allocator, key);
                defer self.allocator.free(key_bytes);
                try keylist_writer.writeFieldBytes(1, key_bytes);
            }
            const keylist_bytes = try keylist_writer.toOwnedSlice();
            defer self.allocator.free(keylist_bytes);
            try body_writer.writeFieldBytes(3, keylist_bytes);
        }

        if (self.contents) |contents| {
            try body_writer.writeFieldBytes(4, contents);
        }

        if (self.memo_field) |memo| {
            var memo_wrapper = proto.Writer.init(self.allocator);
            defer memo_wrapper.deinit();
            try memo_wrapper.writeFieldString(1, memo);
            const memo_bytes = try memo_wrapper.toOwnedSlice();
            defer self.allocator.free(memo_bytes);
            try body_writer.writeFieldBytes(5, memo_bytes);
        }

        const update_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(update_bytes);

        try writer.writeFieldBytes(18, update_bytes); // FileUpdateTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *FileUpdateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *FileUpdateTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        return try client.executeTransaction(tx_bytes);
    }
};

/// Delete a file
pub const FileDeleteTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    file_id: ?model.FileId = null,

    pub fn init(allocator: std.mem.Allocator) FileDeleteTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *FileDeleteTransaction) void {
        self.builder.deinit();
    }

    pub fn setFileId(self: *FileDeleteTransaction, file_id: model.FileId) *FileDeleteTransaction {
        self.file_id = file_id;
        return self;
    }

    pub fn freeze(self: *FileDeleteTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.file_id) |file_id| {
            const file_bytes = try encodeFileId(self.allocator, file_id);
            defer self.allocator.free(file_bytes);
            try body_writer.writeFieldBytes(2, file_bytes);
        }

        const delete_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(delete_bytes);

        try writer.writeFieldBytes(19, delete_bytes); // FileDeleteTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *FileDeleteTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *FileDeleteTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        return try client.executeTransaction(tx_bytes);
    }
};

// Helper functions

fn encodeFileId(allocator: std.mem.Allocator, file_id: model.FileId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldVarint(1, file_id.shard);
    try writer.writeFieldVarint(2, file_id.realm);
    try writer.writeFieldVarint(3, file_id.num);
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
