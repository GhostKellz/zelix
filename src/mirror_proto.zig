//! Minimal protobuf helpers for Hedera mirror gRPC messages.

const std = @import("std");
const model = @import("model.zig");
const proto = @import("ser/proto.zig");
const crypto = @import("crypto.zig");

const math = std.math;
const mem = std.mem;

pub const ConsensusTopicResponse = struct {
    consensus_timestamp: model.Timestamp,
    message: []u8,
    running_hash: []u8,
    sequence_number: u64,
    running_hash_version: u64,

    pub fn deinit(self: *ConsensusTopicResponse, allocator: std.mem.Allocator) void {
        if (self.message.len > 0) allocator.free(self.message);
        if (self.running_hash.len > 0) allocator.free(self.running_hash);
        self.* = undefined;
    }
};

pub fn encodeAccountBalanceQuery(
    allocator: std.mem.Allocator,
    account_id: model.AccountId,
) ![]u8 {
    const header_bytes = try encodeQueryHeader(allocator);
    defer allocator.free(header_bytes);

    const account_bytes = try encodeAccountId(allocator, account_id);
    defer allocator.free(account_bytes);

    var balance_writer = proto.Writer.init(allocator);
    defer balance_writer.deinit();
    try balance_writer.writeFieldBytes(1, header_bytes);
    try balance_writer.writeFieldBytes(2, account_bytes);
    const balance_query = try balance_writer.toOwnedSlice();
    defer allocator.free(balance_query);

    return try encodeQueryWrapper(allocator, 7, balance_query);
}

pub fn encodeAccountInfoQuery(
    allocator: std.mem.Allocator,
    account_id: model.AccountId,
) ![]u8 {
    const header_bytes = try encodeQueryHeader(allocator);
    defer allocator.free(header_bytes);

    const account_bytes = try encodeAccountId(allocator, account_id);
    defer allocator.free(account_bytes);

    var info_writer = proto.Writer.init(allocator);
    defer info_writer.deinit();
    try info_writer.writeFieldBytes(1, header_bytes);
    try info_writer.writeFieldBytes(2, account_bytes);
    const info_query = try info_writer.toOwnedSlice();
    defer allocator.free(info_query);

    return try encodeQueryWrapper(allocator, 9, info_query);
}

pub fn encodeTransactionGetReceiptQuery(
    allocator: std.mem.Allocator,
    transaction_id: model.TransactionId,
    include_duplicates: bool,
    include_child_receipts: bool,
) ![]u8 {
    const header_bytes = try encodeQueryHeader(allocator);
    defer allocator.free(header_bytes);

    const tx_bytes = try encodeTransactionId(allocator, transaction_id);
    defer allocator.free(tx_bytes);

    var query_writer = proto.Writer.init(allocator);
    defer query_writer.deinit();
    try query_writer.writeFieldBytes(1, header_bytes);
    try query_writer.writeFieldBytes(2, tx_bytes);
    if (include_duplicates) try query_writer.writeFieldVarint(3, 1);
    if (include_child_receipts) try query_writer.writeFieldVarint(4, 1);
    const query_bytes = try query_writer.toOwnedSlice();
    defer allocator.free(query_bytes);

    return try encodeQueryWrapper(allocator, 14, query_bytes);
}

pub fn encodeTransactionGetRecordQuery(
    allocator: std.mem.Allocator,
    transaction_id: model.TransactionId,
    include_duplicates: bool,
    include_child_records: bool,
) ![]u8 {
    const header_bytes = try encodeQueryHeader(allocator);
    defer allocator.free(header_bytes);

    const tx_bytes = try encodeTransactionId(allocator, transaction_id);
    defer allocator.free(tx_bytes);

    var query_writer = proto.Writer.init(allocator);
    defer query_writer.deinit();
    try query_writer.writeFieldBytes(1, header_bytes);
    try query_writer.writeFieldBytes(2, tx_bytes);
    if (include_duplicates) try query_writer.writeFieldVarint(3, 1);
    if (include_child_records) try query_writer.writeFieldVarint(4, 1);
    const query_bytes = try query_writer.toOwnedSlice();
    defer allocator.free(query_bytes);

    return try encodeQueryWrapper(allocator, 15, query_bytes);
}

pub fn encodeAccountDetailsQuery(
    allocator: std.mem.Allocator,
    account_id: model.AccountId,
) ![]u8 {
    const header_bytes = try encodeQueryHeader(allocator);
    defer allocator.free(header_bytes);

    const account_bytes = try encodeAccountId(allocator, account_id);
    defer allocator.free(account_bytes);

    var query_writer = proto.Writer.init(allocator);
    defer query_writer.deinit();
    try query_writer.writeFieldBytes(1, header_bytes);
    try query_writer.writeFieldBytes(2, account_bytes);
    const details_query = try query_writer.toOwnedSlice();
    defer allocator.free(details_query);

    return try encodeQueryWrapper(allocator, 58, details_query);
}

pub fn encodeTokenInfoQuery(
    allocator: std.mem.Allocator,
    token_id: model.TokenId,
) ![]u8 {
    const header_bytes = try encodeQueryHeader(allocator);
    defer allocator.free(header_bytes);

    const token_bytes = try encodeTokenId(allocator, token_id);
    defer allocator.free(token_bytes);

    var token_writer = proto.Writer.init(allocator);
    defer token_writer.deinit();
    try token_writer.writeFieldBytes(1, header_bytes);
    try token_writer.writeFieldBytes(2, token_bytes);
    const token_query = try token_writer.toOwnedSlice();
    defer allocator.free(token_query);

    return try encodeQueryWrapper(allocator, 52, token_query);
}

pub fn decodeAccountBalanceResponse(payload: []const u8) !model.Hbar {
    const message = try extractResponseMessage(payload, 7);
    return try decodeAccountBalanceMessage(message);
}

pub const AccountInfoDecodeResult = struct {
    info: model.AccountInfo,
    balance: model.Hbar,
};

pub fn decodeAccountInfoResponse(
    allocator: std.mem.Allocator,
    payload: []const u8,
    expected_account_id: model.AccountId,
) !AccountInfoDecodeResult {
    const wrapper = try extractResponseMessage(payload, 9);
    const account_bytes = try extractResponseMessage(wrapper, 2);
    return try decodeAccountInfoMessage(allocator, account_bytes, expected_account_id);
}

pub fn decodeAccountDetailsAllowances(
    allocator: std.mem.Allocator,
    payload: []const u8,
    expected_account_id: model.AccountId,
) !model.AccountAllowances {
    const wrapper = try extractResponseMessage(payload, 158);
    const details_bytes = try extractResponseMessage(wrapper, 2);
    return try decodeAccountDetailsMessage(allocator, details_bytes, expected_account_id);
}

pub fn decodeTransactionReceiptResponse(
    payload: []const u8,
    expected_transaction_id: model.TransactionId,
) !model.TransactionReceipt {
    const wrapper = try extractResponseMessage(payload, 14);
    const receipt_bytes = try extractResponseMessage(wrapper, 2);
    return decodeTransactionReceiptMessage(receipt_bytes, expected_transaction_id);
}

pub fn decodeTransactionRecordResponse(
    allocator: std.mem.Allocator,
    payload: []const u8,
    expected_transaction_id: model.TransactionId,
) !model.TransactionRecord {
    const wrapper = try extractResponseMessage(payload, 15);
    const record_bytes = try extractResponseMessage(wrapper, 3);

    var duplicate_values = std.ArrayList([]const u8).init(allocator);
    defer duplicate_values.deinit();
    var child_values = std.ArrayList([]const u8).init(allocator);
    defer child_values.deinit();

    var resp_reader = ProtoReader{ .data = wrapper, .index = 0 };
    while (try resp_reader.next()) |field| {
        switch (field.number) {
            4 => try duplicate_values.append(field.value),
            5 => try child_values.append(field.value),
            else => {},
        }
    }

    var record = try decodeTransactionRecordMessage(allocator, record_bytes, expected_transaction_id);

    if (duplicate_values.items.len > 0) {
        var duplicates = try allocator.alloc(model.TransactionRecord, duplicate_values.items.len);
        var dup_index: usize = 0;
        errdefer {
            for (duplicates[0..dup_index]) |*dup| dup.deinit(allocator);
            if (duplicates.len > 0) allocator.free(duplicates);
        }
        for (duplicate_values.items) |dup_bytes| {
            const dup_record = try decodeTransactionRecordMessage(allocator, dup_bytes, expected_transaction_id);
            duplicates[dup_index] = dup_record;
            dup_index += 1;
        }
        record.duplicates = duplicates;
    }

    if (child_values.items.len > 0) {
        var children = try allocator.alloc(model.TransactionRecord, child_values.items.len);
        var child_index: usize = 0;
        errdefer {
            for (children[0..child_index]) |*child| child.deinit(allocator);
            if (children.len > 0) allocator.free(children);
        }
        for (child_values.items) |child_bytes| {
            const child_record = try decodeTransactionRecordMessage(allocator, child_bytes, expected_transaction_id);
            children[child_index] = child_record;
            child_index += 1;
        }
        record.children = children;
    }

    return record;
}

pub fn decodeTokenInfoResponse(
    allocator: std.mem.Allocator,
    payload: []const u8,
    expected_token_id: model.TokenId,
) !model.TokenInfo {
    const wrapper = try extractResponseMessage(payload, 152);
    const token_bytes = try extractResponseMessage(wrapper, 2);
    return try decodeTokenInfoMessage(allocator, token_bytes, expected_token_id);
}

pub fn encodeConsensusTopicQuery(
    allocator: std.mem.Allocator,
    topic_id: model.TopicId,
    consensus_start: ?model.Timestamp,
    consensus_end: ?model.Timestamp,
    limit: ?u64,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const topic_bytes = try encodeTopicId(allocator, topic_id);
    defer allocator.free(topic_bytes);
    try writer.writeFieldBytes(1, topic_bytes);

    if (consensus_start) |ts| {
        const ts_bytes = try encodeTimestamp(allocator, ts);
        defer allocator.free(ts_bytes);
        try writer.writeFieldBytes(2, ts_bytes);
    }

    if (consensus_end) |ts| {
        const ts_bytes = try encodeTimestamp(allocator, ts);
        defer allocator.free(ts_bytes);
        try writer.writeFieldBytes(3, ts_bytes);
    }

    if (limit) |value| {
        try writer.writeFieldUint64(4, value);
    }

    return try writer.toOwnedSlice();
}

pub fn decodeConsensusTopicResponse(allocator: std.mem.Allocator, payload: []const u8) !ConsensusTopicResponse {
    var result = ConsensusTopicResponse{
        .consensus_timestamp = .{ .seconds = 0, .nanos = 0 },
        .message = &[_]u8{},
        .running_hash = &[_]u8{},
        .sequence_number = 0,
        .running_hash_version = 0,
    };

    var reader = ProtoReader{ .data = payload, .index = 0 };
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => {
                const ts = try decodeTimestamp(field.value);
                result.consensus_timestamp = ts;
            },
            2 => {
                if (result.message.len > 0) allocator.free(result.message);
                result.message = try allocator.dupe(u8, field.value);
            },
            3 => {
                if (result.running_hash.len > 0) allocator.free(result.running_hash);
                result.running_hash = try allocator.dupe(u8, field.value);
            },
            4 => result.sequence_number = field.varint,
            5 => result.running_hash_version = field.varint,
            else => {},
        }
    }

    return result;
}

fn encodeTopicId(allocator: std.mem.Allocator, id: model.TopicId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldUint64(1, id.shard);
    try writer.writeFieldUint64(2, id.realm);
    try writer.writeFieldUint64(3, id.num);
    return try writer.toOwnedSlice();
}

fn encodeAccountId(allocator: std.mem.Allocator, id: model.AccountId) ![]u8 {
    return encodeEntityId(allocator, id);
}

fn encodeTokenId(allocator: std.mem.Allocator, id: model.TokenId) ![]u8 {
    return encodeEntityId(allocator, id);
}

fn encodeEntityId(allocator: std.mem.Allocator, id: model.EntityId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldUint64(1, id.shard);
    try writer.writeFieldUint64(2, id.realm);
    try writer.writeFieldUint64(3, id.num);
    return try writer.toOwnedSlice();
}

fn encodeTransactionId(allocator: std.mem.Allocator, id: model.TransactionId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const timestamp_bytes = try encodeTimestamp(allocator, id.valid_start);
    defer allocator.free(timestamp_bytes);
    try writer.writeFieldBytes(1, timestamp_bytes);

    const account_bytes = try encodeAccountId(allocator, id.account_id);
    defer allocator.free(account_bytes);
    try writer.writeFieldBytes(2, account_bytes);

    if (id.scheduled) try writer.writeFieldVarint(3, 1);
    if (id.nonce) |nonce| {
        const widened: i64 = @intCast(nonce);
        try writer.writeFieldInt64(4, widened);
    }

    return try writer.toOwnedSlice();
}

fn encodeQueryHeader(allocator: std.mem.Allocator) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    // ResponseType ANSWER_ONLY (0) is default but explicit encode avoids ambiguity.
    try writer.writeFieldVarint(2, 0);
    return try writer.toOwnedSlice();
}

fn encodeQueryWrapper(allocator: std.mem.Allocator, field_number: u32, body: []const u8) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldBytes(field_number, body);
    return try writer.toOwnedSlice();
}

fn encodeTimestamp(allocator: std.mem.Allocator, ts: model.Timestamp) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldInt64(1, ts.seconds);
    try writer.writeFieldInt64(2, ts.nanos);
    return try writer.toOwnedSlice();
}

const DecodeError = error{
    MissingField,
    InvalidMessage,
    UnsupportedKeyType,
    ValueOverflow,
};

fn extractResponseMessage(payload: []const u8, field_number: u32) ![]const u8 {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    while (try reader.next()) |field| {
        if (field.number == field_number) {
            if (field.value.len == 0) return DecodeError.InvalidMessage;
            return field.value;
        }
    }
    return DecodeError.MissingField;
}

fn decodeAccountBalanceMessage(message: []const u8) !model.Hbar {
    var reader = ProtoReader{ .data = message, .index = 0 };
    var balance: ?u64 = null;
    while (try reader.next()) |field| {
        switch (field.number) {
            3 => balance = field.varint,
            else => {},
        }
    }
    const value = balance orelse return DecodeError.MissingField;
    if (value > math.maxInt(i64)) return DecodeError.ValueOverflow;
    return model.Hbar.fromTinybars(@as(i64, @intCast(value)));
}

fn decodeAccountInfoMessage(
    allocator: std.mem.Allocator,
    message: []const u8,
    expected_account_id: model.AccountId,
) !AccountInfoDecodeResult {
    var info = model.AccountInfo{
        .account_id = expected_account_id,
        .alias_key = null,
        .contract_account_id = null,
        .deleted = false,
        .expiry_timestamp = null,
        .key = null,
        .auto_renew_period = null,
        .memo = "",
        .owned_nfts = 0,
        .max_automatic_token_associations = 0,
        .receiver_sig_required = false,
        .ethereum_nonce = 0,
        .staking_info = null,
    };
    errdefer info.deinit(allocator);

    var balance_tinybars: ?i64 = null;

    var reader = ProtoReader{ .data = message, .index = 0 };
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => info.account_id = try decodeAccountId(field.value),
            2 => {
                if (info.contract_account_id) |existing| {
                    if (existing.len > 0) allocator.free(@constCast(existing));
                }
                info.contract_account_id = try dupOptionalString(allocator, field.value);
            },
            3 => info.deleted = field.varint != 0,
            7 => info.key = try decodeKey(field.value),
            8 => {
                if (field.varint > math.maxInt(i64)) return DecodeError.ValueOverflow;
                balance_tinybars = @as(i64, @intCast(field.varint));
            },
            11 => info.receiver_sig_required = field.varint != 0,
            12 => info.expiry_timestamp = try decodeTimestamp(field.value),
            13 => info.auto_renew_period = try decodeDuration(field.value),
            16 => {
                if (info.memo.len > 0) allocator.free(@constCast(info.memo));
                info.memo = try allocator.dupe(u8, field.value);
            },
            17 => {
                const signed: i64 = @bitCast(field.varint);
                if (signed >= 0) info.owned_nfts = @intCast(signed);
            },
            18 => {
                const signed: i64 = @bitCast(field.varint);
                if (signed >= 0 and signed <= math.maxInt(i32)) {
                    info.max_automatic_token_associations = @intCast(signed);
                }
            },
            19 => {
                if (info.alias_key) |existing| {
                    if (existing.len > 0) allocator.free(@constCast(existing));
                }
                if (field.value.len == 0) {
                    info.alias_key = null;
                } else {
                    info.alias_key = try allocator.dupe(u8, field.value);
                }
            },
            21 => info.ethereum_nonce = @bitCast(field.varint),
            22 => info.staking_info = try decodeStakingInfo(field.value),
            else => {},
        }
    }

    const balance_value = balance_tinybars orelse return DecodeError.MissingField;
    return AccountInfoDecodeResult{ .info = info, .balance = model.Hbar.fromTinybars(balance_value) };
}

fn decodeTokenInfoMessage(
    allocator: std.mem.Allocator,
    message: []const u8,
    expected_token_id: model.TokenId,
) !model.TokenInfo {
    var info = model.TokenInfo{
        .token_id = expected_token_id,
        .name = "",
        .symbol = "",
        .decimals = 0,
        .total_supply = 0,
        .treasury_account_id = model.EntityId.init(0, 0, 0),
        .admin_key = null,
        .kyc_key = null,
        .freeze_key = null,
        .wipe_key = null,
        .supply_key = null,
        .fee_schedule_key = null,
        .pause_key = null,
        .token_type = .fungible_common,
        .supply_type = .infinite,
        .max_supply = null,
        .freeze_default = false,
        .pause_status = false,
        .deleted = false,
        .expiry_timestamp = null,
        .auto_renew_period = null,
        .auto_renew_account_id = null,
        .memo = "",
        .custom_fees = &.{},
    };
    errdefer info.deinit(allocator);

    var reader = ProtoReader{ .data = message, .index = 0 };
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => info.token_id = try decodeTokenId(field.value),
            2 => {
                if (info.name.len > 0) allocator.free(@constCast(info.name));
                info.name = try allocator.dupe(u8, field.value);
            },
            3 => {
                if (info.symbol.len > 0) allocator.free(@constCast(info.symbol));
                info.symbol = try allocator.dupe(u8, field.value);
            },
            4 => info.decimals = @intCast(field.varint),
            5 => info.total_supply = field.varint,
            6 => info.treasury_account_id = try decodeAccountId(field.value),
            7 => info.admin_key = try decodeKey(field.value),
            8 => info.kyc_key = try decodeKey(field.value),
            9 => info.freeze_key = try decodeKey(field.value),
            10 => info.wipe_key = try decodeKey(field.value),
            11 => info.supply_key = try decodeKey(field.value),
            12 => info.freeze_default = field.varint != 0,
            13 => {}, // default KYC status unused
            14 => info.deleted = field.varint != 0,
            15 => info.auto_renew_account_id = try decodeOptionalAccountId(field.value),
            16 => info.auto_renew_period = try decodeDuration(field.value),
            17 => info.expiry_timestamp = try decodeTimestamp(field.value),
            18 => {
                if (info.memo.len > 0) allocator.free(@constCast(info.memo));
                info.memo = try allocator.dupe(u8, field.value);
            },
            19 => info.token_type = try mapTokenType(field.varint),
            20 => info.supply_type = try mapSupplyType(field.varint),
            21 => {
                const signed: i64 = @bitCast(field.varint);
                if (signed >= 0) info.max_supply = @intCast(signed) else info.max_supply = null;
            },
            22 => info.fee_schedule_key = try decodeKey(field.value),
            24 => info.pause_key = try decodeKey(field.value),
            25 => info.pause_status = switch (field.varint) {
                1 => true,
                else => false,
            },
            else => {},
        }
    }

    if (info.name.len == 0 or info.symbol.len == 0) return DecodeError.MissingField;
    return info;
}

fn decodeAccountDetailsMessage(
    allocator: std.mem.Allocator,
    message: []const u8,
    owner_account_id: model.AccountId,
) !model.AccountAllowances {
    var crypto_list = std.ArrayListUnmanaged(model.CryptoAllowance){};
    errdefer crypto_list.deinit(allocator);
    var token_list = std.ArrayListUnmanaged(model.TokenAllowance){};
    errdefer token_list.deinit(allocator);
    var nft_list = std.ArrayListUnmanaged(model.TokenNftAllowance){};
    errdefer nft_list.deinit(allocator);

    var reader = ProtoReader{ .data = message, .index = 0 };
    while (try reader.next()) |field| {
        switch (field.number) {
            17 => {
                const allowance = try decodeGrantedCryptoAllowance(field.value, owner_account_id);
                try crypto_list.append(allocator, allowance);
            },
            18 => {
                const allowance = try decodeGrantedNftAllowance(field.value, owner_account_id);
                try nft_list.append(allocator, allowance);
            },
            19 => {
                const allowance = try decodeGrantedTokenAllowance(field.value, owner_account_id);
                try token_list.append(allocator, allowance);
            },
            else => {},
        }
    }

    var allowances = model.AccountAllowances.empty();
    errdefer allowances.deinit(allocator);

    allowances.crypto = if (crypto_list.items.len == 0)
        @constCast((&[_]model.CryptoAllowance{})[0..])
    else
        try crypto_list.toOwnedSlice(allocator);

    allowances.token = if (token_list.items.len == 0)
        @constCast((&[_]model.TokenAllowance{})[0..])
    else
        try token_list.toOwnedSlice(allocator);

    allowances.nft = if (nft_list.items.len == 0)
        @constCast((&[_]model.TokenNftAllowance{})[0..])
    else
        try nft_list.toOwnedSlice(allocator);

    return allowances;
}

fn decodeTransactionReceiptMessage(bytes: []const u8, expected_transaction_id: model.TransactionId) !model.TransactionReceipt {
    var status_code: u64 = 21; // UNKNOWN
    var reader = ProtoReader{ .data = bytes, .index = 0 };
    while (try reader.next()) |field| {
        if (field.number == 1) {
            status_code = field.varint;
            break;
        }
    }

    const status = mapResponseCode(status_code);
    return model.TransactionReceipt{ .status = status, .transaction_id = expected_transaction_id };
}

fn decodeTransactionRecordMessage(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    expected_transaction_id: model.TransactionId,
) !model.TransactionRecord {
    var record = model.TransactionRecord{
        .transaction_hash = "",
        .consensus_timestamp = .{ .seconds = 0, .nanos = 0 },
        .transaction_id = expected_transaction_id,
        .memo = "",
        .transaction_fee = model.Hbar.ZERO,
        .transfer_list = @constCast((&[_]model.Transfer{})[0..]),
        .duplicates = @constCast((&[_]model.TransactionRecord{})[0..]),
        .children = @constCast((&[_]model.TransactionRecord{})[0..]),
    };
    errdefer record.deinit(allocator);

    var reader = ProtoReader{ .data = bytes, .index = 0 };
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => {}, // receipt ignored for now
            2 => {
                if (record.transaction_hash.len > 0) allocator.free(@constCast(record.transaction_hash));
                record.transaction_hash = try allocator.dupe(u8, field.value);
            },
            3 => record.consensus_timestamp = try decodeTimestamp(field.value),
            4 => record.transaction_id = try decodeTransactionId(field.value),
            5 => {
                if (record.memo.len > 0) allocator.free(@constCast(record.memo));
                record.memo = try allocator.dupe(u8, field.value);
            },
            6 => {
                if (field.varint > math.maxInt(i64)) return DecodeError.ValueOverflow;
                record.transaction_fee = model.Hbar.fromTinybars(@as(i64, @intCast(field.varint)));
            },
            10 => {
                if (record.transfer_list.len > 0) allocator.free(record.transfer_list);
                record.transfer_list = try decodeTransferList(allocator, field.value);
            },
            else => {},
        }
    }

    return record;
}

fn decodeGrantedCryptoAllowance(bytes: []const u8, owner_account_id: model.AccountId) !model.CryptoAllowance {
    var reader = ProtoReader{ .data = bytes, .index = 0 };
    var spender: ?model.AccountId = null;
    var amount: ?i64 = null;
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => spender = try decodeAccountId(field.value),
            2 => amount = @as(i64, @bitCast(field.varint)),
            else => {},
        }
    }

    const spender_id = spender orelse return DecodeError.MissingField;
    const amount_value = amount orelse return DecodeError.MissingField;
    if (amount_value < 0) return DecodeError.InvalidMessage;

    return model.CryptoAllowance{
        .owner_account_id = owner_account_id,
        .spender_account_id = spender_id,
        .amount = model.Hbar.fromTinybars(amount_value),
        .timestamp = null,
    };
}

fn decodeGrantedTokenAllowance(bytes: []const u8, owner_account_id: model.AccountId) !model.TokenAllowance {
    var reader = ProtoReader{ .data = bytes, .index = 0 };
    var token: ?model.TokenId = null;
    var spender: ?model.AccountId = null;
    var amount: ?i64 = null;
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => token = try decodeTokenId(field.value),
            2 => spender = try decodeAccountId(field.value),
            3 => amount = @as(i64, @bitCast(field.varint)),
            else => {},
        }
    }

    const token_id = token orelse return DecodeError.MissingField;
    const spender_id = spender orelse return DecodeError.MissingField;
    const amount_value = amount orelse return DecodeError.MissingField;
    if (amount_value < 0) return DecodeError.InvalidMessage;

    return model.TokenAllowance{
        .owner_account_id = owner_account_id,
        .spender_account_id = spender_id,
        .token_id = token_id,
        .amount = @as(u64, @intCast(amount_value)),
        .timestamp = null,
    };
}

fn decodeGrantedNftAllowance(bytes: []const u8, owner_account_id: model.AccountId) !model.TokenNftAllowance {
    var reader = ProtoReader{ .data = bytes, .index = 0 };
    var token: ?model.TokenId = null;
    var spender: ?model.AccountId = null;
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => token = try decodeTokenId(field.value),
            2 => spender = try decodeAccountId(field.value),
            else => {},
        }
    }

    const token_id = token orelse return DecodeError.MissingField;
    const spender_id = spender orelse return DecodeError.MissingField;

    return model.TokenNftAllowance{
        .owner_account_id = owner_account_id,
        .spender_account_id = spender_id,
        .token_id = token_id,
        .serial_numbers = @constCast((&[_]u64{})[0..]),
        .approved_for_all = true,
        .timestamp = null,
    };
}

fn decodeTransactionId(bytes: []const u8) !model.TransactionId {
    var tx_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 0),
        .valid_start = .{ .seconds = 0, .nanos = 0 },
        .nonce = null,
        .scheduled = false,
    };

    var reader = ProtoReader{ .data = bytes, .index = 0 };
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => tx_id.valid_start = try decodeTimestamp(field.value),
            2 => tx_id.account_id = try decodeAccountId(field.value),
            3 => tx_id.scheduled = field.varint != 0,
            4 => {
                const signed64: i64 = @bitCast(field.varint);
                if (signed64 < math.minInt(i32) or signed64 > math.maxInt(i32)) return DecodeError.ValueOverflow;
                tx_id.nonce = @intCast(signed64);
            },
            else => {},
        }
    }

    return tx_id;
}

fn decodeTransferList(allocator: std.mem.Allocator, bytes: []const u8) ![]model.Transfer {
    var list = std.ArrayList(model.Transfer).init(allocator);
    errdefer list.deinit();

    var reader = ProtoReader{ .data = bytes, .index = 0 };
    while (try reader.next()) |field| {
        if (field.number == 1) {
            const transfer = try decodeAccountAmount(field.value);
            try list.append(transfer);
        }
    }

    return try list.toOwnedSlice();
}

fn decodeAccountAmount(bytes: []const u8) !model.Transfer {
    var account = model.AccountId.init(0, 0, 0);
    var amount: ?i64 = null;
    var approval = false;
    var has_account = false;

    var reader = ProtoReader{ .data = bytes, .index = 0 };
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => {
                account = try decodeAccountId(field.value);
                has_account = true;
            },
            2 => amount = decodeSint64(field.varint),
            3 => approval = field.varint != 0,
            else => {},
        }
    }

    if (!has_account) return DecodeError.MissingField;
    const amount_value = amount orelse return DecodeError.MissingField;
    return model.Transfer{
        .account_id = account,
        .amount = model.Hbar.fromTinybars(amount_value),
        .is_approval = approval,
    };
}

fn decodeSint64(value: u64) i64 {
    const shifted: i64 = @intCast(value >> 1);
    const neg_mask: i64 = @intCast(value & 1);
    return shifted ^ -neg_mask;
}

fn mapResponseCode(code: u64) model.TransactionStatus {
    return switch (code) {
        0, 22, 220, 280 => .success,
        21 => .unknown,
        else => .failed,
    };
}

const ProtoReader = struct {
    data: []const u8,
    index: usize,

    const Field = struct {
        number: u32,
        wire: u3,
        varint: u64 = 0,
        value: []const u8 = &[_]u8{},
    };

    fn next(self: *ProtoReader) !?Field {
        if (self.index >= self.data.len) return null;
        const key = try readVarint(self.data, &self.index);
        const number: u32 = @intCast(key >> 3);
        const wire: u3 = @intCast(key & 0x7);
        var field = Field{ .number = number, .wire = wire };
        switch (wire) {
            0 => field.varint = try readVarint(self.data, &self.index),
            2 => {
                const len = try readVarint(self.data, &self.index);
                const start = self.index;
                const end = start + len;
                if (end > self.data.len) return error.UnexpectedEndOfStream;
                field.value = self.data[start..end];
                self.index = end;
            },
            else => return error.UnsupportedWireType,
        }
        return field;
    }
};

fn decodeTimestamp(bytes: []const u8) !model.Timestamp {
    var reader = ProtoReader{ .data = bytes, .index = 0 };
    var seconds: i64 = 0;
    var nanos: i64 = 0;
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => seconds = @intCast(field.varint),
            2 => nanos = @intCast(field.varint),
            else => {},
        }
    }
    return .{ .seconds = seconds, .nanos = nanos };
}

fn decodeDuration(bytes: []const u8) !?i64 {
    var reader = ProtoReader{ .data = bytes, .index = 0 };
    var seconds: ?i64 = null;
    while (try reader.next()) |field| {
        if (field.number == 1) seconds = @intCast(@as(i64, @bitCast(field.varint)));
    }
    return seconds;
}

fn decodeAccountId(bytes: []const u8) !model.AccountId {
    return decodeEntityId(bytes);
}

fn decodeTokenId(bytes: []const u8) !model.TokenId {
    return decodeEntityId(bytes);
}

fn decodeOptionalAccountId(bytes: []const u8) !?model.AccountId {
    if (bytes.len == 0) return null;
    return try decodeAccountId(bytes);
}

fn decodeEntityId(bytes: []const u8) !model.EntityId {
    var reader = ProtoReader{ .data = bytes, .index = 0 };
    var shard: u64 = 0;
    var realm: u64 = 0;
    var num: u64 = 0;
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => shard = field.varint,
            2 => realm = field.varint,
            3 => num = field.varint,
            else => {},
        }
    }
    return model.EntityId.init(shard, realm, num);
}

fn decodeKey(bytes: []const u8) !?crypto.PublicKey {
    var reader = ProtoReader{ .data = bytes, .index = 0 };
    while (try reader.next()) |field| {
        switch (field.number) {
            2 => {
                if (field.value.len != 32) return DecodeError.UnsupportedKeyType;
                var raw: [32]u8 = undefined;
                mem.copy(u8, raw[0..], field.value);
                return crypto.PublicKey.fromBytes(raw) catch return DecodeError.UnsupportedKeyType;
            },
            else => {},
        }
    }
    return null;
}

fn decodeStakingInfo(bytes: []const u8) !?model.StakingInfo {
    if (bytes.len == 0) return null;
    var info = model.StakingInfo{};
    var reader = ProtoReader{ .data = bytes, .index = 0 };
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => info.decline_staking_reward = field.varint != 0,
            2 => info.stake_period_start = try decodeTimestamp(field.value),
            3 => info.pending_reward = @intCast(field.varint),
            4 => info.staked_to_me = @intCast(field.varint),
            5 => info.staked_account_id = try decodeAccountId(field.value),
            6 => {
                const node_id = @as(i64, @bitCast(field.varint));
                if (node_id >= 0) info.staked_node_id = @intCast(node_id);
            },
            else => {},
        }
    }
    return info;
}

fn mapTokenType(raw: u64) !model.TokenType {
    return switch (raw) {
        0 => .fungible_common,
        1 => .non_fungible_unique,
        else => DecodeError.InvalidMessage,
    };
}

fn mapSupplyType(raw: u64) !model.TokenSupplyType {
    return switch (raw) {
        0 => .infinite,
        1 => .finite,
        else => DecodeError.InvalidMessage,
    };
}

fn dupOptionalString(allocator: std.mem.Allocator, value: []const u8) !?[]const u8 {
    if (value.len == 0) return "";
    return try allocator.dupe(u8, value);
}

test "encode account balance query" {
    const allocator = std.testing.allocator;
    const account_id = model.AccountId.init(0, 0, 123);
    const bytes = try encodeAccountBalanceQuery(allocator, account_id);
    defer allocator.free(bytes);

    var reader = ProtoReader{ .data = bytes, .index = 0 };
    const outer_opt = try reader.next();
    try std.testing.expect(outer_opt != null);
    const outer = outer_opt.?;
    try std.testing.expectEqual(@as(u32, 7), outer.number);

    var query_reader = ProtoReader{ .data = outer.value, .index = 0 };
    var header_checked = false;
    var parsed_id: ?model.AccountId = null;
    while (try query_reader.next()) |field| {
        switch (field.number) {
            1 => {
                var header_reader = ProtoReader{ .data = field.value, .index = 0 };
                while (try header_reader.next()) |header_field| {
                    if (header_field.number == 2) {
                        try std.testing.expectEqual(@as(u64, 0), header_field.varint);
                        header_checked = true;
                    }
                }
            },
            2 => parsed_id = try decodeAccountId(field.value),
            else => {},
        }
    }
    try std.testing.expect(header_checked);
    try std.testing.expect(parsed_id != null);
    const id = parsed_id.?;
    try std.testing.expectEqual(account_id.shard, id.shard);
    try std.testing.expectEqual(account_id.realm, id.realm);
    try std.testing.expectEqual(account_id.num, id.num);
}

test "decode account balance response" {
    const allocator = std.testing.allocator;

    var balance_writer = proto.Writer.init(allocator);
    defer balance_writer.deinit();
    try balance_writer.writeFieldVarint(3, 5000);
    const balance_bytes = try balance_writer.toOwnedSlice();
    defer allocator.free(balance_bytes);

    var response_writer = proto.Writer.init(allocator);
    defer response_writer.deinit();
    try response_writer.writeFieldBytes(7, balance_bytes);
    const payload = try response_writer.toOwnedSlice();
    defer allocator.free(payload);

    const balance = try decodeAccountBalanceResponse(payload);
    try std.testing.expectEqual(@as(i64, 5000), balance.toTinybars());
}

test "decode account info response" {
    const allocator = std.testing.allocator;
    const account_id = model.AccountId.init(0, 0, 1001);

    const account_id_bytes = try encodeAccountId(allocator, account_id);
    defer allocator.free(account_id_bytes);

    var key_writer = proto.Writer.init(allocator);
    defer key_writer.deinit();
    var key_bytes: [32]u8 = [_]u8{0x11} ** 32;
    try key_writer.writeFieldBytes(2, &key_bytes);
    const key_message = try key_writer.toOwnedSlice();
    defer allocator.free(key_message);

    var timestamp_writer = proto.Writer.init(allocator);
    defer timestamp_writer.deinit();
    try timestamp_writer.writeFieldInt64(1, 1_700_000_000);
    try timestamp_writer.writeFieldInt64(2, 42);
    const expiry_bytes = try timestamp_writer.toOwnedSlice();
    defer allocator.free(expiry_bytes);

    var duration_writer = proto.Writer.init(allocator);
    defer duration_writer.deinit();
    try duration_writer.writeFieldInt64(1, 3600);
    const duration_bytes = try duration_writer.toOwnedSlice();
    defer allocator.free(duration_bytes);

    var account_info_writer = proto.Writer.init(allocator);
    defer account_info_writer.deinit();
    try account_info_writer.writeFieldBytes(1, account_id_bytes);
    try account_info_writer.writeFieldVarint(3, 1);
    try account_info_writer.writeFieldBytes(7, key_message);
    try account_info_writer.writeFieldVarint(8, 7500);
    try account_info_writer.writeFieldVarint(11, 1);
    try account_info_writer.writeFieldBytes(12, expiry_bytes);
    try account_info_writer.writeFieldBytes(13, duration_bytes);
    try account_info_writer.writeFieldBytes(16, "demo");
    try account_info_writer.writeFieldVarint(17, 4);
    try account_info_writer.writeFieldVarint(18, 3);
    const alias_bytes: [3]u8 = .{ 0xAA, 0xBB, 0xCC };
    try account_info_writer.writeFieldBytes(19, &alias_bytes);
    try account_info_writer.writeFieldInt64(21, 42);

    var staking_writer = proto.Writer.init(allocator);
    defer staking_writer.deinit();
    try staking_writer.writeFieldVarint(1, 1);
    try staking_writer.writeFieldVarint(3, 100);
    const staking_bytes = try staking_writer.toOwnedSlice();
    defer allocator.free(staking_bytes);
    try account_info_writer.writeFieldBytes(22, staking_bytes);

    const account_info_bytes = try account_info_writer.toOwnedSlice();
    defer allocator.free(account_info_bytes);

    var info_response_writer = proto.Writer.init(allocator);
    defer info_response_writer.deinit();
    try info_response_writer.writeFieldBytes(2, account_info_bytes);
    const info_response_bytes = try info_response_writer.toOwnedSlice();
    defer allocator.free(info_response_bytes);

    var response_writer = proto.Writer.init(allocator);
    defer response_writer.deinit();
    try response_writer.writeFieldBytes(9, info_response_bytes);
    const payload = try response_writer.toOwnedSlice();
    defer allocator.free(payload);

    var decoded = try decodeAccountInfoResponse(allocator, payload, account_id);
    defer decoded.info.deinit(allocator);

    try std.testing.expectEqual(account_id.shard, decoded.info.account_id.shard);
    try std.testing.expectEqual(account_id.num, decoded.info.account_id.num);
    try std.testing.expect(decoded.info.deleted);
    try std.testing.expectEqualStrings("demo", decoded.info.memo);
    try std.testing.expect(decoded.info.auto_renew_period != null);
    try std.testing.expectEqual(@as(i64, 3600), decoded.info.auto_renew_period.?);
    try std.testing.expectEqual(@as(i64, 42), decoded.info.ethereum_nonce);
    try std.testing.expectEqual(@as(i64, 7500), decoded.balance.toTinybars());
    try std.testing.expectEqual(@as(u64, 4), decoded.info.owned_nfts);
    try std.testing.expectEqual(@as(u32, 3), decoded.info.max_automatic_token_associations);
    try std.testing.expect(decoded.info.alias_key != null);
    try std.testing.expect(decoded.info.key != null);
    const key_union = decoded.info.key.?;
    const pk_bytes = key_union.toBytes();
    try std.testing.expectEqualSlices(u8, &key_bytes, &pk_bytes);
    try std.testing.expect(decoded.info.staking_info != null);
    const staking = decoded.info.staking_info.?;
    try std.testing.expect(staking.decline_staking_reward);
    try std.testing.expectEqual(@as(u64, 100), staking.pending_reward);
}

test "encode account details query" {
    const allocator = std.testing.allocator;
    const account_id = model.AccountId.init(0, 0, 202);
    const bytes = try encodeAccountDetailsQuery(allocator, account_id);
    defer allocator.free(bytes);

    var reader = ProtoReader{ .data = bytes, .index = 0 };
    const outer = (try reader.next()).?;
    try std.testing.expectEqual(@as(u32, 58), outer.number);
}

test "decode account details allowances" {
    const allocator = std.testing.allocator;
    const owner_id = model.AccountId.init(0, 0, 3003);
    const spender_id = model.AccountId.init(0, 0, 4004);
    const token_id = model.TokenId.init(0, 0, 5005);
    const nft_token_id = model.TokenId.init(0, 0, 6006);

    const spender_bytes = try encodeAccountId(allocator, spender_id);
    defer allocator.free(spender_bytes);
    const token_bytes = try encodeTokenId(allocator, token_id);
    defer allocator.free(token_bytes);
    const nft_token_bytes = try encodeTokenId(allocator, nft_token_id);
    defer allocator.free(nft_token_bytes);

    var crypto_writer = proto.Writer.init(allocator);
    defer crypto_writer.deinit();
    try crypto_writer.writeFieldBytes(1, spender_bytes);
    try crypto_writer.writeFieldInt64(2, 7_500);
    const crypto_bytes = try crypto_writer.toOwnedSlice();
    defer allocator.free(crypto_bytes);

    var token_writer = proto.Writer.init(allocator);
    defer token_writer.deinit();
    try token_writer.writeFieldBytes(1, token_bytes);
    try token_writer.writeFieldBytes(2, spender_bytes);
    try token_writer.writeFieldInt64(3, 42);
    const token_allowance_bytes = try token_writer.toOwnedSlice();
    defer allocator.free(token_allowance_bytes);

    var nft_writer = proto.Writer.init(allocator);
    defer nft_writer.deinit();
    try nft_writer.writeFieldBytes(1, nft_token_bytes);
    try nft_writer.writeFieldBytes(2, spender_bytes);
    const nft_allowance_bytes = try nft_writer.toOwnedSlice();
    defer allocator.free(nft_allowance_bytes);

    var details_writer = proto.Writer.init(allocator);
    defer details_writer.deinit();
    try details_writer.writeFieldBytes(17, crypto_bytes);
    try details_writer.writeFieldBytes(18, nft_allowance_bytes);
    try details_writer.writeFieldBytes(19, token_allowance_bytes);
    const details_bytes = try details_writer.toOwnedSlice();
    defer allocator.free(details_bytes);

    var response_body_writer = proto.Writer.init(allocator);
    defer response_body_writer.deinit();
    try response_body_writer.writeFieldBytes(2, details_bytes);
    const response_body = try response_body_writer.toOwnedSlice();
    defer allocator.free(response_body);

    var response_writer = proto.Writer.init(allocator);
    defer response_writer.deinit();
    try response_writer.writeFieldBytes(158, response_body);
    const payload = try response_writer.toOwnedSlice();
    defer allocator.free(payload);

    var allowances = try decodeAccountDetailsAllowances(allocator, payload, owner_id);
    defer allowances.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), allowances.crypto.len);
    try std.testing.expectEqual(@as(usize, 1), allowances.token.len);
    try std.testing.expectEqual(@as(usize, 1), allowances.nft.len);
    try std.testing.expectEqual(@as(i64, 7_500), allowances.crypto[0].amount.toTinybars());
    try std.testing.expectEqual(@as(u64, 42), allowances.token[0].amount);
    try std.testing.expect(allowances.nft[0].approved_for_all);
    try std.testing.expectEqual(nft_token_id.num, allowances.nft[0].token_id.num);
}

test "decode token info response" {
    const allocator = std.testing.allocator;
    const token_id = model.TokenId.init(0, 0, 5002);
    const treasury_id = model.AccountId.init(0, 0, 6006);

    const token_id_bytes = try encodeTokenId(allocator, token_id);
    defer allocator.free(token_id_bytes);
    const treasury_bytes = try encodeAccountId(allocator, treasury_id);
    defer allocator.free(treasury_bytes);

    var key_writer = proto.Writer.init(allocator);
    defer key_writer.deinit();
    var key_raw: [32]u8 = [_]u8{0x22} ** 32;
    try key_writer.writeFieldBytes(2, &key_raw);
    const admin_key_bytes = try key_writer.toOwnedSlice();
    defer allocator.free(admin_key_bytes);

    var expiry_writer = proto.Writer.init(allocator);
    defer expiry_writer.deinit();
    try expiry_writer.writeFieldInt64(1, 1_700_000_100);
    try expiry_writer.writeFieldInt64(2, 9);
    const expiry_bytes = try expiry_writer.toOwnedSlice();
    defer allocator.free(expiry_bytes);

    var duration_writer = proto.Writer.init(allocator);
    defer duration_writer.deinit();
    try duration_writer.writeFieldInt64(1, 86400);
    const duration_bytes = try duration_writer.toOwnedSlice();
    defer allocator.free(duration_bytes);

    var token_info_writer = proto.Writer.init(allocator);
    defer token_info_writer.deinit();
    try token_info_writer.writeFieldBytes(1, token_id_bytes);
    try token_info_writer.writeFieldBytes(2, "TestToken");
    try token_info_writer.writeFieldBytes(3, "TST");
    try token_info_writer.writeFieldVarint(4, 2);
    try token_info_writer.writeFieldVarint(5, 1_000_000);
    try token_info_writer.writeFieldBytes(6, treasury_bytes);
    try token_info_writer.writeFieldBytes(7, admin_key_bytes);
    try token_info_writer.writeFieldVarint(12, 1);
    try token_info_writer.writeFieldVarint(14, 0);
    try token_info_writer.writeFieldBytes(15, treasury_bytes);
    try token_info_writer.writeFieldBytes(16, duration_bytes);
    try token_info_writer.writeFieldBytes(17, expiry_bytes);
    try token_info_writer.writeFieldBytes(18, "memo");
    try token_info_writer.writeFieldVarint(19, 0);
    try token_info_writer.writeFieldVarint(20, 1);
    try token_info_writer.writeFieldInt64(21, 5_000);
    try token_info_writer.writeFieldVarint(25, 1);

    const token_info_bytes = try token_info_writer.toOwnedSlice();
    defer allocator.free(token_info_bytes);

    var token_response_writer = proto.Writer.init(allocator);
    defer token_response_writer.deinit();
    try token_response_writer.writeFieldBytes(2, token_info_bytes);
    const token_response_bytes = try token_response_writer.toOwnedSlice();
    defer allocator.free(token_response_bytes);

    var response_writer = proto.Writer.init(allocator);
    defer response_writer.deinit();
    try response_writer.writeFieldBytes(152, token_response_bytes);
    const payload = try response_writer.toOwnedSlice();
    defer allocator.free(payload);

    var token = try decodeTokenInfoResponse(allocator, payload, token_id);
    defer token.deinit(allocator);

    try std.testing.expectEqual(token_id.num, token.token_id.num);
    try std.testing.expectEqualStrings("TestToken", token.name);
    try std.testing.expectEqualStrings("TST", token.symbol);
    try std.testing.expectEqual(@as(u32, 2), token.decimals);
    try std.testing.expectEqual(@as(u64, 1_000_000), token.total_supply);
    try std.testing.expectEqual(treasury_id.num, token.treasury_account_id.num);
    try std.testing.expect(token.admin_key != null);
    try std.testing.expect(token.freeze_default);
    try std.testing.expect(!token.deleted);
    try std.testing.expect(token.pause_status);
    try std.testing.expectEqual(@as(?u64, 5_000), token.max_supply);
}

fn readVarint(data: []const u8, index: *usize) !u64 {
    var shift: u7 = 0;
    var result: u64 = 0;
    while (true) {
        if (index.* >= data.len) return error.UnexpectedEndOfStream;
        const byte = data[index.*];
        index.* += 1;
        result |= (@as(u64, byte & 0x7F) << shift);
        if ((byte & 0x80) == 0) break;
        shift += 7;
        if (shift >= 64) return error.VarintOverflow;
    }
    return result;
}
