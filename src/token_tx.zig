//! Token and NFT transaction builders for Hedera Token Service (HTS)

const std = @import("std");
const model = @import("model.zig");
const crypto = @import("crypto.zig");
const proto = @import("ser/proto.zig");
const tx = @import("tx.zig");

const ArrayListUnmanaged = std.ArrayListUnmanaged;

/// Token types supported by Hedera
pub const TokenType = enum(i32) {
    fungible_common = 0,
    non_fungible_unique = 1,

    pub fn toProtoValue(self: TokenType) i32 {
        return @intFromEnum(self);
    }
};

/// Token supply types
pub const TokenSupplyType = enum(i32) {
    infinite = 0,
    finite = 1,

    pub fn toProtoValue(self: TokenSupplyType) i32 {
        return @intFromEnum(self);
    }
};

/// Create a new fungible or non-fungible token
pub const TokenCreateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,

    // Token properties
    name: []const u8 = "",
    symbol: []const u8 = "",
    decimals: u32 = 0,
    initial_supply: u64 = 0,
    treasury_account_id: ?model.AccountId = null,
    admin_key: ?crypto.PublicKey = null,
    kyc_key: ?crypto.PublicKey = null,
    freeze_key: ?crypto.PublicKey = null,
    wipe_key: ?crypto.PublicKey = null,
    supply_key: ?crypto.PublicKey = null,
    freeze_default: bool = false,
    expiration_time: ?i64 = null,
    auto_renew_account: ?model.AccountId = null,
    auto_renew_period: i64 = 7776000, // 90 days default
    memo_field: []const u8 = "",
    token_type: TokenType = .fungible_common,
    supply_type: TokenSupplyType = .infinite,
    max_supply: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) TokenCreateTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenCreateTransaction) void {
        self.builder.deinit();
    }

    pub fn setTokenName(self: *TokenCreateTransaction, name: []const u8) *TokenCreateTransaction {
        self.name = name;
        return self;
    }

    pub fn setTokenSymbol(self: *TokenCreateTransaction, symbol: []const u8) *TokenCreateTransaction {
        self.symbol = symbol;
        return self;
    }

    pub fn setDecimals(self: *TokenCreateTransaction, decimals: u32) *TokenCreateTransaction {
        self.decimals = decimals;
        return self;
    }

    pub fn setInitialSupply(self: *TokenCreateTransaction, supply: u64) *TokenCreateTransaction {
        self.initial_supply = supply;
        return self;
    }

    pub fn setTreasuryAccountId(self: *TokenCreateTransaction, account_id: model.AccountId) *TokenCreateTransaction {
        self.treasury_account_id = account_id;
        return self;
    }

    pub fn setAdminKey(self: *TokenCreateTransaction, key: crypto.PublicKey) *TokenCreateTransaction {
        self.admin_key = key;
        return self;
    }

    pub fn setKycKey(self: *TokenCreateTransaction, key: crypto.PublicKey) *TokenCreateTransaction {
        self.kyc_key = key;
        return self;
    }

    pub fn setFreezeKey(self: *TokenCreateTransaction, key: crypto.PublicKey) *TokenCreateTransaction {
        self.freeze_key = key;
        return self;
    }

    pub fn setWipeKey(self: *TokenCreateTransaction, key: crypto.PublicKey) *TokenCreateTransaction {
        self.wipe_key = key;
        return self;
    }

    pub fn setSupplyKey(self: *TokenCreateTransaction, key: crypto.PublicKey) *TokenCreateTransaction {
        self.supply_key = key;
        return self;
    }

    pub fn setFreezeDefault(self: *TokenCreateTransaction, freeze_default: bool) *TokenCreateTransaction {
        self.freeze_default = freeze_default;
        return self;
    }

    pub fn setAutoRenewAccount(self: *TokenCreateTransaction, account_id: model.AccountId) *TokenCreateTransaction {
        self.auto_renew_account = account_id;
        return self;
    }

    pub fn setAutoRenewPeriod(self: *TokenCreateTransaction, seconds: i64) *TokenCreateTransaction {
        self.auto_renew_period = seconds;
        return self;
    }

    pub fn setTokenMemo(self: *TokenCreateTransaction, memo: []const u8) *TokenCreateTransaction {
        self.memo_field = memo;
        return self;
    }

    pub fn setTokenType(self: *TokenCreateTransaction, token_type: TokenType) *TokenCreateTransaction {
        self.token_type = token_type;
        return self;
    }

    pub fn setSupplyType(self: *TokenCreateTransaction, supply_type: TokenSupplyType) *TokenCreateTransaction {
        self.supply_type = supply_type;
        return self;
    }

    pub fn setMaxSupply(self: *TokenCreateTransaction, max: u64) *TokenCreateTransaction {
        self.max_supply = max;
        return self;
    }

    pub fn freeze(self: *TokenCreateTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        // TokenCreateTransactionBody - field 29 in TransactionBody
        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.name.len > 0) try body_writer.writeFieldString(1, self.name);
        if (self.symbol.len > 0) try body_writer.writeFieldString(2, self.symbol);
        try body_writer.writeFieldVarint(3, self.decimals);
        try body_writer.writeFieldVarint(4, self.initial_supply);

        if (self.treasury_account_id) |treasury| {
            const treasury_bytes = try encodeAccountId(self.allocator, treasury);
            defer self.allocator.free(treasury_bytes);
            try body_writer.writeFieldBytes(5, treasury_bytes);
        }

        if (self.admin_key) |key| {
            const key_bytes = try encodePublicKey(self.allocator, key);
            defer self.allocator.free(key_bytes);
            try body_writer.writeFieldBytes(6, key_bytes);
        }

        if (self.kyc_key) |key| {
            const key_bytes = try encodePublicKey(self.allocator, key);
            defer self.allocator.free(key_bytes);
            try body_writer.writeFieldBytes(7, key_bytes);
        }

        if (self.freeze_key) |key| {
            const key_bytes = try encodePublicKey(self.allocator, key);
            defer self.allocator.free(key_bytes);
            try body_writer.writeFieldBytes(8, key_bytes);
        }

        if (self.wipe_key) |key| {
            const key_bytes = try encodePublicKey(self.allocator, key);
            defer self.allocator.free(key_bytes);
            try body_writer.writeFieldBytes(9, key_bytes);
        }

        if (self.supply_key) |key| {
            const key_bytes = try encodePublicKey(self.allocator, key);
            defer self.allocator.free(key_bytes);
            try body_writer.writeFieldBytes(10, key_bytes);
        }

        try body_writer.writeFieldBool(11, self.freeze_default);

        if (self.auto_renew_account) |account| {
            const account_bytes = try encodeAccountId(self.allocator, account);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(13, account_bytes);
        }

        try body_writer.writeFieldVarint(14, @as(u64, @intCast(self.auto_renew_period)));

        if (self.memo_field.len > 0) try body_writer.writeFieldString(15, self.memo_field);
        try body_writer.writeFieldVarint(16, @as(u32, @intCast(self.token_type.toProtoValue())));
        try body_writer.writeFieldVarint(17, @as(u32, @intCast(self.supply_type.toProtoValue())));

        if (self.max_supply > 0) try body_writer.writeFieldVarint(18, self.max_supply);

        const token_create_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(token_create_bytes);

        // Build transaction body
        try writer.writeFieldBytes(29, token_create_bytes);
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenCreateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenCreateTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Mint new tokens (fungible) or NFTs (non-fungible)
pub const TokenMintTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    token_id: ?model.TokenId = null,
    amount: u64 = 0,
    metadata_list: ArrayListUnmanaged([]const u8) = .{},

    pub fn init(allocator: std.mem.Allocator) TokenMintTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenMintTransaction) void {
        self.metadata_list.deinit(self.allocator);
        self.builder.deinit();
    }

    pub fn setTokenId(self: *TokenMintTransaction, token_id: model.TokenId) *TokenMintTransaction {
        self.token_id = token_id;
        return self;
    }

    pub fn setAmount(self: *TokenMintTransaction, amount: u64) *TokenMintTransaction {
        self.amount = amount;
        return self;
    }

    pub fn addMetadata(self: *TokenMintTransaction, metadata: []const u8) !*TokenMintTransaction {
        try self.metadata_list.append(self.allocator, metadata);
        return self;
    }

    pub fn freeze(self: *TokenMintTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.token_id) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(1, token_bytes);
        }

        if (self.amount > 0) {
            try body_writer.writeFieldVarint(2, self.amount);
        }

        for (self.metadata_list.items) |metadata| {
            try body_writer.writeFieldBytes(3, metadata);
        }

        const mint_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(mint_bytes);

        try writer.writeFieldBytes(30, mint_bytes); // TokenMintTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenMintTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenMintTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Burn tokens or NFTs
pub const TokenBurnTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    token_id: ?model.TokenId = null,
    amount: u64 = 0,
    serial_numbers: ArrayListUnmanaged(u64) = .{},

    pub fn init(allocator: std.mem.Allocator) TokenBurnTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenBurnTransaction) void {
        self.serial_numbers.deinit(self.allocator);
        self.builder.deinit();
    }

    pub fn setTokenId(self: *TokenBurnTransaction, token_id: model.TokenId) *TokenBurnTransaction {
        self.token_id = token_id;
        return self;
    }

    pub fn setAmount(self: *TokenBurnTransaction, amount: u64) *TokenBurnTransaction {
        self.amount = amount;
        return self;
    }

    pub fn addSerialNumber(self: *TokenBurnTransaction, serial: u64) !*TokenBurnTransaction {
        try self.serial_numbers.append(self.allocator, serial);
        return self;
    }

    pub fn freeze(self: *TokenBurnTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.token_id) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(1, token_bytes);
        }

        if (self.amount > 0) {
            try body_writer.writeFieldVarint(2, self.amount);
        }

        for (self.serial_numbers.items) |serial| {
            try body_writer.writeFieldVarint(3, serial);
        }

        const burn_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(burn_bytes);

        try writer.writeFieldBytes(31, burn_bytes); // TokenBurnTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenBurnTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenBurnTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Associate tokens with an account
pub const TokenAssociateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    account_id: ?model.AccountId = null,
    token_ids: ArrayListUnmanaged(model.TokenId) = .{},

    pub fn init(allocator: std.mem.Allocator) TokenAssociateTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenAssociateTransaction) void {
        self.token_ids.deinit(self.allocator);
        self.builder.deinit();
    }

    pub fn setAccountId(self: *TokenAssociateTransaction, account_id: model.AccountId) *TokenAssociateTransaction {
        self.account_id = account_id;
        return self;
    }

    pub fn addTokenId(self: *TokenAssociateTransaction, token_id: model.TokenId) !*TokenAssociateTransaction {
        try self.token_ids.append(self.allocator, token_id);
        return self;
    }

    pub fn freeze(self: *TokenAssociateTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.account_id) |account_id| {
            const account_bytes = try encodeAccountId(self.allocator, account_id);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(1, account_bytes);
        }

        for (self.token_ids.items) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(2, token_bytes);
        }

        const associate_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(associate_bytes);

        try writer.writeFieldBytes(32, associate_bytes); // TokenAssociateTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenAssociateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenAssociateTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Dissociate tokens from an account
pub const TokenDissociateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    account_id: ?model.AccountId = null,
    token_ids: ArrayListUnmanaged(model.TokenId) = .{},

    pub fn init(allocator: std.mem.Allocator) TokenDissociateTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenDissociateTransaction) void {
        self.token_ids.deinit(self.allocator);
        self.builder.deinit();
    }

    pub fn setAccountId(self: *TokenDissociateTransaction, account_id: model.AccountId) *TokenDissociateTransaction {
        self.account_id = account_id;
        return self;
    }

    pub fn addTokenId(self: *TokenDissociateTransaction, token_id: model.TokenId) !*TokenDissociateTransaction {
        try self.token_ids.append(self.allocator, token_id);
        return self;
    }

    pub fn freeze(self: *TokenDissociateTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.account_id) |account_id| {
            const account_bytes = try encodeAccountId(self.allocator, account_id);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(1, account_bytes);
        }

        for (self.token_ids.items) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(2, token_bytes);
        }

        const dissociate_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(dissociate_bytes);

        try writer.writeFieldBytes(33, dissociate_bytes); // TokenDissociateTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenDissociateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenDissociateTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

// Helper functions for encoding IDs and keys

fn encodeAccountId(allocator: std.mem.Allocator, account_id: model.AccountId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldVarint(1, account_id.shard);
    try writer.writeFieldVarint(2, account_id.realm);
    try writer.writeFieldVarint(3, account_id.num);
    return try writer.toOwnedSlice();
}

fn encodeTokenId(allocator: std.mem.Allocator, token_id: model.TokenId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldVarint(1, token_id.shard);
    try writer.writeFieldVarint(2, token_id.realm);
    try writer.writeFieldVarint(3, token_id.num);
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

/// Update token properties
pub const TokenUpdateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    token_id: ?model.TokenId = null,
    name: ?[]const u8 = null,
    symbol: ?[]const u8 = null,
    treasury_account_id: ?model.AccountId = null,
    admin_key: ?crypto.PublicKey = null,
    kyc_key: ?crypto.PublicKey = null,
    freeze_key: ?crypto.PublicKey = null,
    wipe_key: ?crypto.PublicKey = null,
    supply_key: ?crypto.PublicKey = null,
    auto_renew_account: ?model.AccountId = null,
    auto_renew_period: ?i64 = null,
    memo_field: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) TokenUpdateTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenUpdateTransaction) void {
        self.builder.deinit();
    }

    pub fn setTokenId(self: *TokenUpdateTransaction, token_id: model.TokenId) *TokenUpdateTransaction {
        self.token_id = token_id;
        return self;
    }

    pub fn setTokenName(self: *TokenUpdateTransaction, name: []const u8) *TokenUpdateTransaction {
        self.name = name;
        return self;
    }

    pub fn setTokenSymbol(self: *TokenUpdateTransaction, symbol: []const u8) *TokenUpdateTransaction {
        self.symbol = symbol;
        return self;
    }

    pub fn setTreasuryAccountId(self: *TokenUpdateTransaction, account_id: model.AccountId) *TokenUpdateTransaction {
        self.treasury_account_id = account_id;
        return self;
    }

    pub fn setAdminKey(self: *TokenUpdateTransaction, key: crypto.PublicKey) *TokenUpdateTransaction {
        self.admin_key = key;
        return self;
    }

    pub fn setTokenMemo(self: *TokenUpdateTransaction, memo: []const u8) *TokenUpdateTransaction {
        self.memo_field = memo;
        return self;
    }

    pub fn freeze(self: *TokenUpdateTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.token_id) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(1, token_bytes);
        }

        if (self.name) |name| try body_writer.writeFieldString(2, name);
        if (self.symbol) |symbol| try body_writer.writeFieldString(3, symbol);

        if (self.treasury_account_id) |treasury| {
            const treasury_bytes = try encodeAccountId(self.allocator, treasury);
            defer self.allocator.free(treasury_bytes);
            try body_writer.writeFieldBytes(4, treasury_bytes);
        }

        if (self.admin_key) |key| {
            const key_bytes = try encodePublicKey(self.allocator, key);
            defer self.allocator.free(key_bytes);
            try body_writer.writeFieldBytes(5, key_bytes);
        }

        if (self.memo_field) |memo| try body_writer.writeFieldString(9, memo);

        const update_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(update_bytes);

        try writer.writeFieldBytes(34, update_bytes); // TokenUpdateTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenUpdateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenUpdateTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Delete a token
pub const TokenDeleteTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    token_id: ?model.TokenId = null,

    pub fn init(allocator: std.mem.Allocator) TokenDeleteTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenDeleteTransaction) void {
        self.builder.deinit();
    }

    pub fn setTokenId(self: *TokenDeleteTransaction, token_id: model.TokenId) *TokenDeleteTransaction {
        self.token_id = token_id;
        return self;
    }

    pub fn freeze(self: *TokenDeleteTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.token_id) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(1, token_bytes);
        }

        const delete_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(delete_bytes);

        try writer.writeFieldBytes(35, delete_bytes); // TokenDeleteTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenDeleteTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenDeleteTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Wipe token balance from an account
pub const TokenWipeTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    token_id: ?model.TokenId = null,
    account_id: ?model.AccountId = null,
    amount: u64 = 0,
    serial_numbers: ArrayListUnmanaged(u64) = .{},

    pub fn init(allocator: std.mem.Allocator) TokenWipeTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenWipeTransaction) void {
        self.serial_numbers.deinit(self.allocator);
        self.builder.deinit();
    }

    pub fn setTokenId(self: *TokenWipeTransaction, token_id: model.TokenId) *TokenWipeTransaction {
        self.token_id = token_id;
        return self;
    }

    pub fn setAccountId(self: *TokenWipeTransaction, account_id: model.AccountId) *TokenWipeTransaction {
        self.account_id = account_id;
        return self;
    }

    pub fn setAmount(self: *TokenWipeTransaction, amount: u64) *TokenWipeTransaction {
        self.amount = amount;
        return self;
    }

    pub fn addSerialNumber(self: *TokenWipeTransaction, serial: u64) !*TokenWipeTransaction {
        try self.serial_numbers.append(self.allocator, serial);
        return self;
    }

    pub fn freeze(self: *TokenWipeTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.token_id) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(1, token_bytes);
        }

        if (self.account_id) |account_id| {
            const account_bytes = try encodeAccountId(self.allocator, account_id);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(2, account_bytes);
        }

        if (self.amount > 0) {
            try body_writer.writeFieldVarint(3, self.amount);
        }

        for (self.serial_numbers.items) |serial| {
            try body_writer.writeFieldVarint(4, serial);
        }

        const wipe_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(wipe_bytes);

        try writer.writeFieldBytes(36, wipe_bytes); // TokenWipeAccountTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenWipeTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenWipeTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Freeze a token account
pub const TokenFreezeTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    token_id: ?model.TokenId = null,
    account_id: ?model.AccountId = null,

    pub fn init(allocator: std.mem.Allocator) TokenFreezeTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenFreezeTransaction) void {
        self.builder.deinit();
    }

    pub fn setTokenId(self: *TokenFreezeTransaction, token_id: model.TokenId) *TokenFreezeTransaction {
        self.token_id = token_id;
        return self;
    }

    pub fn setAccountId(self: *TokenFreezeTransaction, account_id: model.AccountId) *TokenFreezeTransaction {
        self.account_id = account_id;
        return self;
    }

    pub fn freeze(self: *TokenFreezeTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.token_id) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(1, token_bytes);
        }

        if (self.account_id) |account_id| {
            const account_bytes = try encodeAccountId(self.allocator, account_id);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(2, account_bytes);
        }

        const freeze_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(freeze_bytes);

        try writer.writeFieldBytes(37, freeze_bytes); // TokenFreezeAccountTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenFreezeTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenFreezeTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Unfreeze a token account
pub const TokenUnfreezeTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    token_id: ?model.TokenId = null,
    account_id: ?model.AccountId = null,

    pub fn init(allocator: std.mem.Allocator) TokenUnfreezeTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenUnfreezeTransaction) void {
        self.builder.deinit();
    }

    pub fn setTokenId(self: *TokenUnfreezeTransaction, token_id: model.TokenId) *TokenUnfreezeTransaction {
        self.token_id = token_id;
        return self;
    }

    pub fn setAccountId(self: *TokenUnfreezeTransaction, account_id: model.AccountId) *TokenUnfreezeTransaction {
        self.account_id = account_id;
        return self;
    }

    pub fn freeze(self: *TokenUnfreezeTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.token_id) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(1, token_bytes);
        }

        if (self.account_id) |account_id| {
            const account_bytes = try encodeAccountId(self.allocator, account_id);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(2, account_bytes);
        }

        const unfreeze_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(unfreeze_bytes);

        try writer.writeFieldBytes(38, unfreeze_bytes); // TokenUnfreezeAccountTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenUnfreezeTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenUnfreezeTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Pause a token
pub const TokenPauseTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    token_id: ?model.TokenId = null,

    pub fn init(allocator: std.mem.Allocator) TokenPauseTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenPauseTransaction) void {
        self.builder.deinit();
    }

    pub fn setTokenId(self: *TokenPauseTransaction, token_id: model.TokenId) *TokenPauseTransaction {
        self.token_id = token_id;
        return self;
    }

    pub fn freeze(self: *TokenPauseTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.token_id) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(1, token_bytes);
        }

        const pause_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(pause_bytes);

        try writer.writeFieldBytes(52, pause_bytes); // TokenPauseTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenPauseTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenPauseTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Unpause a token
pub const TokenUnpauseTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    token_id: ?model.TokenId = null,

    pub fn init(allocator: std.mem.Allocator) TokenUnpauseTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *TokenUnpauseTransaction) void {
        self.builder.deinit();
    }

    pub fn setTokenId(self: *TokenUnpauseTransaction, token_id: model.TokenId) *TokenUnpauseTransaction {
        self.token_id = token_id;
        return self;
    }

    pub fn freeze(self: *TokenUnpauseTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        if (self.token_id) |token_id| {
            const token_bytes = try encodeTokenId(self.allocator, token_id);
            defer self.allocator.free(token_bytes);
            try body_writer.writeFieldBytes(1, token_bytes);
        }

        const unpause_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(unpause_bytes);

        try writer.writeFieldBytes(53, unpause_bytes); // TokenUnpauseTransactionBody
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenUnpauseTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *TokenUnpauseTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};
