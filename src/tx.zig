//! Transaction builders for write operations

const std = @import("std");
const model = @import("model.zig");
const crypto = @import("crypto.zig");
const proto = @import("ser/proto.zig");

const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub const TransactionBuilder = struct {
    allocator: ?std.mem.Allocator = null,
    transaction_id: ?model.TransactionId = null,
    node_account_id: ?model.AccountId = null,
    valid_duration_seconds: u32 = 120,
    memo: []const u8 = "",
    max_transaction_fee: model.Hbar = model.Hbar.fromTinybars(1_000_000),
    body_bytes: ?[]u8 = null,
    is_frozen: bool = false,
    signatures: ArrayListUnmanaged(SignaturePair) = .{},

    const SignaturePair = struct {
        public_key: [32]u8,
        signature: [64]u8,
    };

    pub fn init(allocator: std.mem.Allocator) TransactionBuilder {
        return .{ .allocator = allocator };
    }

    pub fn setAllocator(self: *TransactionBuilder, allocator: std.mem.Allocator) *TransactionBuilder {
        self.allocator = allocator;
        return self;
    }

    pub fn deinit(self: *TransactionBuilder) void {
        if (self.body_bytes) |bytes| {
            if (self.allocator) |alloc| alloc.free(bytes);
        }
        if (self.allocator) |alloc| {
            self.signatures.deinit(alloc);
        }
        self.body_bytes = null;
        self.signatures = .{};
        self.is_frozen = false;
        self.transaction_id = null;
    }

    pub fn setTransactionId(self: *TransactionBuilder, tx_id: model.TransactionId) *TransactionBuilder {
        self.transaction_id = tx_id;
        return self;
    }

    pub fn setNodeAccountId(self: *TransactionBuilder, account_id: model.AccountId) *TransactionBuilder {
        self.node_account_id = account_id;
        return self;
    }

    pub fn setValidDuration(self: *TransactionBuilder, seconds: u32) *TransactionBuilder {
        self.valid_duration_seconds = seconds;
        return self;
    }

    pub fn setMemo(self: *TransactionBuilder, memo: []const u8) *TransactionBuilder {
        self.memo = memo;
        return self;
    }

    pub fn setMaxTransactionFee(self: *TransactionBuilder, fee: model.Hbar) *TransactionBuilder {
        self.max_transaction_fee = fee;
        return self;
    }

    fn requireAllocator(self: *TransactionBuilder) !std.mem.Allocator {
        return self.allocator orelse error.AllocatorRequired;
    }

    pub fn freeze(self: *TransactionBuilder) void {
        if (self.transaction_id == null) {
            self.transaction_id = model.TransactionId.generate(model.AccountId.init(0, 0, 1));
        }
    }

    pub fn setBody(self: *TransactionBuilder, body: []u8) !void {
        const allocator = try self.requireAllocator();
        if (self.body_bytes) |existing| allocator.free(existing);
        self.body_bytes = body;
        self.is_frozen = true;
    }

    pub fn sign(self: *TransactionBuilder, private_key: crypto.PrivateKey) !void {
        if (!self.is_frozen or self.body_bytes == null) return error.TransactionNotFrozen;
        const allocator = try self.requireAllocator();
        const signature_bytes = try private_key.sign(self.body_bytes.?);
        const public_key = private_key.publicKey();
        const prefix = public_key.toBytes();
        try self.signatures.append(allocator, .{ .public_key = prefix, .signature = signature_bytes });
    }

    pub fn toBytes(self: *TransactionBuilder) ![]u8 {
        if (!self.is_frozen or self.body_bytes == null) return error.TransactionNotFrozen;
        const allocator = try self.requireAllocator();
        const signed_bytes = try encodeSignedTransaction(allocator, self.body_bytes.?, self.signatures.items);
        defer allocator.free(signed_bytes);

        var writer = proto.Writer.init(allocator);
        defer writer.deinit();
        try writer.writeFieldBytes(5, signed_bytes);
        return try writer.toOwnedSlice();
    }
};

pub const CryptoTransferTransaction = struct {
    allocator: std.mem.Allocator,
    builder: TransactionBuilder,
    transfers: ArrayListUnmanaged(Transfer) = .{},

    const Transfer = struct {
        account_id: model.AccountId,
        amount: model.Hbar,
    };

    pub fn init(allocator: std.mem.Allocator) CryptoTransferTransaction {
        return .{
            .allocator = allocator,
            .builder = TransactionBuilder.init(allocator),
            .transfers = .{},
        };
    }

    pub fn deinit(self: *CryptoTransferTransaction) void {
        self.transfers.deinit(self.allocator);
        self.builder.deinit();
    }

    pub fn addHbarTransfer(self: *CryptoTransferTransaction, account_id: model.AccountId, amount: model.Hbar) !void {
        try self.transfers.append(self.allocator, .{ .account_id = account_id, .amount = amount });
    }

    pub fn setTransactionId(self: *CryptoTransferTransaction, tx_id: model.TransactionId) *CryptoTransferTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn setNodeAccountId(self: *CryptoTransferTransaction, account_id: model.AccountId) *CryptoTransferTransaction {
        _ = self.builder.setNodeAccountId(account_id);
        return self;
    }

    pub fn freeze(self: *CryptoTransferTransaction) !void {
        self.builder.freeze();
        const body = try encodeCryptoTransferBody(self.allocator, &self.builder, self.transfers.items);
        errdefer self.allocator.free(body);
        try self.builder.setBody(body);
    }

    pub fn sign(self: *CryptoTransferTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: *CryptoTransferTransaction) ![]u8 {
        return try self.builder.toBytes();
    }

    /// Execute this transaction by submitting to the network and waiting for receipt
    pub fn execute(self: *CryptoTransferTransaction, client: anytype) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }

        const tx_bytes = try self.toBytes();
        defer self.allocator.free(tx_bytes);

        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    /// Execute this transaction and return just the transaction ID (don't wait for receipt)
    pub fn executeAsync(self: *CryptoTransferTransaction, client: anytype) !model.TransactionId {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }

        const tx_bytes = try self.toBytes();
        defer self.allocator.free(tx_bytes);

        const response = try client.consensus_client.submitTransaction(tx_bytes);
        return response.transaction_id;
    }
};

fn encodeCryptoTransferBody(
    allocator: std.mem.Allocator,
    builder: *TransactionBuilder,
    transfers: []const CryptoTransferTransaction.Transfer,
) ![]u8 {
    const tx_id = builder.transaction_id orelse return error.TransactionNotFrozen;

    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const tx_id_bytes = try encodeTransactionId(allocator, tx_id);
    defer allocator.free(tx_id_bytes);
    try writer.writeFieldBytes(1, tx_id_bytes);

    if (builder.node_account_id) |node_id| {
        const node_bytes = try encodeAccountId(allocator, node_id);
        defer allocator.free(node_bytes);
        try writer.writeFieldBytes(2, node_bytes);
    }

    const fee = builder.max_transaction_fee.toTinybars();
    if (fee < 0) return error.InvalidFee;
    const fee_u64: u64 = @intCast(fee);
    try writer.writeFieldUint64(3, fee_u64);

    const duration_bytes = try encodeDuration(allocator, builder.valid_duration_seconds);
    defer allocator.free(duration_bytes);
    try writer.writeFieldBytes(4, duration_bytes);

    if (builder.memo.len > 0) {
        try writer.writeFieldString(6, builder.memo);
    }

    const transfer_body = try encodeCryptoTransferTransactionBody(allocator, transfers);
    defer allocator.free(transfer_body);
    try writer.writeFieldBytes(14, transfer_body);

    return try writer.toOwnedSlice();
}

fn encodeTopicSubmitTransactionBody(
    allocator: std.mem.Allocator,
    builder: *TransactionBuilder,
    topic_id: model.TopicId,
    message: []const u8,
) ![]u8 {
    if (message.len == 0) return error.EmptyMessage;
    if (message.len > max_topic_message_bytes) return error.MessageTooLarge;

    const tx_id = builder.transaction_id orelse return error.TransactionNotFrozen;

    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const tx_id_bytes = try encodeTransactionId(allocator, tx_id);
    defer allocator.free(tx_id_bytes);
    try writer.writeFieldBytes(1, tx_id_bytes);

    if (builder.node_account_id) |node_id| {
        const node_bytes = try encodeAccountId(allocator, node_id);
        defer allocator.free(node_bytes);
        try writer.writeFieldBytes(2, node_bytes);
    }

    const fee = builder.max_transaction_fee.toTinybars();
    if (fee < 0) return error.InvalidFee;
    const fee_u64: u64 = @intCast(fee);
    try writer.writeFieldUint64(3, fee_u64);

    const duration_bytes = try encodeDuration(allocator, builder.valid_duration_seconds);
    defer allocator.free(duration_bytes);
    try writer.writeFieldBytes(4, duration_bytes);

    if (builder.memo.len > 0) {
        try writer.writeFieldString(6, builder.memo);
    }

    const submit_body = try encodeConsensusSubmitMessageTransactionBody(allocator, topic_id, message);
    defer allocator.free(submit_body);
    try writer.writeFieldBytes(27, submit_body);

    return try writer.toOwnedSlice();
}

fn encodeConsensusSubmitMessageTransactionBody(
    allocator: std.mem.Allocator,
    topic_id: model.TopicId,
    message: []const u8,
) ![]u8 {
    if (message.len == 0) return error.EmptyMessage;
    if (message.len > max_topic_message_bytes) return error.MessageTooLarge;

    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const topic_bytes = try encodeTopicId(allocator, topic_id);
    defer allocator.free(topic_bytes);
    try writer.writeFieldBytes(1, topic_bytes);
    try writer.writeFieldBytes(2, message);

    return try writer.toOwnedSlice();
}

fn encodeCryptoTransferTransactionBody(
    allocator: std.mem.Allocator,
    transfers: []const CryptoTransferTransaction.Transfer,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    if (transfers.len > 0) {
        const transfer_list = try encodeTransferList(allocator, transfers);
        defer allocator.free(transfer_list);
        try writer.writeFieldBytes(1, transfer_list);
    }

    return try writer.toOwnedSlice();
}

fn encodeTopicId(allocator: std.mem.Allocator, topic_id: model.TopicId) ![]u8 {
    return try encodeAccountId(allocator, topic_id);
}

fn encodeTokenId(allocator: std.mem.Allocator, token_id: model.TokenId) ![]u8 {
    return try encodeAccountId(allocator, token_id);
}

fn encodeTokenTransferBody(
    allocator: std.mem.Allocator,
    builder: *TransactionBuilder,
    fungible: []const TokenTransferTransaction.FungibleTransfer,
    nfts: []const TokenTransferTransaction.NftTransfer,
) ![]u8 {
    const tx_id = builder.transaction_id orelse return error.TransactionNotFrozen;

    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const tx_id_bytes = try encodeTransactionId(allocator, tx_id);
    defer allocator.free(tx_id_bytes);
    try writer.writeFieldBytes(1, tx_id_bytes);

    if (builder.node_account_id) |node_id| {
        const node_bytes = try encodeAccountId(allocator, node_id);
        defer allocator.free(node_bytes);
        try writer.writeFieldBytes(2, node_bytes);
    }

    const fee = builder.max_transaction_fee.toTinybars();
    if (fee < 0) return error.InvalidFee;
    const fee_u64: u64 = @intCast(fee);
    try writer.writeFieldUint64(3, fee_u64);

    const duration_bytes = try encodeDuration(allocator, builder.valid_duration_seconds);
    defer allocator.free(duration_bytes);
    try writer.writeFieldBytes(4, duration_bytes);

    if (builder.memo.len > 0) {
        try writer.writeFieldString(6, builder.memo);
    }

    const transfer_body = try encodeTokenTransferTransactionBody(allocator, fungible, nfts);
    errdefer allocator.free(transfer_body);
    try writer.writeFieldBytes(14, transfer_body);
    allocator.free(transfer_body);

    return try writer.toOwnedSlice();
}

fn encodeTokenTransferTransactionBody(
    allocator: std.mem.Allocator,
    fungible: []const TokenTransferTransaction.FungibleTransfer,
    nfts: []const TokenTransferTransaction.NftTransfer,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    try encodeFungibleTokenTransferGroups(allocator, &writer, fungible);
    try encodeNftTokenTransferGroups(allocator, &writer, nfts);

    return try writer.toOwnedSlice();
}

const FungibleGroup = struct {
    token_id: model.TokenId,
    indices: std.ArrayList(usize),
};

fn encodeFungibleTokenTransferGroups(
    allocator: std.mem.Allocator,
    writer: *proto.Writer,
    entries: []const TokenTransferTransaction.FungibleTransfer,
) !void {
    if (entries.len == 0) return;

    var groups = std.ArrayList(FungibleGroup).empty;
    defer {
        for (groups.items) |*group| group.indices.deinit(allocator);
        groups.deinit(allocator);
    }

    for (entries, 0..) |entry, idx| {
        const group_index = try ensureFungibleGroup(allocator, &groups, entry.token_id);
        try groups.items[group_index].indices.append(allocator, idx);
    }

    for (groups.items) |group| {
        var list_writer = proto.Writer.init(allocator);
        defer list_writer.deinit();

        const token_bytes = try encodeTokenId(allocator, group.token_id);
        defer allocator.free(token_bytes);
        try list_writer.writeFieldBytes(1, token_bytes);

        for (group.indices.items) |entry_index| {
            const entry = entries[entry_index];
            const account_amount = try encodeTokenAccountAmount(allocator, entry);
            errdefer allocator.free(account_amount);
            try list_writer.writeFieldBytes(2, account_amount);
            allocator.free(account_amount);
        }

        const list_bytes = try list_writer.toOwnedSlice();
        errdefer allocator.free(list_bytes);
        try writer.writeFieldBytes(2, list_bytes);
        allocator.free(list_bytes);
    }
}

const NftGroup = struct {
    token_id: model.TokenId,
    indices: std.ArrayList(usize),
};

fn encodeNftTokenTransferGroups(
    allocator: std.mem.Allocator,
    writer: *proto.Writer,
    entries: []const TokenTransferTransaction.NftTransfer,
) !void {
    if (entries.len == 0) return;

    var groups = std.ArrayList(NftGroup).empty;
    defer {
        for (groups.items) |*group| group.indices.deinit(allocator);
        groups.deinit(allocator);
    }

    for (entries, 0..) |entry, idx| {
        const group_index = try ensureNftGroup(allocator, &groups, entry.token_id);
        try groups.items[group_index].indices.append(allocator, idx);
    }

    for (groups.items) |group| {
        var list_writer = proto.Writer.init(allocator);
        defer list_writer.deinit();

        const token_bytes = try encodeTokenId(allocator, group.token_id);
        defer allocator.free(token_bytes);
        try list_writer.writeFieldBytes(1, token_bytes);

        for (group.indices.items) |entry_index| {
            const entry = entries[entry_index];
            const nft_transfer = try encodeNftTransferMessage(allocator, entry);
            errdefer allocator.free(nft_transfer);
            try list_writer.writeFieldBytes(3, nft_transfer);
            allocator.free(nft_transfer);
        }

        const list_bytes = try list_writer.toOwnedSlice();
        errdefer allocator.free(list_bytes);
        try writer.writeFieldBytes(2, list_bytes);
        allocator.free(list_bytes);
    }
}

fn ensureFungibleGroup(
    allocator: std.mem.Allocator,
    groups: *std.ArrayList(FungibleGroup),
    token_id: model.TokenId,
) !usize {
    for (groups.items, 0..) |group, idx| {
        if (std.meta.eql(group.token_id, token_id)) return idx;
    }
    const new_group = FungibleGroup{
        .token_id = token_id,
        .indices = std.ArrayList(usize).empty,
    };
    try groups.append(allocator, new_group);
    return groups.items.len - 1;
}

fn ensureNftGroup(
    allocator: std.mem.Allocator,
    groups: *std.ArrayList(NftGroup),
    token_id: model.TokenId,
) !usize {
    for (groups.items, 0..) |group, idx| {
        if (std.meta.eql(group.token_id, token_id)) return idx;
    }
    const new_group = NftGroup{
        .token_id = token_id,
        .indices = std.ArrayList(usize).empty,
    };
    try groups.append(allocator, new_group);
    return groups.items.len - 1;
}

fn encodeTokenAccountAmount(
    allocator: std.mem.Allocator,
    transfer: TokenTransferTransaction.FungibleTransfer,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const account_bytes = try encodeAccountId(allocator, transfer.account_id);
    defer allocator.free(account_bytes);
    try writer.writeFieldBytes(1, account_bytes);
    try writer.writeFieldInt64(2, transfer.amount);
    if (transfer.is_approval) try writer.writeFieldBool(3, true);

    return try writer.toOwnedSlice();
}

fn encodeNftTransferMessage(
    allocator: std.mem.Allocator,
    transfer: TokenTransferTransaction.NftTransfer,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const sender_bytes = try encodeAccountId(allocator, transfer.sender);
    defer allocator.free(sender_bytes);
    try writer.writeFieldBytes(1, sender_bytes);

    const receiver_bytes = try encodeAccountId(allocator, transfer.receiver);
    defer allocator.free(receiver_bytes);
    try writer.writeFieldBytes(2, receiver_bytes);

    try writer.writeFieldInt64(3, transfer.serial);
    if (transfer.is_approval) try writer.writeFieldBool(4, true);

    return try writer.toOwnedSlice();
}

fn encodeTokenAssociateBody(
    allocator: std.mem.Allocator,
    builder: *TransactionBuilder,
    account_id: model.AccountId,
    token_ids: []const model.TokenId,
) ![]u8 {
    const tx_id = builder.transaction_id orelse return error.TransactionNotFrozen;

    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const tx_id_bytes = try encodeTransactionId(allocator, tx_id);
    defer allocator.free(tx_id_bytes);
    try writer.writeFieldBytes(1, tx_id_bytes);

    if (builder.node_account_id) |node_id| {
        const node_bytes = try encodeAccountId(allocator, node_id);
        defer allocator.free(node_bytes);
        try writer.writeFieldBytes(2, node_bytes);
    }

    const fee = builder.max_transaction_fee.toTinybars();
    if (fee < 0) return error.InvalidFee;
    const fee_u64: u64 = @intCast(fee);
    try writer.writeFieldUint64(3, fee_u64);

    const duration_bytes = try encodeDuration(allocator, builder.valid_duration_seconds);
    defer allocator.free(duration_bytes);
    try writer.writeFieldBytes(4, duration_bytes);

    if (builder.memo.len > 0) {
        try writer.writeFieldString(6, builder.memo);
    }

    const associate_body = try encodeTokenAssociationBody(allocator, account_id, token_ids);
    errdefer allocator.free(associate_body);
    try writer.writeFieldBytes(40, associate_body);
    allocator.free(associate_body);

    return try writer.toOwnedSlice();
}

fn encodeTokenDissociateBody(
    allocator: std.mem.Allocator,
    builder: *TransactionBuilder,
    account_id: model.AccountId,
    token_ids: []const model.TokenId,
) ![]u8 {
    const tx_id = builder.transaction_id orelse return error.TransactionNotFrozen;

    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const tx_id_bytes = try encodeTransactionId(allocator, tx_id);
    defer allocator.free(tx_id_bytes);
    try writer.writeFieldBytes(1, tx_id_bytes);

    if (builder.node_account_id) |node_id| {
        const node_bytes = try encodeAccountId(allocator, node_id);
        defer allocator.free(node_bytes);
        try writer.writeFieldBytes(2, node_bytes);
    }

    const fee = builder.max_transaction_fee.toTinybars();
    if (fee < 0) return error.InvalidFee;
    const fee_u64: u64 = @intCast(fee);
    try writer.writeFieldUint64(3, fee_u64);

    const duration_bytes = try encodeDuration(allocator, builder.valid_duration_seconds);
    defer allocator.free(duration_bytes);
    try writer.writeFieldBytes(4, duration_bytes);

    if (builder.memo.len > 0) {
        try writer.writeFieldString(6, builder.memo);
    }

    const dissociate_body = try encodeTokenAssociationBody(allocator, account_id, token_ids);
    errdefer allocator.free(dissociate_body);
    try writer.writeFieldBytes(41, dissociate_body);
    allocator.free(dissociate_body);

    return try writer.toOwnedSlice();
}

fn encodeTokenAssociationBody(
    allocator: std.mem.Allocator,
    account_id: model.AccountId,
    token_ids: []const model.TokenId,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const account_bytes = try encodeAccountId(allocator, account_id);
    defer allocator.free(account_bytes);
    try writer.writeFieldBytes(1, account_bytes);

    for (token_ids) |token_id| {
        const token_bytes = try encodeTokenId(allocator, token_id);
        errdefer allocator.free(token_bytes);
        try writer.writeFieldBytes(2, token_bytes);
        allocator.free(token_bytes);
    }

    return try writer.toOwnedSlice();
}

fn encodeTransferList(
    allocator: std.mem.Allocator,
    transfers: []const CryptoTransferTransaction.Transfer,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    for (transfers) |transfer| {
        const account_amount = try encodeAccountAmount(allocator, transfer);
        defer allocator.free(account_amount);
        try writer.writeFieldBytes(1, account_amount);
    }

    return try writer.toOwnedSlice();
}

fn encodeAccountAmount(
    allocator: std.mem.Allocator,
    transfer: CryptoTransferTransaction.Transfer,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const account_bytes = try encodeAccountId(allocator, transfer.account_id);
    defer allocator.free(account_bytes);
    try writer.writeFieldBytes(1, account_bytes);
    try writer.writeFieldInt64(2, transfer.amount.toTinybars());
    if (transfer.is_approval) try writer.writeFieldBool(3, true);

    return try writer.toOwnedSlice();
}

fn encodeTransactionId(allocator: std.mem.Allocator, tx_id: model.TransactionId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const timestamp_bytes = try encodeTimestamp(allocator, tx_id.valid_start);
    defer allocator.free(timestamp_bytes);
    try writer.writeFieldBytes(1, timestamp_bytes);

    const account_bytes = try encodeAccountId(allocator, tx_id.account_id);
    defer allocator.free(account_bytes);
    try writer.writeFieldBytes(2, account_bytes);

    if (tx_id.scheduled) {
        try writer.writeFieldBool(3, true);
    }

    if (tx_id.nonce) |nonce| {
        const nonce_u64: u64 = @intCast(nonce);
        try writer.writeFieldVarint(4, nonce_u64);
    }

    return try writer.toOwnedSlice();
}

fn encodeAccountId(allocator: std.mem.Allocator, account_id: model.AccountId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    try writer.writeFieldUint64(1, account_id.shard);
    try writer.writeFieldUint64(2, account_id.realm);
    try writer.writeFieldUint64(3, account_id.num);

    return try writer.toOwnedSlice();
}

fn encodeTimestamp(allocator: std.mem.Allocator, timestamp: model.Timestamp) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const seconds_bits: u64 = @bitCast(timestamp.seconds);
    const nanos_bits: u64 = @intCast(timestamp.nanos);
    try writer.writeFieldVarint(1, seconds_bits);
    try writer.writeFieldVarint(2, nanos_bits);

    return try writer.toOwnedSlice();
}

fn encodeDuration(allocator: std.mem.Allocator, seconds: u32) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    try writer.writeFieldVarint(1, @as(u64, seconds));
    return try writer.toOwnedSlice();
}

fn encodeSignaturePair(allocator: std.mem.Allocator, sig: TransactionBuilder.SignaturePair) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    try writer.writeFieldBytes(1, sig.public_key[0..]);
    try writer.writeFieldBytes(3, sig.signature[0..]);
    return try writer.toOwnedSlice();
}

fn encodeSignatureMap(
    allocator: std.mem.Allocator,
    signatures: []const TransactionBuilder.SignaturePair,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    for (signatures) |sig| {
        const pair_bytes = try encodeSignaturePair(allocator, sig);
        defer allocator.free(pair_bytes);
        try writer.writeFieldBytes(1, pair_bytes);
    }

    return try writer.toOwnedSlice();
}

fn encodeSignedTransaction(
    allocator: std.mem.Allocator,
    body_bytes: []const u8,
    signatures: []const TransactionBuilder.SignaturePair,
) ![]u8 {
    const sig_map = try encodeSignatureMap(allocator, signatures);
    defer allocator.free(sig_map);

    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldBytes(1, body_bytes);
    try writer.writeFieldBytes(2, sig_map);
    return try writer.toOwnedSlice();
}

const ProtoField = struct {
    field_number: u32,
    wire_type: u3,
    value: []const u8,
    varint: u64,

    fn asBytes(self: ProtoField) []const u8 {
        return self.value;
    }

    fn asVarint(self: ProtoField) u64 {
        return self.varint;
    }
};

const ProtoReader = struct {
    data: []const u8,
    index: usize = 0,

    const Error = error{
        UnexpectedEnd,
        VarintOverflow,
        UnsupportedWireType,
    };

    fn init(data: []const u8) ProtoReader {
        return .{ .data = data, .index = 0 };
    }

    fn next(self: *ProtoReader) Error!?ProtoField {
        if (self.index >= self.data.len) return null;

        const key = try self.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: u3 = @intCast(key & 0x7);

        switch (wire_type) {
            0 => {
                const value = try self.readVarint();
                return ProtoField{
                    .field_number = field_number,
                    .wire_type = wire_type,
                    .value = &[_]u8{},
                    .varint = value,
                };
            },
            2 => {
                const len_u64 = try self.readVarint();
                if (len_u64 > self.data.len - self.index) return error.UnexpectedEnd;
                const len: usize = @intCast(len_u64);
                const start = self.index;
                self.index += len;
                return ProtoField{
                    .field_number = field_number,
                    .wire_type = wire_type,
                    .value = self.data[start .. start + len],
                    .varint = 0,
                };
            },
            else => return error.UnsupportedWireType,
        }
    }

    fn readVarint(self: *ProtoReader) Error!u64 {
        var shift: u6 = 0;
        var value: u64 = 0;
        while (true) {
            if (self.index >= self.data.len) return error.UnexpectedEnd;
            const byte = self.data[self.index];
            self.index += 1;

            value |= (@as(u64, byte & 0x7f) << shift);
            if ((byte & 0x80) == 0) break;
            shift += 7;
            if (shift >= 64) return error.VarintOverflow;
        }
        return value;
    }
};

fn expectField(reader: *ProtoReader, number: u32, wire_type: u3) !ProtoField {
    const field_opt = try reader.next() orelse return error.MissingField;
    if (field_opt.field_number != number or field_opt.wire_type != wire_type) return error.UnexpectedField;
    return field_opt;
}

fn varintToI64(value: u64) i64 {
    return @bitCast(value);
}

test "encodeSignedTransaction emits body and signature map" {
    const allocator = std.testing.allocator;

    const body = [_]u8{ 0x01, 0x02, 0x03 };
    var pub_key: [32]u8 = undefined;
    var signature: [64]u8 = undefined;
    for (&pub_key, 0..) |*byte, idx| byte.* = @intCast(idx);
    for (&signature, 0..) |*byte, idx| byte.* = @intCast(idx + 1);

    const pairs = [_]TransactionBuilder.SignaturePair{
        .{ .public_key = pub_key, .signature = signature },
    };

    const encoded = try encodeSignedTransaction(allocator, &body, pairs[0..]);
    defer allocator.free(encoded);

    var reader = ProtoReader.init(encoded);
    const body_field = try expectField(&reader, 1, 2);
    try std.testing.expectEqualSlices(u8, &body, body_field.asBytes());

    const sig_map_field = try expectField(&reader, 2, 2);
    var sig_reader = ProtoReader.init(sig_map_field.asBytes());
    const pair_field = try expectField(&sig_reader, 1, 2);

    var pair_reader = ProtoReader.init(pair_field.asBytes());
    const prefix_field = try expectField(&pair_reader, 1, 2);
    try std.testing.expectEqualSlices(u8, &pub_key, prefix_field.asBytes());
    const sig_field = try expectField(&pair_reader, 3, 2);
    try std.testing.expectEqualSlices(u8, &signature, sig_field.asBytes());
}

test "encodeCryptoTransferBody encodes transaction body and transfers" {
    const allocator = std.testing.allocator;

    var builder = TransactionBuilder.init(allocator);
    defer builder.deinit();

    const tx_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 1111),
        .valid_start = .{ .seconds = 1, .nanos = 2 },
        .nonce = null,
        .scheduled = false,
    };
    builder.setTransactionId(tx_id);
    builder.setNodeAccountId(model.AccountId.init(0, 0, 3));
    builder.setMaxTransactionFee(model.Hbar.fromTinybars(1_000));
    builder.setMemo("memo");

    const transfers = [_]CryptoTransferTransaction.Transfer{
        .{ .account_id = model.AccountId.init(0, 0, 1111), .amount = model.Hbar.fromTinybars(-10) },
        .{ .account_id = model.AccountId.init(0, 0, 2222), .amount = model.Hbar.fromTinybars(10) },
    };

    const body = try encodeCryptoTransferBody(allocator, &builder, transfers[0..]);
    defer allocator.free(body);

    var reader = ProtoReader.init(body);
    const tx_id_field = try expectField(&reader, 1, 2);
    var tx_id_reader = ProtoReader.init(tx_id_field.asBytes());
    const account_field = try expectField(&tx_id_reader, 2, 2);
    var account_reader = ProtoReader.init(account_field.asBytes());
    const shard_field = try expectField(&account_reader, 1, 0);
    try std.testing.expectEqual(@as(u64, 0), shard_field.asVarint());
    const realm_field = try expectField(&account_reader, 2, 0);
    try std.testing.expectEqual(@as(u64, 0), realm_field.asVarint());
    const num_field = try expectField(&account_reader, 3, 0);
    try std.testing.expectEqual(@as(u64, 1111), num_field.asVarint());

    const transfer_field = try expectField(&reader, 14, 2);
    var transfer_body_reader = ProtoReader.init(transfer_field.asBytes());
    const list_field = try expectField(&transfer_body_reader, 1, 2);
    var list_reader = ProtoReader.init(list_field.asBytes());

    const first_transfer = try expectField(&list_reader, 1, 2);
    var first_reader = ProtoReader.init(first_transfer.asBytes());
    const first_amount_field = try expectField(&first_reader, 2, 0);
    const first_amount = varintToI64(first_amount_field.asVarint());
    try std.testing.expectEqual(@as(i64, -10), first_amount);

    const second_transfer = try expectField(&list_reader, 1, 2);
    var second_reader = ProtoReader.init(second_transfer.asBytes());
    const second_amount_field = try expectField(&second_reader, 2, 0);
    const second_amount = varintToI64(second_amount_field.asVarint());
    try std.testing.expectEqual(@as(i64, 10), second_amount);
}

test "TopicMessageSubmitTransaction encodes message body" {
    const allocator = std.testing.allocator;

    var tx = TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();

    const tx_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 5001),
        .valid_start = .{ .seconds = 1_700_000_000, .nanos = 42 },
    };

    tx.setTransactionId(tx_id);
    tx.setNodeAccountId(model.AccountId.init(0, 0, 3));
    _ = tx.setValidDuration(120);
    try tx.setTopicId(model.TopicId.init(0, 0, 6001));
    try tx.setMessage("hello world");
    try tx.freeze();

    const bytes = try tx.toBytes();
    defer allocator.free(bytes);

    var signed_reader = ProtoReader.init(bytes);
    const body_field = try expectField(&signed_reader, 1, 2);
    var body_reader = ProtoReader.init(body_field.asBytes());

    const tx_id_field = try expectField(&body_reader, 1, 2);
    var tx_id_reader = ProtoReader.init(tx_id_field.asBytes());
    const account_field = try expectField(&tx_id_reader, 2, 2);
    var account_reader = ProtoReader.init(account_field.asBytes());
    _ = try expectField(&account_reader, 1, 0);
    _ = try expectField(&account_reader, 2, 0);
    const account_num = try expectField(&account_reader, 3, 0);
    try std.testing.expectEqual(@as(u64, 5001), account_num.asVarint());

    const submit_field = try expectField(&body_reader, 27, 2);
    var submit_reader = ProtoReader.init(submit_field.asBytes());
    const topic_field = try expectField(&submit_reader, 1, 2);
    var topic_reader = ProtoReader.init(topic_field.asBytes());
    _ = try expectField(&topic_reader, 1, 0);
    _ = try expectField(&topic_reader, 2, 0);
    const topic_num = try expectField(&topic_reader, 3, 0);
    try std.testing.expectEqual(@as(u64, 6001), topic_num.asVarint());
    const message_field = try expectField(&submit_reader, 2, 2);
    try std.testing.expectEqualStrings("hello world", message_field.asBytes());
}

test "TopicMessageSubmitTransaction rejects oversized message" {
    const allocator = std.testing.allocator;

    var tx = TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();

    try tx.setTopicId(model.TopicId.init(0, 0, 7001));

    const big_len = TopicMessageSubmitTransaction.max_message_bytes + 1;
    const big = try allocator.alloc(u8, big_len);
    defer allocator.free(big);
    @memset(big, 'a');

    try std.testing.expectError(error.MessageTooLarge, tx.setMessage(big));
}

test "TopicMessageSubmitTransaction requires topic id before freeze" {
    const allocator = std.testing.allocator;

    var tx = TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();

    try tx.setMessage("ready");
    try std.testing.expectError(error.TopicIdRequired, tx.freeze());
}

test "TopicMessageSubmitTransaction produces signature" {
    const allocator = std.testing.allocator;

    var tx = TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();

    const tx_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 4001),
        .valid_start = .{ .seconds = 1_700_000_123, .nanos = 256 },
    };

    tx.setTransactionId(tx_id);
    tx.setNodeAccountId(model.AccountId.init(0, 0, 3));
    try tx.setTopicId(model.TopicId.init(0, 0, 6002));
    try tx.setMessage("signed payload");
    try tx.freeze();

    var key = crypto.PrivateKey.generateEd25519();
    try tx.sign(key);

    const bytes = try tx.toBytes();
    defer allocator.free(bytes);

    var signed_reader = ProtoReader.init(bytes);
    const body_field = try expectField(&signed_reader, 1, 2);
    const sig_map_field = try expectField(&signed_reader, 2, 2);

    var sig_map_reader = ProtoReader.init(sig_map_field.asBytes());
    const pair_field = try expectField(&sig_map_reader, 1, 2);
    var pair_reader = ProtoReader.init(pair_field.asBytes());
    const prefix_field = try expectField(&pair_reader, 1, 2);
    const sig_field = try expectField(&pair_reader, 3, 2);

    try std.testing.expectEqual(@as(usize, 32), prefix_field.asBytes().len);
    try std.testing.expectEqual(@as(usize, 64), sig_field.asBytes().len);

    var signature: [64]u8 = undefined;
    std.mem.copy(u8, signature[0..], sig_field.asBytes());

    const public_key = key.publicKey();
    try public_key.verify(body_field.asBytes(), signature);
}

test "TokenTransferTransaction encodes fungible and nft transfers" {
    const allocator = std.testing.allocator;

    var tx = TokenTransferTransaction.init(allocator);
    defer tx.deinit();

    const tx_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 5001),
        .valid_start = .{ .seconds = 1_700_000_000, .nanos = 100 },
    };

    const fungible_token = model.TokenId.init(0, 0, 9001);
    const nft_token = model.TokenId.init(0, 0, 9002);

    tx.setTransactionId(tx_id);
    tx.setNodeAccountId(model.AccountId.init(0, 0, 4));
    try tx.addTokenTransfer(fungible_token, model.AccountId.init(0, 0, 1111), -50);
    try tx.addTokenTransfer(fungible_token, model.AccountId.init(0, 0, 2222), 50);
    try tx.addNftTransfer(nft_token, model.AccountId.init(0, 0, 3333), model.AccountId.init(0, 0, 4444), 7);
    try tx.freeze();

    const bytes = try tx.toBytes();
    defer allocator.free(bytes);

    var signed_reader = ProtoReader.init(bytes);
    const body_field = try expectField(&signed_reader, 1, 2);
    var body_reader = ProtoReader.init(body_field.asBytes());
    _ = try expectField(&body_reader, 1, 2);
    const crypto_field = try expectField(&body_reader, 14, 2);
    var crypto_reader = ProtoReader.init(crypto_field.asBytes());

    const list_a = try expectField(&crypto_reader, 2, 2);
    const list_b = try expectField(&crypto_reader, 2, 2);
    try std.testing.expectEqual(@as(?ProtoField, null), try crypto_reader.next());

    const lists = [_]ProtoField{ list_a, list_b };
    var fungible_found = false;
    var nft_found = false;
    for (lists) |list_field| {
        var list_reader = ProtoReader.init(list_field.asBytes());
        const token_field = try expectField(&list_reader, 1, 2);
        var token_reader = ProtoReader.init(token_field.asBytes());
        const shard_field = try expectField(&token_reader, 1, 0);
        const realm_field = try expectField(&token_reader, 2, 0);
        const num_field = try expectField(&token_reader, 3, 0);

        const shard = shard_field.asVarint();
        const realm = realm_field.asVarint();
        const num = num_field.asVarint();

        const next_field = try list_reader.next() orelse return error.MissingField;
        if (next_field.field_number == 2) {
            try std.testing.expect(!fungible_found);
            fungible_found = true;
            try std.testing.expectEqual(@as(u64, fungible_token.shard), shard);
            try std.testing.expectEqual(@as(u64, fungible_token.realm), realm);
            try std.testing.expectEqual(@as(u64, fungible_token.num), num);

            var amount_reader = ProtoReader.init(next_field.asBytes());
            const sender_account = try expectField(&amount_reader, 1, 2);
            var sender_reader = ProtoReader.init(sender_account.asBytes());
            _ = try expectField(&sender_reader, 1, 0);
            _ = try expectField(&sender_reader, 2, 0);
            const sender_num = try expectField(&sender_reader, 3, 0);
            try std.testing.expectEqual(@as(u64, 1111), sender_num.asVarint());
            const sender_amount = try expectField(&amount_reader, 2, 0);
            try std.testing.expectEqual(@as(i64, -50), varintToI64(sender_amount.asVarint()));

            const receiver_field = try expectField(&list_reader, 2, 2);
            var receiver_reader = ProtoReader.init(receiver_field.asBytes());
            const recv_account_field = try expectField(&receiver_reader, 1, 2);
            var recv_account_reader = ProtoReader.init(recv_account_field.asBytes());
            _ = try expectField(&recv_account_reader, 1, 0);
            _ = try expectField(&recv_account_reader, 2, 0);
            const recv_num = try expectField(&recv_account_reader, 3, 0);
            try std.testing.expectEqual(@as(u64, 2222), recv_num.asVarint());
            const recv_amount = try expectField(&receiver_reader, 2, 0);
            try std.testing.expectEqual(@as(i64, 50), varintToI64(recv_amount.asVarint()));

            try std.testing.expectEqual(@as(?ProtoField, null), try list_reader.next());
        } else {
            try std.testing.expectEqual(@as(u32, 3), next_field.field_number);
            try std.testing.expect(!nft_found);
            nft_found = true;
            try std.testing.expectEqual(@as(u64, nft_token.shard), shard);
            try std.testing.expectEqual(@as(u64, nft_token.realm), realm);
            try std.testing.expectEqual(@as(u64, nft_token.num), num);

            var nft_reader = ProtoReader.init(next_field.asBytes());
            const sender_field = try expectField(&nft_reader, 1, 2);
            var nft_sender_reader = ProtoReader.init(sender_field.asBytes());
            _ = try expectField(&nft_sender_reader, 1, 0);
            _ = try expectField(&nft_sender_reader, 2, 0);
            const nft_sender_num = try expectField(&nft_sender_reader, 3, 0);
            try std.testing.expectEqual(@as(u64, 3333), nft_sender_num.asVarint());

            const receiver_field = try expectField(&nft_reader, 2, 2);
            var nft_receiver_reader = ProtoReader.init(receiver_field.asBytes());
            _ = try expectField(&nft_receiver_reader, 1, 0);
            _ = try expectField(&nft_receiver_reader, 2, 0);
            const nft_receiver_num = try expectField(&nft_receiver_reader, 3, 0);
            try std.testing.expectEqual(@as(u64, 4444), nft_receiver_num.asVarint());

            const serial_field = try expectField(&nft_reader, 3, 0);
            try std.testing.expectEqual(@as(i64, 7), varintToI64(serial_field.asVarint()));

            try std.testing.expectEqual(@as(?ProtoField, null), try list_reader.next());
        }
    }

    try std.testing.expect(fungible_found);
    try std.testing.expect(nft_found);
}

test "TokenTransferTransaction requires transfer before freeze" {
    const allocator = std.testing.allocator;

    var tx = TokenTransferTransaction.init(allocator);
    defer tx.deinit();

    try std.testing.expectError(error.EmptyTokenTransfer, tx.freeze());
}

test "TokenAssociateTransaction encodes account and tokens" {
    const allocator = std.testing.allocator;

    var tx = TokenAssociateTransaction.init(allocator);
    defer tx.deinit();

    const tx_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 5100),
        .valid_start = .{ .seconds = 1_700_000_500, .nanos = 88 },
    };
    const account = model.AccountId.init(0, 0, 7000);
    const token_a = model.TokenId.init(0, 0, 9003);
    const token_b = model.TokenId.init(0, 0, 9004);

    tx.setTransactionId(tx_id);
    tx.setNodeAccountId(model.AccountId.init(0, 0, 8));
    _ = tx.setAccountId(account);
    try tx.addTokenId(token_a);
    try tx.addTokenId(token_b);
    try tx.freeze();

    const bytes = try tx.toBytes();
    defer allocator.free(bytes);

    var signed_reader = ProtoReader.init(bytes);
    const body_field = try expectField(&signed_reader, 1, 2);
    var body_reader = ProtoReader.init(body_field.asBytes());
    _ = try expectField(&body_reader, 1, 2);
    const associate_field = try expectField(&body_reader, 40, 2);
    var associate_reader = ProtoReader.init(associate_field.asBytes());

    const account_field = try expectField(&associate_reader, 1, 2);
    var account_reader = ProtoReader.init(account_field.asBytes());
    _ = try expectField(&account_reader, 1, 0);
    _ = try expectField(&account_reader, 2, 0);
    const account_num = try expectField(&account_reader, 3, 0);
    try std.testing.expectEqual(@as(u64, account.num), account_num.asVarint());

    const token_field_a = try expectField(&associate_reader, 2, 2);
    var token_reader_a = ProtoReader.init(token_field_a.asBytes());
    _ = try expectField(&token_reader_a, 1, 0);
    _ = try expectField(&token_reader_a, 2, 0);
    const token_num_a = try expectField(&token_reader_a, 3, 0);
    try std.testing.expectEqual(@as(u64, token_a.num), token_num_a.asVarint());

    const token_field_b = try expectField(&associate_reader, 2, 2);
    var token_reader_b = ProtoReader.init(token_field_b.asBytes());
    _ = try expectField(&token_reader_b, 1, 0);
    _ = try expectField(&token_reader_b, 2, 0);
    const token_num_b = try expectField(&token_reader_b, 3, 0);
    try std.testing.expectEqual(@as(u64, token_b.num), token_num_b.asVarint());

    try std.testing.expectEqual(@as(?ProtoField, null), try associate_reader.next());
}

test "TokenAssociateTransaction requires tokens before freeze" {
    const allocator = std.testing.allocator;

    var tx = TokenAssociateTransaction.init(allocator);
    defer tx.deinit();

    _ = tx.setAccountId(model.AccountId.init(0, 0, 7000));
    try std.testing.expectError(error.NoTokensSpecified, tx.freeze());
}

test "TokenAssociateTransaction requires account before freeze" {
    const allocator = std.testing.allocator;

    var tx = TokenAssociateTransaction.init(allocator);
    defer tx.deinit();

    const token_id = model.TokenId.init(0, 0, 8000);
    try tx.addTokenId(token_id);
    try std.testing.expectError(error.AccountIdRequired, tx.freeze());
}

test "TokenDissociateTransaction encodes account and tokens" {
    const allocator = std.testing.allocator;

    var tx = TokenDissociateTransaction.init(allocator);
    defer tx.deinit();

    const tx_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 5200),
        .valid_start = .{ .seconds = 1_700_000_700, .nanos = 99 },
    };
    const account = model.AccountId.init(0, 0, 7100);
    const token = model.TokenId.init(0, 0, 9100);

    tx.setTransactionId(tx_id);
    tx.setNodeAccountId(model.AccountId.init(0, 0, 9));
    _ = tx.setAccountId(account);
    try tx.addTokenId(token);
    try tx.freeze();

    const bytes = try tx.toBytes();
    defer allocator.free(bytes);

    var signed_reader = ProtoReader.init(bytes);
    const body_field = try expectField(&signed_reader, 1, 2);
    var body_reader = ProtoReader.init(body_field.asBytes());
    _ = try expectField(&body_reader, 1, 2);
    const dissociate_field = try expectField(&body_reader, 41, 2);
    var dissociate_reader = ProtoReader.init(dissociate_field.asBytes());

    const account_field = try expectField(&dissociate_reader, 1, 2);
    var account_reader = ProtoReader.init(account_field.asBytes());
    _ = try expectField(&account_reader, 1, 0);
    _ = try expectField(&account_reader, 2, 0);
    const account_num = try expectField(&account_reader, 3, 0);
    try std.testing.expectEqual(@as(u64, account.num), account_num.asVarint());

    const token_field = try expectField(&dissociate_reader, 2, 2);
    var token_reader = ProtoReader.init(token_field.asBytes());
    _ = try expectField(&token_reader, 1, 0);
    _ = try expectField(&token_reader, 2, 0);
    const token_num = try expectField(&token_reader, 3, 0);
    try std.testing.expectEqual(@as(u64, token.num), token_num.asVarint());

    try std.testing.expectEqual(@as(?ProtoField, null), try dissociate_reader.next());
}

test "TokenDissociateTransaction requires tokens before freeze" {
    const allocator = std.testing.allocator;

    var tx = TokenDissociateTransaction.init(allocator);
    defer tx.deinit();

    _ = tx.setAccountId(model.AccountId.init(0, 0, 7100));
    try std.testing.expectError(error.NoTokensSpecified, tx.freeze());
}

test "TokenDissociateTransaction requires account before freeze" {
    const allocator = std.testing.allocator;

    var tx = TokenDissociateTransaction.init(allocator);
    defer tx.deinit();

    const token_id = model.TokenId.init(0, 0, 9101);
    try tx.addTokenId(token_id);
    try std.testing.expectError(error.AccountIdRequired, tx.freeze());
}

test "TokenTransferTransaction rejects invalid NFT serial" {
    const allocator = std.testing.allocator;

    var tx = TokenTransferTransaction.init(allocator);
    defer tx.deinit();

    try std.testing.expectError(error.InvalidSerialNumber, tx.addNftTransfer(model.TokenId.init(0, 0, 9005), model.AccountId.init(0, 0, 1), model.AccountId.init(0, 0, 2), 0));
}

const max_topic_message_bytes: usize = 6_144;

pub const TopicMessageSubmitTransaction = struct {
    allocator: std.mem.Allocator,
    builder: TransactionBuilder,
    topic_id: ?model.TopicId = null,
    message: []u8 = &[_]u8{},

    pub const max_message_bytes = max_topic_message_bytes;

    pub fn init(allocator: std.mem.Allocator) TopicMessageSubmitTransaction {
        return .{ .allocator = allocator, .builder = TransactionBuilder.init(allocator) };
    }

    pub fn deinit(self: *TopicMessageSubmitTransaction) void {
        if (self.message.len > 0) self.allocator.free(self.message);
        self.message = &[_]u8{};
        self.builder.deinit();
    }

    pub fn setTopicId(self: *TopicMessageSubmitTransaction, topic_id: model.TopicId) *TopicMessageSubmitTransaction {
        self.topic_id = topic_id;
        return self;
    }

    pub fn setMessage(self: *TopicMessageSubmitTransaction, message: []const u8) !*TopicMessageSubmitTransaction {
        if (message.len == 0) return error.EmptyMessage;
        if (message.len > max_topic_message_bytes) return error.MessageTooLarge;
        if (self.message.len > 0) self.allocator.free(self.message);
        self.message = try self.allocator.dupe(u8, message);
        return self;
    }

    pub fn setTransactionId(self: *TopicMessageSubmitTransaction, tx_id: model.TransactionId) *TopicMessageSubmitTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn setNodeAccountId(self: *TopicMessageSubmitTransaction, account_id: model.AccountId) *TopicMessageSubmitTransaction {
        _ = self.builder.setNodeAccountId(account_id);
        return self;
    }

    pub fn setValidDuration(self: *TopicMessageSubmitTransaction, seconds: u32) *TopicMessageSubmitTransaction {
        _ = self.builder.setValidDuration(seconds);
        return self;
    }

    pub fn setMemo(self: *TopicMessageSubmitTransaction, memo: []const u8) *TopicMessageSubmitTransaction {
        _ = self.builder.setMemo(memo);
        return self;
    }

    pub fn setMaxTransactionFee(self: *TopicMessageSubmitTransaction, fee: model.Hbar) *TopicMessageSubmitTransaction {
        _ = self.builder.setMaxTransactionFee(fee);
        return self;
    }

    pub fn freeze(self: *TopicMessageSubmitTransaction) !void {
        const topic = self.topic_id orelse return error.TopicIdRequired;
        if (self.message.len == 0) return error.EmptyMessage;

        self.builder.freeze();
        const body = try encodeTopicSubmitTransactionBody(self.allocator, &self.builder, topic, self.message);
        errdefer self.allocator.free(body);
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TopicMessageSubmitTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: *TopicMessageSubmitTransaction) ![]u8 {
        return try self.builder.toBytes();
    }

    pub fn execute(self: *TopicMessageSubmitTransaction, client: anytype) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    pub fn executeAsync(self: *TopicMessageSubmitTransaction, client: anytype) !model.TransactionResponse {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes();
        defer self.allocator.free(tx_bytes);
        return try client.consensus_client.submitTransaction(tx_bytes);
    }
};

pub const AccountCreateTransaction = struct {
    builder: TransactionBuilder = .{},
    key: ?crypto.PublicKey = null,
    initial_balance: model.Hbar = model.Hbar.ZERO,
    receiver_sig_required: bool = false,
    auto_renew_period: ?i64 = null,
    memo: []const u8 = "",
    max_automatic_token_associations: ?u32 = null,
    alias: ?[]const u8 = null,
    decline_staking_reward: bool = false,
    staked_account_id: ?model.AccountId = null,
    staked_node_id: ?u64 = null,

    pub fn setKey(self: *AccountCreateTransaction, key: crypto.PublicKey) *AccountCreateTransaction {
        self.key = key;
        return self;
    }

    pub fn setInitialBalance(self: *AccountCreateTransaction, balance: model.Hbar) *AccountCreateTransaction {
        self.initial_balance = balance;
        return self;
    }

    pub fn setReceiverSigRequired(self: *AccountCreateTransaction, required: bool) *AccountCreateTransaction {
        self.receiver_sig_required = required;
        return self;
    }

    pub fn setAutoRenewPeriod(self: *AccountCreateTransaction, seconds: i64) *AccountCreateTransaction {
        self.auto_renew_period = seconds;
        return self;
    }

    pub fn setMemo(self: *AccountCreateTransaction, memo: []const u8) *AccountCreateTransaction {
        self.memo = memo;
        return self;
    }

    pub fn setMaxAutomaticTokenAssociations(self: *AccountCreateTransaction, max: u32) *AccountCreateTransaction {
        self.max_automatic_token_associations = max;
        return self;
    }

    pub fn setAlias(self: *AccountCreateTransaction, alias: []const u8) *AccountCreateTransaction {
        self.alias = alias;
        return self;
    }

    pub fn setDeclineStakingReward(self: *AccountCreateTransaction, decline: bool) *AccountCreateTransaction {
        self.decline_staking_reward = decline;
        return self;
    }

    pub fn setStakedAccountId(self: *AccountCreateTransaction, account_id: model.AccountId) *AccountCreateTransaction {
        self.staked_account_id = account_id;
        return self;
    }

    pub fn setStakedNodeId(self: *AccountCreateTransaction, node_id: u64) *AccountCreateTransaction {
        self.staked_node_id = node_id;
        return self;
    }

    pub fn setTransactionId(self: *AccountCreateTransaction, tx_id: model.TransactionId) *AccountCreateTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn freeze(self: *AccountCreateTransaction) !void {
        try self.builder.freeze();
    }

    pub fn sign(self: *AccountCreateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: AccountCreateTransaction, allocator: std.mem.Allocator) ![]u8 {
        return self.builder.toBytes(allocator);
    }

    pub fn execute(self: *AccountCreateTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    pub fn executeAsync(self: *AccountCreateTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionResponse {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        return try client.consensus_client.submitTransaction(tx_bytes);
    }
};

pub const AccountUpdateTransaction = struct {
    builder: TransactionBuilder = .{},
    account_id: ?model.AccountId = null,
    key: ?crypto.PublicKey = null,
    receiver_sig_required: ?bool = null,
    auto_renew_period: ?i64 = null,
    memo: ?[]const u8 = null,
    max_automatic_token_associations: ?u32 = null,
    decline_staking_reward: ?bool = null,
    staked_account_id: ?model.AccountId = null,
    staked_node_id: ?u64 = null,
    expiration_time: ?model.Timestamp = null,

    pub fn setAccountId(self: *AccountUpdateTransaction, account_id: model.AccountId) *AccountUpdateTransaction {
        self.account_id = account_id;
        return self;
    }

    pub fn setKey(self: *AccountUpdateTransaction, key: crypto.PublicKey) *AccountUpdateTransaction {
        self.key = key;
        return self;
    }

    pub fn setReceiverSigRequired(self: *AccountUpdateTransaction, required: bool) *AccountUpdateTransaction {
        self.receiver_sig_required = required;
        return self;
    }

    pub fn setAutoRenewPeriod(self: *AccountUpdateTransaction, seconds: i64) *AccountUpdateTransaction {
        self.auto_renew_period = seconds;
        return self;
    }

    pub fn setMemo(self: *AccountUpdateTransaction, memo: []const u8) *AccountUpdateTransaction {
        self.memo = memo;
        return self;
    }

    pub fn setMaxAutomaticTokenAssociations(self: *AccountUpdateTransaction, max: u32) *AccountUpdateTransaction {
        self.max_automatic_token_associations = max;
        return self;
    }

    pub fn setDeclineStakingReward(self: *AccountUpdateTransaction, decline: bool) *AccountUpdateTransaction {
        self.decline_staking_reward = decline;
        return self;
    }

    pub fn setStakedAccountId(self: *AccountUpdateTransaction, account_id: model.AccountId) *AccountUpdateTransaction {
        self.staked_account_id = account_id;
        return self;
    }

    pub fn setStakedNodeId(self: *AccountUpdateTransaction, node_id: u64) *AccountUpdateTransaction {
        self.staked_node_id = node_id;
        return self;
    }

    pub fn setExpirationTime(self: *AccountUpdateTransaction, timestamp: model.Timestamp) *AccountUpdateTransaction {
        self.expiration_time = timestamp;
        return self;
    }

    pub fn setTransactionId(self: *AccountUpdateTransaction, tx_id: model.TransactionId) *AccountUpdateTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn freeze(self: *AccountUpdateTransaction) !void {
        try self.builder.freeze();
    }

    pub fn sign(self: *AccountUpdateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: AccountUpdateTransaction, allocator: std.mem.Allocator) ![]u8 {
        return self.builder.toBytes(allocator);
    }

    pub fn execute(self: *AccountUpdateTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    pub fn executeAsync(self: *AccountUpdateTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionResponse {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        return try client.consensus_client.submitTransaction(tx_bytes);
    }
};

pub const AccountDeleteTransaction = struct {
    builder: TransactionBuilder = .{},
    account_id: ?model.AccountId = null,
    transfer_account_id: ?model.AccountId = null,

    pub fn setAccountId(self: *AccountDeleteTransaction, account_id: model.AccountId) *AccountDeleteTransaction {
        self.account_id = account_id;
        return self;
    }

    pub fn setTransferAccountId(self: *AccountDeleteTransaction, transfer_account_id: model.AccountId) *AccountDeleteTransaction {
        self.transfer_account_id = transfer_account_id;
        return self;
    }

    pub fn setTransactionId(self: *AccountDeleteTransaction, tx_id: model.TransactionId) *AccountDeleteTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn freeze(self: *AccountDeleteTransaction) !void {
        try self.builder.freeze();
    }

    pub fn sign(self: *AccountDeleteTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: AccountDeleteTransaction, allocator: std.mem.Allocator) ![]u8 {
        return self.builder.toBytes(allocator);
    }

    pub fn execute(self: *AccountDeleteTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    pub fn executeAsync(self: *AccountDeleteTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionResponse {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        return try client.consensus_client.submitTransaction(tx_bytes);
    }
};

pub const TokenCreateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: TransactionBuilder = .{},
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
    fee_schedule_key: ?crypto.PublicKey = null,
    pause_key: ?crypto.PublicKey = null,
    token_type: model.TokenType = .fungible_common,
    supply_type: model.TokenSupplyType = .infinite,
    max_supply: ?u64 = null,
    freeze_default: bool = false,
    auto_renew_period: ?i64 = null,
    auto_renew_account_id: ?model.AccountId = null,
    memo: []const u8 = "",
    custom_fees: std.ArrayList(model.CustomFee) = std.ArrayList(model.CustomFee).empty,

    pub fn init(allocator: std.mem.Allocator) TokenCreateTransaction {
        return .{
            .allocator = allocator,
            .builder = TransactionBuilder.init(allocator),
            .custom_fees = std.ArrayList(model.CustomFee).empty,
        };
    }

    pub fn deinit(self: *TokenCreateTransaction) void {
        self.custom_fees.deinit(self.allocator);
        self.builder.deinit();
    }

    pub fn setName(self: *TokenCreateTransaction, name: []const u8) *TokenCreateTransaction {
        self.name = name;
        return self;
    }

    pub fn setSymbol(self: *TokenCreateTransaction, symbol: []const u8) *TokenCreateTransaction {
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

    pub fn setFeeScheduleKey(self: *TokenCreateTransaction, key: crypto.PublicKey) *TokenCreateTransaction {
        self.fee_schedule_key = key;
        return self;
    }

    pub fn setPauseKey(self: *TokenCreateTransaction, key: crypto.PublicKey) *TokenCreateTransaction {
        self.pause_key = key;
        return self;
    }

    pub fn setTokenType(self: *TokenCreateTransaction, token_type: model.TokenType) *TokenCreateTransaction {
        self.token_type = token_type;
        return self;
    }

    pub fn setSupplyType(self: *TokenCreateTransaction, supply_type: model.TokenSupplyType) *TokenCreateTransaction {
        self.supply_type = supply_type;
        return self;
    }

    pub fn setMaxSupply(self: *TokenCreateTransaction, max_supply: u64) *TokenCreateTransaction {
        self.max_supply = max_supply;
        return self;
    }

    pub fn setFreezeDefault(self: *TokenCreateTransaction, freeze_default: bool) *TokenCreateTransaction {
        self.freeze_default = freeze_default;
        return self;
    }

    pub fn setAutoRenewPeriod(self: *TokenCreateTransaction, seconds: i64) *TokenCreateTransaction {
        self.auto_renew_period = seconds;
        return self;
    }

    pub fn setAutoRenewAccountId(self: *TokenCreateTransaction, account_id: model.AccountId) *TokenCreateTransaction {
        self.auto_renew_account_id = account_id;
        return self;
    }

    pub fn setMemo(self: *TokenCreateTransaction, memo: []const u8) *TokenCreateTransaction {
        self.memo = memo;
        return self;
    }

    pub fn addCustomFee(self: *TokenCreateTransaction, fee: model.CustomFee) !*TokenCreateTransaction {
        try self.custom_fees.append(self.allocator, fee);
        return self;
    }

    pub fn setTransactionId(self: *TokenCreateTransaction, tx_id: model.TransactionId) *TokenCreateTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn freeze(self: *TokenCreateTransaction) !void {
        try self.builder.freeze();
    }

    pub fn sign(self: *TokenCreateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: TokenCreateTransaction, allocator: std.mem.Allocator) ![]u8 {
        return self.builder.toBytes(allocator);
    }

    pub fn execute(self: *TokenCreateTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    pub fn executeAsync(self: *TokenCreateTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionResponse {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        return try client.consensus_client.submitTransaction(tx_bytes);
    }
};

pub const TokenTransferTransaction = struct {
    allocator: std.mem.Allocator,
    builder: TransactionBuilder,
    fungible: std.ArrayList(FungibleTransfer),
    nfts: std.ArrayList(NftTransfer),

    const FungibleTransfer = struct {
        token_id: model.TokenId,
        account_id: model.AccountId,
        amount: i64,
        is_approval: bool = false,
    };

    const NftTransfer = struct {
        token_id: model.TokenId,
        sender: model.AccountId,
        receiver: model.AccountId,
        serial: i64,
        is_approval: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) TokenTransferTransaction {
        return .{
            .allocator = allocator,
            .builder = TransactionBuilder.init(allocator),
            .fungible = std.ArrayList(FungibleTransfer).empty,
            .nfts = std.ArrayList(NftTransfer).empty,
        };
    }

    pub fn deinit(self: *TokenTransferTransaction) void {
        self.fungible.deinit(self.allocator);
        self.nfts.deinit(self.allocator);
        self.builder.deinit();
    }

    pub fn addTokenTransfer(self: *TokenTransferTransaction, token_id: model.TokenId, account_id: model.AccountId, amount: i64) !void {
        if (amount == 0) return error.ZeroTokenTransfer;
        try self.fungible.append(self.allocator, .{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
        });
    }

    pub fn addTokenTransferWithApproval(
        self: *TokenTransferTransaction,
        token_id: model.TokenId,
        account_id: model.AccountId,
        amount: i64,
        is_approval: bool,
    ) !void {
        if (amount == 0) return error.ZeroTokenTransfer;
        try self.fungible.append(self.allocator, .{
            .token_id = token_id,
            .account_id = account_id,
            .amount = amount,
            .is_approval = is_approval,
        });
    }

    pub fn addNftTransfer(
        self: *TokenTransferTransaction,
        token_id: model.TokenId,
        sender: model.AccountId,
        receiver: model.AccountId,
        serial: i64,
    ) !void {
        try self.addNftTransferWithApproval(token_id, sender, receiver, serial, false);
    }

    pub fn addNftTransferWithApproval(
        self: *TokenTransferTransaction,
        token_id: model.TokenId,
        sender: model.AccountId,
        receiver: model.AccountId,
        serial: i64,
        is_approval: bool,
    ) !void {
        if (serial <= 0) return error.InvalidSerialNumber;
        try self.nfts.append(self.allocator, .{
            .token_id = token_id,
            .sender = sender,
            .receiver = receiver,
            .serial = serial,
            .is_approval = is_approval,
        });
    }

    pub fn setTransactionId(self: *TokenTransferTransaction, tx_id: model.TransactionId) *TokenTransferTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn setNodeAccountId(self: *TokenTransferTransaction, account_id: model.AccountId) *TokenTransferTransaction {
        _ = self.builder.setNodeAccountId(account_id);
        return self;
    }

    pub fn setValidDuration(self: *TokenTransferTransaction, seconds: u32) *TokenTransferTransaction {
        _ = self.builder.setValidDuration(seconds);
        return self;
    }

    pub fn setMemo(self: *TokenTransferTransaction, memo: []const u8) *TokenTransferTransaction {
        _ = self.builder.setMemo(memo);
        return self;
    }

    pub fn setMaxTransactionFee(self: *TokenTransferTransaction, fee: model.Hbar) *TokenTransferTransaction {
        _ = self.builder.setMaxTransactionFee(fee);
        return self;
    }

    pub fn freeze(self: *TokenTransferTransaction) !void {
        if (self.fungible.items.len == 0 and self.nfts.items.len == 0) return error.EmptyTokenTransfer;
        self.builder.freeze();
        const body = try encodeTokenTransferBody(self.allocator, &self.builder, self.fungible.items, self.nfts.items);
        errdefer self.allocator.free(body);
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenTransferTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: *TokenTransferTransaction) ![]u8 {
        return try self.builder.toBytes();
    }

    /// Execute this transaction by submitting to the network and waiting for receipt
    pub fn execute(self: *TokenTransferTransaction, client: anytype) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }

        const tx_bytes = try self.toBytes();
        defer self.allocator.free(tx_bytes);

        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    /// Execute this transaction and return just the transaction ID (don't wait for receipt)
    pub fn executeAsync(self: *TokenTransferTransaction, client: anytype) !model.TransactionId {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }

        const tx_bytes = try self.toBytes();
        defer self.allocator.free(tx_bytes);

        const response = try client.consensus_client.submitTransaction(tx_bytes);
        return response.transaction_id orelse return error.NoTransactionId;
    }
};

pub const TokenAssociateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: TransactionBuilder,
    account_id: ?model.AccountId = null,
    token_ids: std.ArrayList(model.TokenId),

    pub fn init(allocator: std.mem.Allocator) TokenAssociateTransaction {
        return .{
            .allocator = allocator,
            .builder = TransactionBuilder.init(allocator),
            .token_ids = std.ArrayList(model.TokenId).empty,
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

    pub fn setTransactionId(self: *TokenAssociateTransaction, tx_id: model.TransactionId) *TokenAssociateTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn setNodeAccountId(self: *TokenAssociateTransaction, account_id: model.AccountId) *TokenAssociateTransaction {
        _ = self.builder.setNodeAccountId(account_id);
        return self;
    }

    pub fn setValidDuration(self: *TokenAssociateTransaction, seconds: u32) *TokenAssociateTransaction {
        _ = self.builder.setValidDuration(seconds);
        return self;
    }

    pub fn setMemo(self: *TokenAssociateTransaction, memo: []const u8) *TokenAssociateTransaction {
        _ = self.builder.setMemo(memo);
        return self;
    }

    pub fn setMaxTransactionFee(self: *TokenAssociateTransaction, fee: model.Hbar) *TokenAssociateTransaction {
        _ = self.builder.setMaxTransactionFee(fee);
        return self;
    }

    pub fn freeze(self: *TokenAssociateTransaction) !void {
        const account = self.account_id orelse return error.AccountIdRequired;
        if (self.token_ids.items.len == 0) return error.NoTokensSpecified;
        self.builder.freeze();
        const body = try encodeTokenAssociateBody(self.allocator, &self.builder, account, self.token_ids.items);
        errdefer self.allocator.free(body);
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenAssociateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: *TokenAssociateTransaction) ![]u8 {
        return try self.builder.toBytes();
    }

    pub fn execute(self: *TokenAssociateTransaction, client: anytype) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    pub fn executeAsync(self: *TokenAssociateTransaction, client: anytype) !model.TransactionResponse {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes();
        defer self.allocator.free(tx_bytes);
        return try client.consensus_client.submitTransaction(tx_bytes);
    }
};

pub const TokenDissociateTransaction = struct {
    allocator: std.mem.Allocator,
    builder: TransactionBuilder,
    account_id: ?model.AccountId = null,
    token_ids: std.ArrayList(model.TokenId),

    pub fn init(allocator: std.mem.Allocator) TokenDissociateTransaction {
        return .{
            .allocator = allocator,
            .builder = TransactionBuilder.init(allocator),
            .token_ids = std.ArrayList(model.TokenId).empty,
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

    pub fn setTransactionId(self: *TokenDissociateTransaction, tx_id: model.TransactionId) *TokenDissociateTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn setNodeAccountId(self: *TokenDissociateTransaction, account_id: model.AccountId) *TokenDissociateTransaction {
        _ = self.builder.setNodeAccountId(account_id);
        return self;
    }

    pub fn setValidDuration(self: *TokenDissociateTransaction, seconds: u32) *TokenDissociateTransaction {
        _ = self.builder.setValidDuration(seconds);
        return self;
    }

    pub fn setMemo(self: *TokenDissociateTransaction, memo: []const u8) *TokenDissociateTransaction {
        _ = self.builder.setMemo(memo);
        return self;
    }

    pub fn setMaxTransactionFee(self: *TokenDissociateTransaction, fee: model.Hbar) *TokenDissociateTransaction {
        _ = self.builder.setMaxTransactionFee(fee);
        return self;
    }

    pub fn freeze(self: *TokenDissociateTransaction) !void {
        const account = self.account_id orelse return error.AccountIdRequired;
        if (self.token_ids.items.len == 0) return error.NoTokensSpecified;
        self.builder.freeze();
        const body = try encodeTokenDissociateBody(self.allocator, &self.builder, account, self.token_ids.items);
        errdefer self.allocator.free(body);
        try self.builder.setBody(body);
    }

    pub fn sign(self: *TokenDissociateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: *TokenDissociateTransaction) ![]u8 {
        return try self.builder.toBytes();
    }

    pub fn execute(self: *TokenDissociateTransaction, client: anytype) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes();
        defer self.allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    pub fn executeAsync(self: *TokenDissociateTransaction, client: anytype) !model.TransactionResponse {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes();
        defer self.allocator.free(tx_bytes);
        return try client.consensus_client.submitTransaction(tx_bytes);
    }
};

pub const ContractCreateTransaction = struct {
    builder: TransactionBuilder = .{},
    bytecode: []const u8 = "",
    admin_key: ?crypto.PublicKey = null,
    gas: u64 = 0,
    initial_balance: model.Hbar = model.Hbar.ZERO,
    auto_renew_period: ?i64 = null,
    auto_renew_account_id: ?model.AccountId = null,
    memo: []const u8 = "",
    max_automatic_token_associations: ?u32 = null,
    constructor_parameters: ?model.ContractFunctionParameters = null,
    decline_staking_reward: bool = false,
    staked_account_id: ?model.AccountId = null,
    staked_node_id: ?u64 = null,

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

    pub fn setInitialBalance(self: *ContractCreateTransaction, balance: model.Hbar) *ContractCreateTransaction {
        self.initial_balance = balance;
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

    pub fn setMemo(self: *ContractCreateTransaction, memo: []const u8) *ContractCreateTransaction {
        self.memo = memo;
        return self;
    }

    pub fn setMaxAutomaticTokenAssociations(self: *ContractCreateTransaction, max: u32) *ContractCreateTransaction {
        self.max_automatic_token_associations = max;
        return self;
    }

    pub fn setConstructorParameters(self: *ContractCreateTransaction, params: model.ContractFunctionParameters) *ContractCreateTransaction {
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

    pub fn setStakedNodeId(self: *ContractCreateTransaction, node_id: u64) *ContractCreateTransaction {
        self.staked_node_id = node_id;
        return self;
    }

    pub fn setTransactionId(self: *ContractCreateTransaction, tx_id: model.TransactionId) *ContractCreateTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn freeze(self: *ContractCreateTransaction) !void {
        try self.builder.freeze();
    }

    pub fn sign(self: *ContractCreateTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: ContractCreateTransaction, allocator: std.mem.Allocator) ![]u8 {
        return self.builder.toBytes(allocator);
    }

    pub fn execute(self: *ContractCreateTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    pub fn executeAsync(self: *ContractCreateTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionResponse {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        return try client.consensus_client.submitTransaction(tx_bytes);
    }
};

pub const ContractExecuteTransaction = struct {
    builder: TransactionBuilder = .{},
    contract_id: ?model.ContractId = null,
    gas: u64 = 0,
    payable_amount: model.Hbar = model.Hbar.ZERO,
    function_parameters: ?model.ContractFunctionParameters = null,

    pub fn setContractId(self: *ContractExecuteTransaction, contract_id: model.ContractId) *ContractExecuteTransaction {
        self.contract_id = contract_id;
        return self;
    }

    pub fn setGas(self: *ContractExecuteTransaction, gas: u64) *ContractExecuteTransaction {
        self.gas = gas;
        return self;
    }

    pub fn setPayableAmount(self: *ContractExecuteTransaction, amount: model.Hbar) *ContractExecuteTransaction {
        self.payable_amount = amount;
        return self;
    }

    pub fn setFunctionParameters(self: *ContractExecuteTransaction, params: model.ContractFunctionParameters) *ContractExecuteTransaction {
        self.function_parameters = params;
        return self;
    }

    pub fn setTransactionId(self: *ContractExecuteTransaction, tx_id: model.TransactionId) *ContractExecuteTransaction {
        _ = self.builder.setTransactionId(tx_id);
        return self;
    }

    pub fn freeze(self: *ContractExecuteTransaction) !void {
        try self.builder.freeze();
    }

    pub fn sign(self: *ContractExecuteTransaction, private_key: crypto.PrivateKey) !void {
        try self.builder.sign(private_key);
    }

    pub fn toBytes(self: ContractExecuteTransaction, allocator: std.mem.Allocator) ![]u8 {
        return self.builder.toBytes(allocator);
    }

    pub fn execute(self: *ContractExecuteTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionReceipt {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        const response = try client.consensus_client.submitTransaction(tx_bytes);
        const tx_id = response.transaction_id orelse return error.NoTransactionId;
        return try client.consensus_client.getTransactionReceipt(tx_id);
    }

    pub fn executeAsync(self: *ContractExecuteTransaction, client: anytype, allocator: std.mem.Allocator) !model.TransactionResponse {
        if (!self.builder.is_frozen) {
            try self.freeze();
        }
        const tx_bytes = try self.toBytes(allocator);
        defer allocator.free(tx_bytes);
        return try client.consensus_client.submitTransaction(tx_bytes);
    }
};
