//! Smart Contract transaction builders for Hedera Smart Contract Service

const std = @import("std");
const model = @import("model.zig");
const crypto = @import("crypto.zig");
const proto = @import("ser/proto.zig");
const tx = @import("tx.zig");

const ArrayListUnmanaged = std.ArrayListUnmanaged;

/// Create a smart contract
pub const ContractCreateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    bytecode: []const u8 = "",
    admin_key: ?crypto.PublicKey = null,
    gas: u64 = 0,
    initial_balance: i64 = 0,
    auto_renew_period: ?i64 = null,
    auto_renew_account_id: ?model.AccountId = null,
    memo_field: []const u8 = "",
    max_automatic_token_associations: ?i32 = null,
    constructor_parameters: []const u8 = "",
    decline_staking_reward: bool = false,
    staked_account_id: ?model.AccountId = null,
    staked_node_id: ?i64 = null,

    pub fn init(allocator: std.mem.Allocator) ContractCreateTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *ContractCreateTransaction) void {
        self.builder.deinit();
    }

    pub fn setBytecode(self: *ContractCreateTransaction, bytecode: []const u8) *ContractCreateTransaction {
        self.bytecode = bytecode;
        return self;
    }

    pub fn setAdminKey(self: *ContractCreateTransaction, key: crypto.PublicKey) *ContractCreateTransaction {
        self.admin_key = key;
        return self;
    }

    pub fn setGas(self: *ContractCreateTransaction, gas: u64) *ContractCreateTransaction {
        self.gas = gas;
        return self;
    }

    pub fn setInitialBalance(self: *ContractCreateTransaction, tinybars: i64) *ContractCreateTransaction {
        self.initial_balance = tinybars;
        return self;
    }

    pub fn setAutoRenewPeriod(self: *ContractCreateTransaction, seconds: i64) *ContractCreateTransaction {
        self.auto_renew_period = seconds;
        return self;
    }

    pub fn setAutoRenewAccountId(self: *ContractCreateTransaction, account_id: model.AccountId) *ContractCreateTransaction {
        self.auto_renew_account_id = account_id;
        return self;
    }

    pub fn setContractMemo(self: *ContractCreateTransaction, memo: []const u8) *ContractCreateTransaction {
        self.memo_field = memo;
        return self;
    }

    pub fn setMaxAutomaticTokenAssociations(self: *ContractCreateTransaction, max: i32) *ContractCreateTransaction {
        self.max_automatic_token_associations = max;
        return self;
    }

    pub fn setConstructorParameters(self: *ContractCreateTransaction, params: []const u8) *ContractCreateTransaction {
        self.constructor_parameters = params;
        return self;
    }

    pub fn setDeclineStakingReward(self: *ContractCreateTransaction, decline: bool) *ContractCreateTransaction {
        self.decline_staking_reward = decline;
        return self;
    }

    pub fn setStakedAccountId(self: *ContractCreateTransaction, account_id: model.AccountId) *ContractCreateTransaction {
        self.staked_account_id = account_id;
        return self;
    }

    pub fn setStakedNodeId(self: *ContractCreateTransaction, node_id: i64) *ContractCreateTransaction {
        self.staked_node_id = node_id;
        return self;
    }

    pub fn freeze(self: *ContractCreateTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        // Field 1: file_id (for bytecode stored in file - not used if bytecode inline)

        // Field 2: bytecode (inline bytecode)
        if (self.bytecode.len > 0) {
            try body_writer.writeFieldBytes(2, self.bytecode);
        }

        // Field 3: admin_key
        if (self.admin_key) |key| {
            const key_bytes = try encodePublicKey(self.allocator, key);
            defer self.allocator.free(key_bytes);
            try body_writer.writeFieldBytes(3, key_bytes);
        }

        // Field 4: gas
        if (self.gas > 0) {
            try body_writer.writeFieldVarint(4, self.gas);
        }

        // Field 5: initial_balance
        if (self.initial_balance > 0) {
            try body_writer.writeFieldVarint(5, @as(u64, @intCast(self.initial_balance)));
        }

        // Field 6: auto_renew_period
        if (self.auto_renew_period) |renew_period| {
            var duration_writer = proto.Writer.init(self.allocator);
            defer duration_writer.deinit();
            try duration_writer.writeFieldVarint(1, @as(u64, @intCast(renew_period)));
            const duration_bytes = try duration_writer.toOwnedSlice();
            defer self.allocator.free(duration_bytes);
            try body_writer.writeFieldBytes(6, duration_bytes);
        }

        // Field 7: constructor_parameters
        if (self.constructor_parameters.len > 0) {
            try body_writer.writeFieldBytes(7, self.constructor_parameters);
        }

        // Field 8: memo
        if (self.memo_field.len > 0) {
            try body_writer.writeFieldString(8, self.memo_field);
        }

        // Field 9: max_automatic_token_associations
        if (self.max_automatic_token_associations) |max| {
            try body_writer.writeFieldVarint(9, @as(u64, @intCast(max)));
        }

        // Field 10: auto_renew_account_id
        if (self.auto_renew_account_id) |account_id| {
            const account_bytes = try encodeAccountId(self.allocator, account_id);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(10, account_bytes);
        }

        // Field 11: decline_staking_reward
        if (self.decline_staking_reward) {
            try body_writer.writeFieldBool(11, self.decline_staking_reward);
        }

        // Field 12: staked_account_id
        if (self.staked_account_id) |account_id| {
            const account_bytes = try encodeAccountId(self.allocator, account_id);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(12, account_bytes);
        }

        // Field 13: staked_node_id
        if (self.staked_node_id) |node_id| {
            try body_writer.writeFieldVarint(13, @as(u64, @intCast(node_id)));
        }

        const contract_create_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(contract_create_bytes);

        try writer.writeFieldBytes(7, contract_create_bytes); // ContractCreateTransactionBody = field 7
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *ContractCreateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *ContractCreateTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Call a smart contract function
pub const ContractExecuteTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    contract_id: ?model.ContractId = null,
    gas: u64 = 0,
    payable_amount: i64 = 0,
    function_parameters: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator) ContractExecuteTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *ContractExecuteTransaction) void {
        self.builder.deinit();
    }

    pub fn setContractId(self: *ContractExecuteTransaction, contract_id: model.ContractId) *ContractExecuteTransaction {
        self.contract_id = contract_id;
        return self;
    }

    pub fn setGas(self: *ContractExecuteTransaction, gas: u64) *ContractExecuteTransaction {
        self.gas = gas;
        return self;
    }

    pub fn setPayableAmount(self: *ContractExecuteTransaction, tinybars: i64) *ContractExecuteTransaction {
        self.payable_amount = tinybars;
        return self;
    }

    pub fn setFunctionParameters(self: *ContractExecuteTransaction, params: []const u8) *ContractExecuteTransaction {
        self.function_parameters = params;
        return self;
    }

    pub fn freeze(self: *ContractExecuteTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        // Field 1: contract_id
        if (self.contract_id) |contract_id| {
            const contract_bytes = try encodeContractId(self.allocator, contract_id);
            defer self.allocator.free(contract_bytes);
            try body_writer.writeFieldBytes(1, contract_bytes);
        }

        // Field 2: gas
        if (self.gas > 0) {
            try body_writer.writeFieldVarint(2, self.gas);
        }

        // Field 3: payable_amount
        if (self.payable_amount > 0) {
            try body_writer.writeFieldVarint(3, @as(u64, @intCast(self.payable_amount)));
        }

        // Field 4: function_parameters
        if (self.function_parameters.len > 0) {
            try body_writer.writeFieldBytes(4, self.function_parameters);
        }

        const contract_call_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(contract_call_bytes);

        try writer.writeFieldBytes(8, contract_call_bytes); // ContractCallTransactionBody = field 8
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *ContractExecuteTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *ContractExecuteTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Update a smart contract
pub const ContractUpdateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    contract_id: ?model.ContractId = null,
    admin_key: ?crypto.PublicKey = null,
    auto_renew_period: ?i64 = null,
    auto_renew_account_id: ?model.AccountId = null,
    expiration_time: ?i64 = null,
    memo_field: ?[]const u8 = null,
    max_automatic_token_associations: ?i32 = null,
    decline_staking_reward: ?bool = null,
    staked_account_id: ?model.AccountId = null,
    staked_node_id: ?i64 = null,

    pub fn init(allocator: std.mem.Allocator) ContractUpdateTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *ContractUpdateTransaction) void {
        self.builder.deinit();
    }

    pub fn setContractId(self: *ContractUpdateTransaction, contract_id: model.ContractId) *ContractUpdateTransaction {
        self.contract_id = contract_id;
        return self;
    }

    pub fn setAdminKey(self: *ContractUpdateTransaction, key: crypto.PublicKey) *ContractUpdateTransaction {
        self.admin_key = key;
        return self;
    }

    pub fn setAutoRenewPeriod(self: *ContractUpdateTransaction, seconds: i64) *ContractUpdateTransaction {
        self.auto_renew_period = seconds;
        return self;
    }

    pub fn setAutoRenewAccountId(self: *ContractUpdateTransaction, account_id: model.AccountId) *ContractUpdateTransaction {
        self.auto_renew_account_id = account_id;
        return self;
    }

    pub fn setExpirationTime(self: *ContractUpdateTransaction, seconds: i64) *ContractUpdateTransaction {
        self.expiration_time = seconds;
        return self;
    }

    pub fn setContractMemo(self: *ContractUpdateTransaction, memo: []const u8) *ContractUpdateTransaction {
        self.memo_field = memo;
        return self;
    }

    pub fn setMaxAutomaticTokenAssociations(self: *ContractUpdateTransaction, max: i32) *ContractUpdateTransaction {
        self.max_automatic_token_associations = max;
        return self;
    }

    pub fn setDeclineStakingReward(self: *ContractUpdateTransaction, decline: bool) *ContractUpdateTransaction {
        self.decline_staking_reward = decline;
        return self;
    }

    pub fn setStakedAccountId(self: *ContractUpdateTransaction, account_id: model.AccountId) *ContractUpdateTransaction {
        self.staked_account_id = account_id;
        return self;
    }

    pub fn setStakedNodeId(self: *ContractUpdateTransaction, node_id: i64) *ContractUpdateTransaction {
        self.staked_node_id = node_id;
        return self;
    }

    pub fn freeze(self: *ContractUpdateTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        // Field 1: contract_id
        if (self.contract_id) |contract_id| {
            const contract_bytes = try encodeContractId(self.allocator, contract_id);
            defer self.allocator.free(contract_bytes);
            try body_writer.writeFieldBytes(1, contract_bytes);
        }

        // Field 2: expiration_time
        if (self.expiration_time) |exp_time| {
            var timestamp_writer = proto.Writer.init(self.allocator);
            defer timestamp_writer.deinit();
            try timestamp_writer.writeFieldVarint(1, @as(u64, @intCast(exp_time)));
            const timestamp_bytes = try timestamp_writer.toOwnedSlice();
            defer self.allocator.free(timestamp_bytes);
            try body_writer.writeFieldBytes(2, timestamp_bytes);
        }

        // Field 3: admin_key
        if (self.admin_key) |key| {
            const key_bytes = try encodePublicKey(self.allocator, key);
            defer self.allocator.free(key_bytes);
            try body_writer.writeFieldBytes(3, key_bytes);
        }

        // Field 4: auto_renew_period
        if (self.auto_renew_period) |renew_period| {
            var duration_writer = proto.Writer.init(self.allocator);
            defer duration_writer.deinit();
            try duration_writer.writeFieldVarint(1, @as(u64, @intCast(renew_period)));
            const duration_bytes = try duration_writer.toOwnedSlice();
            defer self.allocator.free(duration_bytes);
            try body_writer.writeFieldBytes(4, duration_bytes);
        }

        // Field 6: memo (wrapped)
        if (self.memo_field) |memo| {
            var memo_wrapper = proto.Writer.init(self.allocator);
            defer memo_wrapper.deinit();
            try memo_wrapper.writeFieldString(1, memo);
            const memo_bytes = try memo_wrapper.toOwnedSlice();
            defer self.allocator.free(memo_bytes);
            try body_writer.writeFieldBytes(6, memo_bytes);
        }

        // Field 7: max_automatic_token_associations (wrapped)
        if (self.max_automatic_token_associations) |max| {
            var wrapper = proto.Writer.init(self.allocator);
            defer wrapper.deinit();
            try wrapper.writeFieldVarint(1, @as(u64, @intCast(max)));
            const wrapped_bytes = try wrapper.toOwnedSlice();
            defer self.allocator.free(wrapped_bytes);
            try body_writer.writeFieldBytes(7, wrapped_bytes);
        }

        // Field 8: auto_renew_account_id
        if (self.auto_renew_account_id) |account_id| {
            const account_bytes = try encodeAccountId(self.allocator, account_id);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(8, account_bytes);
        }

        // Field 9: decline_staking_reward (wrapped)
        if (self.decline_staking_reward) |decline| {
            var wrapper = proto.Writer.init(self.allocator);
            defer wrapper.deinit();
            try wrapper.writeFieldBool(1, decline);
            const wrapped_bytes = try wrapper.toOwnedSlice();
            defer self.allocator.free(wrapped_bytes);
            try body_writer.writeFieldBytes(9, wrapped_bytes);
        }

        // Field 10: staked_account_id
        if (self.staked_account_id) |account_id| {
            const account_bytes = try encodeAccountId(self.allocator, account_id);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(10, account_bytes);
        }

        // Field 11: staked_node_id
        if (self.staked_node_id) |node_id| {
            try body_writer.writeFieldVarint(11, @as(u64, @intCast(node_id)));
        }

        const contract_update_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(contract_update_bytes);

        try writer.writeFieldBytes(9, contract_update_bytes); // ContractUpdateTransactionBody = field 9
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *ContractUpdateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *ContractUpdateTransaction, client: anytype) !model.TransactionReceipt {
        try self.freeze();
        const tx_bytes = try self.builder.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }
};

/// Delete a smart contract
pub const ContractDeleteTransaction = struct {
    allocator: std.mem.Allocator,
    builder: tx.TransactionBuilder,
    contract_id: ?model.ContractId = null,
    transfer_account_id: ?model.AccountId = null,
    transfer_contract_id: ?model.ContractId = null,
    permanent_removal: bool = false,

    pub fn init(allocator: std.mem.Allocator) ContractDeleteTransaction {
        return .{
            .allocator = allocator,
            .builder = tx.TransactionBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *ContractDeleteTransaction) void {
        self.builder.deinit();
    }

    pub fn setContractId(self: *ContractDeleteTransaction, contract_id: model.ContractId) *ContractDeleteTransaction {
        self.contract_id = contract_id;
        return self;
    }

    pub fn setTransferAccountId(self: *ContractDeleteTransaction, account_id: model.AccountId) *ContractDeleteTransaction {
        self.transfer_account_id = account_id;
        return self;
    }

    pub fn setTransferContractId(self: *ContractDeleteTransaction, contract_id: model.ContractId) *ContractDeleteTransaction {
        self.transfer_contract_id = contract_id;
        return self;
    }

    pub fn setPermanentRemoval(self: *ContractDeleteTransaction, permanent: bool) *ContractDeleteTransaction {
        self.permanent_removal = permanent;
        return self;
    }

    pub fn freeze(self: *ContractDeleteTransaction) !void {
        var writer = proto.Writer.init(self.allocator);
        defer writer.deinit();

        var body_writer = proto.Writer.init(self.allocator);
        defer body_writer.deinit();

        // Field 1: contract_id
        if (self.contract_id) |contract_id| {
            const contract_bytes = try encodeContractId(self.allocator, contract_id);
            defer self.allocator.free(contract_bytes);
            try body_writer.writeFieldBytes(1, contract_bytes);
        }

        // Field 2: transfer_account_id
        if (self.transfer_account_id) |account_id| {
            const account_bytes = try encodeAccountId(self.allocator, account_id);
            defer self.allocator.free(account_bytes);
            try body_writer.writeFieldBytes(2, account_bytes);
        }

        // Field 3: transfer_contract_id
        if (self.transfer_contract_id) |contract_id| {
            const contract_bytes = try encodeContractId(self.allocator, contract_id);
            defer self.allocator.free(contract_bytes);
            try body_writer.writeFieldBytes(3, contract_bytes);
        }

        // Field 4: permanent_removal
        if (self.permanent_removal) {
            try body_writer.writeFieldBool(4, self.permanent_removal);
        }

        const contract_delete_bytes = try body_writer.toOwnedSlice();
        defer self.allocator.free(contract_delete_bytes);

        try writer.writeFieldBytes(22, contract_delete_bytes); // ContractDeleteTransactionBody = field 22
        const body = try writer.toOwnedSlice();
        try self.builder.setBody(body);
    }

    pub fn sign(self: *ContractDeleteTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn execute(self: *ContractDeleteTransaction, client: anytype) !model.TransactionReceipt {
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

fn encodeContractId(allocator: std.mem.Allocator, contract_id: model.ContractId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldVarint(1, contract_id.shard);
    try writer.writeFieldVarint(2, contract_id.realm);
    try writer.writeFieldVarint(3, contract_id.num);
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
