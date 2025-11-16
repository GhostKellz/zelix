//! Helpers for parsing Hedera Mirror Node JSON responses into model types.

const std = @import("std");
const model = @import("model.zig");

const json = std.json;
const mem = std.mem;
const fmt = std.fmt;

pub const TransactionsPage = struct {
    records: []model.TransactionRecord,
    next: ?[]u8,
};

pub const ParseError = error{
    InvalidJson,
    MissingField,
    InvalidType,
    InvalidFormat,
    OutOfMemory,
};

fn dupString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    if (value.len == 0) return "";
    return try allocator.dupe(u8, value);
}

fn dupOptionalString(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |slice| {
        if (slice.len == 0) return "";
        return try allocator.dupe(u8, slice);
    }
    return null;
}

fn expectObject(value: json.Value) ParseError!json.ObjectMap {
    return switch (value) {
        .object => |obj| obj,
        else => ParseError.InvalidJson,
    };
}

fn expectArray(value: json.Value) ParseError!json.Array {
    return switch (value) {
        .array => |arr| arr,
        else => ParseError.InvalidJson,
    };
}

fn getField(obj: json.ObjectMap, name: []const u8) ParseError!json.Value {
    return obj.get(name) orelse ParseError.MissingField;
}

fn getOptionalField(obj: json.ObjectMap, name: []const u8) ?json.Value {
    return obj.get(name);
}

fn parseBoolValue(value: json.Value) ParseError!bool {
    return switch (value) {
        .bool => |b| b,
        .string => |s| switch (s.len) {
            0 => false,
            else => std.ascii.eqlIgnoreCase(s, "true"),
        },
        .integer => |i| i != 0,
        else => ParseError.InvalidType,
    };
}

fn parseOptionalBool(value: ?json.Value) ParseError!?bool {
    if (value) |v| {
        if (v == .null) return null;
        return try parseBoolValue(v);
    }
    return null;
}

fn parseI64(value: json.Value) ParseError!i64 {
    return switch (value) {
        .integer => |i| i,
        .string => |s| fmt.parseInt(i64, s, 10) catch ParseError.InvalidFormat,
        else => ParseError.InvalidType,
    };
}

fn parseOptionalI64(value: ?json.Value) ParseError!?i64 {
    if (value) |v| {
        if (v == .null) return null;
        return try parseI64(v);
    }
    return null;
}

fn parseU64(value: json.Value) ParseError!u64 {
    return switch (value) {
        .integer => |i| if (i < 0) ParseError.InvalidFormat else @as(u64, @intCast(i)),
        .string => |s| fmt.parseInt(u64, s, 10) catch ParseError.InvalidFormat,
        else => ParseError.InvalidType,
    };
}

fn parseOptionalU64(value: ?json.Value) ParseError!?u64 {
    if (value) |v| {
        if (v == .null) return null;
        return try parseU64(v);
    }
    return null;
}

fn parseTimestamp(str: []const u8) ParseError!model.Timestamp {
    if (str.len == 0) return ParseError.InvalidFormat;
    const dot = mem.indexOfScalar(u8, str, '.') orelse return model.Timestamp{
        .seconds = fmt.parseInt(i64, str, 10) catch return ParseError.InvalidFormat,
        .nanos = 0,
    };

    const seconds_str = str[0..dot];
    const nanos_str = str[dot + 1 ..];
    const seconds = fmt.parseInt(i64, seconds_str, 10) catch return ParseError.InvalidFormat;
    var nanos_tmp = fmt.parseInt(i64, nanos_str, 10) catch return ParseError.InvalidFormat;
    // Ensure nanos is 9 digits by padding/truncating
    if (nanos_str.len < 9) {
        var multiplier: i64 = 1;
        var idx = nanos_str.len;
        while (idx < 9) : (idx += 1) multiplier *= 10;
        nanos_tmp *= multiplier;
    } else if (nanos_str.len > 9) {
        const shift = nanos_str.len - 9;
        var divisor: i64 = 1;
        var idx: usize = 0;
        while (idx < shift) : (idx += 1) divisor *= 10;
        nanos_tmp = @divTrunc(nanos_tmp, divisor);
    }

    return model.Timestamp{ .seconds = seconds, .nanos = nanos_tmp };
}

fn parseOptionalTimestamp(value: ?json.Value) ParseError!?model.Timestamp {
    if (value) |v| {
        return switch (v) {
            .string => |s| try parseTimestamp(s),
            .null => null,
            else => ParseError.InvalidType,
        };
    }
    return null;
}

fn parseEntityId(str: []const u8) ParseError!model.EntityId {
    return model.EntityId.fromString(str) catch ParseError.InvalidFormat;
}

fn parseOptionalEntityId(value: ?json.Value) ParseError!?model.EntityId {
    if (value) |v| {
        if (v == .null) return null;
        return switch (v) {
            .string => |s| try parseEntityId(s),
            else => ParseError.InvalidType,
        };
    }
    return null;
}

fn getTransactionsArray(obj: json.ObjectMap) ParseError!json.Array {
    const transactions_val = try getField(obj, "transactions");
    return try expectArray(transactions_val);
}

fn getTransactionObjectAt(arr: json.Array, index: usize) ParseError!json.ObjectMap {
    if (index >= arr.items.len) return ParseError.MissingField;
    return try expectObject(arr.items[index]);
}

fn parseTransactionStatusField(tx_obj: json.ObjectMap) ParseError!model.TransactionStatus {
    const result_field = try getField(tx_obj, "result");
    const result_str = switch (result_field) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };
    return mapTransactionStatus(result_str);
}

fn emptyCryptoAllowanceSlice() []model.CryptoAllowance {
    return @constCast((&[_]model.CryptoAllowance{})[0..]);
}

fn emptyTokenAllowanceSlice() []model.TokenAllowance {
    return @constCast((&[_]model.TokenAllowance{})[0..]);
}

fn emptyNftAllowanceSlice() []model.TokenNftAllowance {
    return @constCast((&[_]model.TokenNftAllowance{})[0..]);
}

fn emptyTransactionRecordSlice() []model.TransactionRecord {
    return @constCast((&[_]model.TransactionRecord{})[0..]);
}

fn parseInlineCryptoAllowances(
    allocator: std.mem.Allocator,
    obj: json.ObjectMap,
    owner_account_id: model.AccountId,
) ParseError![]model.CryptoAllowance {
    const field = getOptionalField(obj, "allowances") orelse return emptyCryptoAllowanceSlice();
    if (field == .null) return emptyCryptoAllowanceSlice();

    const array = switch (field) {
        .array => |arr| arr,
        else => return ParseError.InvalidType,
    };

    if (array.items.len == 0) return emptyCryptoAllowanceSlice();

    const slice = try allocator.alloc(model.CryptoAllowance, array.items.len);
    errdefer allocator.free(slice);

    for (array.items, 0..) |entry_val, idx| {
        const entry = try expectObject(entry_val);
        const spender_raw = switch (try getField(entry, "spender")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const amount_val = try getField(entry, "amount");
        const timestamp_val = getOptionalField(entry, "timestamp");

        var owner = owner_account_id;
        if (getOptionalField(entry, "owner")) |owner_val| switch (owner_val) {
            .string => |owner_str| owner = try parseEntityId(owner_str),
            .null => owner = owner_account_id,
            else => return ParseError.InvalidType,
        };

        const amount_raw = try parseI64(amount_val);
        if (amount_raw < 0) return ParseError.InvalidFormat;

        slice[idx] = model.CryptoAllowance{
            .owner_account_id = owner,
            .spender_account_id = try parseEntityId(spender_raw),
            .amount = model.Hbar.fromTinybars(amount_raw),
            .timestamp = try parseOptionalTimestamp(timestamp_val),
        };
    }

    return slice;
}

fn parseInlineTokenAllowances(
    allocator: std.mem.Allocator,
    obj: json.ObjectMap,
) ParseError![]model.TokenAllowance {
    const field = getOptionalField(obj, "token_allowances") orelse return emptyTokenAllowanceSlice();
    if (field == .null) return emptyTokenAllowanceSlice();

    const array = switch (field) {
        .array => |arr| arr,
        else => return ParseError.InvalidType,
    };

    if (array.items.len == 0) return emptyTokenAllowanceSlice();

    const slice = try allocator.alloc(model.TokenAllowance, array.items.len);
    errdefer allocator.free(slice);

    for (array.items, 0..) |entry_val, idx| {
        const entry = try expectObject(entry_val);
        const owner_raw = switch (try getField(entry, "owner")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const spender_raw = switch (try getField(entry, "spender")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const token_raw = switch (try getField(entry, "token_id")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const amount_val = try getField(entry, "amount");
        const timestamp_val = getOptionalField(entry, "timestamp");

        slice[idx] = model.TokenAllowance{
            .owner_account_id = try parseEntityId(owner_raw),
            .spender_account_id = try parseEntityId(spender_raw),
            .token_id = try parseEntityId(token_raw),
            .amount = try parseU64(amount_val),
            .timestamp = try parseOptionalTimestamp(timestamp_val),
        };
    }

    return slice;
}

fn parseSerialNumbersArray(
    allocator: std.mem.Allocator,
    serials_val: ?json.Value,
) ParseError![]u64 {
    if (serials_val == null) return @constCast((&[_]u64{})[0..]);
    const value = serials_val.?;
    return switch (value) {
        .null => @constCast((&[_]u64{})[0..]),
        .array => |arr| blk: {
            if (arr.items.len == 0) break :blk @constCast((&[_]u64{})[0..]);
            const serials = try allocator.alloc(u64, arr.items.len);
            errdefer allocator.free(serials);
            for (arr.items, 0..) |serial_val, idx| {
                serials[idx] = try parseU64(serial_val);
            }
            break :blk serials;
        },
        else => ParseError.InvalidType,
    };
}

fn parseInlineNftAllowances(
    allocator: std.mem.Allocator,
    obj: json.ObjectMap,
) ParseError![]model.TokenNftAllowance {
    const field = getOptionalField(obj, "nft_allowances") orelse return emptyNftAllowanceSlice();
    if (field == .null) return emptyNftAllowanceSlice();

    const array = switch (field) {
        .array => |arr| arr,
        else => return ParseError.InvalidType,
    };

    if (array.items.len == 0) return emptyNftAllowanceSlice();

    const slice = try allocator.alloc(model.TokenNftAllowance, array.items.len);
    errdefer {
        for (slice) |*item| item.deinit(allocator);
        allocator.free(slice);
    }

    for (array.items, 0..) |entry_val, idx| {
        const entry = try expectObject(entry_val);
        const owner_raw = switch (try getField(entry, "owner")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const spender_raw = switch (try getField(entry, "spender")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const token_raw = switch (try getField(entry, "token_id")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };

        const serials = try parseSerialNumbersArray(allocator, getOptionalField(entry, "serial_numbers"));
        const approved_val = getOptionalField(entry, "approved_for_all");
        const timestamp_val = getOptionalField(entry, "timestamp");

        slice[idx] = model.TokenNftAllowance{
            .owner_account_id = try parseEntityId(owner_raw),
            .spender_account_id = try parseEntityId(spender_raw),
            .token_id = try parseEntityId(token_raw),
            .serial_numbers = serials,
            .approved_for_all = try parseOptionalBool(approved_val) orelse false,
            .timestamp = try parseOptionalTimestamp(timestamp_val),
        };
    }

    return slice;
}

fn decodeBase64(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    if (data.len == 0) return "";
    const decoder = std.base64.standard.Decoder;
    const size = decoder.calcSizeForSlice(data) catch return ParseError.InvalidFormat;
    const buf = try allocator.alloc(u8, size);
    errdefer allocator.free(buf);
    decoder.decode(buf, data) catch return ParseError.InvalidFormat;
    return buf;
}

fn decodeHex(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    if (data.len == 0) return "";
    var hex = data;
    if (hex.len >= 2 and (hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))) {
        hex = hex[2..];
    }
    if (hex.len % 2 != 0) return ParseError.InvalidFormat;
    const buf = try allocator.alloc(u8, hex.len / 2);
    errdefer allocator.free(buf);
    _ = std.fmt.hexToBytes(buf, hex) catch return ParseError.InvalidFormat;
    return buf;
}

fn parseTransactionId(str: []const u8) ParseError!model.TransactionId {
    const first_dash = mem.indexOfScalar(u8, str, '-') orelse return ParseError.InvalidFormat;
    const second_dash = mem.indexOfScalarPos(u8, str, first_dash + 1, '-') orelse return ParseError.InvalidFormat;
    const account_str = str[0..first_dash];
    const seconds_str = str[first_dash + 1 .. second_dash];
    const nanos_str = str[second_dash + 1 ..];

    const account_id = try parseEntityId(account_str);
    const seconds = fmt.parseInt(i64, seconds_str, 10) catch return ParseError.InvalidFormat;
    const nanos = fmt.parseInt(i64, nanos_str, 10) catch return ParseError.InvalidFormat;

    return model.TransactionId{
        .account_id = account_id,
        .valid_start = model.Timestamp{ .seconds = seconds, .nanos = nanos },
        .nonce = null,
        .scheduled = false,
    };
}

fn mapTransactionStatus(result: []const u8) model.TransactionStatus {
    if (mem.eql(u8, result, "SUCCESS")) return .success;
    if (mem.eql(u8, result, "UNKNOWN")) return .unknown;
    return .failed;
}

pub fn parseAccountBalance(
    allocator: std.mem.Allocator,
    body: []const u8,
    expected_account_id: model.AccountId,
) ParseError!model.Hbar {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);

    if (getOptionalField(obj, "balances")) |balances_val| {
        const balances = switch (balances_val) {
            .array => |arr| arr,
            else => return ParseError.InvalidType,
        };

        for (balances.items) |entry| {
            const entry_obj = try expectObject(entry);
            const account_val = try getField(entry_obj, "account");
            const balance_val = try getField(entry_obj, "balance");
            const account_str = switch (account_val) {
                .string => |s| s,
                else => return ParseError.InvalidType,
            };
            const account_id = try parseEntityId(account_str);
            if (account_id.shard != expected_account_id.shard or
                account_id.realm != expected_account_id.realm or
                account_id.num != expected_account_id.num)
            {
                continue;
            }
            const amount = try parseI64(balance_val);
            return model.Hbar.fromTinybars(amount);
        }
    }

    if (getOptionalField(obj, "balance")) |balance_obj_val| {
        const balance_obj = try expectObject(balance_obj_val);
        const balance_val = try getField(balance_obj, "balance");
        const amount = try parseI64(balance_val);
        return model.Hbar.fromTinybars(amount);
    }

    return ParseError.MissingField;
}

pub fn parseAccountInfo(
    allocator: std.mem.Allocator,
    body: []const u8,
    expected_account_id: model.AccountId,
) ParseError!model.AccountInfo {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);

    var info = model.AccountInfo{
        .account_id = expected_account_id,
        .alias_key = null,
        .contract_account_id = null,
        .deleted = try parseBoolValue(getOptionalField(obj, "deleted") orelse json.Value{ .bool = false }),
        .expiry_timestamp = null,
        .key = null,
        .auto_renew_period = null,
        .memo = "",
        .owned_nfts = try parseOptionalU64(getOptionalField(obj, "owned_nfts")) orelse 0,
        .max_automatic_token_associations = @as(u32, @intCast(try parseOptionalU64(getOptionalField(obj, "max_automatic_token_associations")) orelse 0)),
        .receiver_sig_required = try parseOptionalBool(getOptionalField(obj, "receiver_sig_required")) orelse false,
        .ethereum_nonce = try parseOptionalI64(getOptionalField(obj, "ethereum_nonce")) orelse 0,
        .staking_info = null,
    };

    if (getOptionalField(obj, "memo")) |memo_val| {
        switch (memo_val) {
            .string => |memo_str| info.memo = try dupString(allocator, memo_str),
            .null => info.memo = "",
            else => return ParseError.InvalidType,
        }
    }

    if (getOptionalField(obj, "contract_account_id")) |contract_val| switch (contract_val) {
        .string => |s| info.contract_account_id = try dupOptionalString(allocator, s),
        .null => info.contract_account_id = null,
        else => return ParseError.InvalidType,
    };

    if (getOptionalField(obj, "expiry_timestamp")) |expiry_val| {
        switch (expiry_val) {
            .string => |ts| info.expiry_timestamp = try parseTimestamp(ts),
            .null => info.expiry_timestamp = null,
            else => return ParseError.InvalidType,
        }
    }

    if (getOptionalField(obj, "auto_renew_period")) |arp_val| {
        info.auto_renew_period = try parseI64(arp_val);
    }

    // Staking info may appear under "staking" or direct fields.
    const staking_val = getOptionalField(obj, "staking") orelse getOptionalField(obj, "staking_info");
    if (staking_val) |val| {
        const staking_obj = try expectObject(val);
        var staking = model.StakingInfo{};
        staking.decline_staking_reward = try parseOptionalBool(getOptionalField(staking_obj, "decline_reward")) orelse false;
        staking.pending_reward = try parseOptionalU64(getOptionalField(staking_obj, "pending_reward")) orelse 0;
        staking.staked_to_me = try parseOptionalU64(getOptionalField(staking_obj, "staked_to_me")) orelse 0;
        if (getOptionalField(staking_obj, "stake_period_start")) |stake_ts_val| {
            switch (stake_ts_val) {
                .string => |ts| staking.stake_period_start = try parseTimestamp(ts),
                .null => staking.stake_period_start = null,
                else => return ParseError.InvalidType,
            }
        }
        if (getOptionalField(staking_obj, "staked_account_id")) |acct_val| switch (acct_val) {
            .string => |acct_str| staking.staked_account_id = try parseEntityId(acct_str),
            .null => staking.staked_account_id = null,
            else => return ParseError.InvalidType,
        };
        if (getOptionalField(staking_obj, "staked_node_id")) |node_val| {
            const node = try parseI64(node_val);
            staking.staked_node_id = if (node >= 0) @as(u64, @intCast(node)) else null;
        }
        info.staking_info = staking;
    }

    return info;
}

pub fn parseAccountAllowances(
    allocator: std.mem.Allocator,
    body: []const u8,
    owner_account_id: model.AccountId,
) ParseError!model.AccountAllowances {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);

    var allowances = model.AccountAllowances.empty();
    errdefer allowances.deinit(allocator);

    allowances.crypto = try parseInlineCryptoAllowances(allocator, obj, owner_account_id);
    allowances.token = try parseInlineTokenAllowances(allocator, obj);
    allowances.nft = try parseInlineNftAllowances(allocator, obj);

    return allowances;
}

pub fn parseAccountRecords(allocator: std.mem.Allocator, body: []const u8) ParseError!model.AccountRecords {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);
    const tx_array = try getTransactionsArray(obj);
    const tx_count = tx_array.items.len;
    var records = try allocator.alloc(model.TransactionRecord, tx_count);
    var record_index: usize = 0;
    errdefer {
        for (records[0..record_index]) |*record| record.deinit(allocator);
        if (records.len > 0) allocator.free(records);
    }

    for (tx_array.items) |tx_value| {
        const tx_obj = try expectObject(tx_value);
        const record = try parseTransactionRecordObject(allocator, tx_obj);
        records[record_index] = record;
        record_index += 1;
    }

    return model.AccountRecords{ .records = records[0..record_index] };
}

pub fn parseTransactionsPage(allocator: std.mem.Allocator, body: []const u8) ParseError!TransactionsPage {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);
    const tx_array = try getTransactionsArray(obj);

    var records = try allocator.alloc(model.TransactionRecord, tx_array.items.len);
    var record_index: usize = 0;
    errdefer {
        for (records[0..record_index]) |*record| record.deinit(allocator);
        if (records.len > 0) allocator.free(records);
    }

    for (tx_array.items) |tx_value| {
        const tx_obj = try expectObject(tx_value);
        const record = try parseTransactionRecordObject(allocator, tx_obj);
        records[record_index] = record;
        record_index += 1;
    }

    var next_token: ?[]u8 = null;
    if (obj.get("links")) |links_val| {
        const links_obj = try expectObject(links_val);
        if (links_obj.get("next")) |next_val| {
            switch (next_val) {
                .string => |s| {
                    if (s.len > 0) next_token = try allocator.dupe(u8, s);
                },
                .null => {},
                else => return ParseError.InvalidType,
            }
        }
    }

    return TransactionsPage{ .records = records[0..record_index], .next = next_token };
}

fn parseTransactionRecordObject(
    allocator: std.mem.Allocator,
    tx_obj: json.ObjectMap,
) ParseError!model.TransactionRecord {
    const tx_id_str = switch (try getField(tx_obj, "transaction_id")) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };
    const consensus_ts = switch (try getField(tx_obj, "consensus_timestamp")) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };

    const transaction_id = try parseTransactionId(tx_id_str);
    const consensus_timestamp = try parseTimestamp(consensus_ts);

    const hash_field = getOptionalField(tx_obj, "transaction_hash");
    const memo_field = getOptionalField(tx_obj, "memo_base64");
    const charge_field = try getField(tx_obj, "charged_tx_fee");
    const transfers_field = try getField(tx_obj, "transfers");

    const transaction_fee = model.Hbar.fromTinybars(try parseI64(charge_field));
    _ = try parseTransactionStatusField(tx_obj);

    var transaction_hash: []const u8 = "";
    if (hash_field) |hash_val| {
        switch (hash_val) {
            .string => |hash_str| transaction_hash = try decodeBase64(allocator, hash_str),
            .null => transaction_hash = "",
            else => return ParseError.InvalidType,
        }
    }

    var memo: []const u8 = "";
    if (memo_field) |memo_val| switch (memo_val) {
        .string => |memo_str| memo = try decodeBase64(allocator, memo_str),
        .null => memo = "",
        else => return ParseError.InvalidType,
    };

    const transfers_array = try expectArray(transfers_field);
    var transfers = try allocator.alloc(model.Transfer, transfers_array.items.len);
    errdefer allocator.free(transfers);

    for (transfers_array.items, 0..) |transfer_val, index| {
        const transfer_obj = try expectObject(transfer_val);
        const account_str = switch (try getField(transfer_obj, "account")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const amount_val = try getField(transfer_obj, "amount");
        const amount = try parseI64(amount_val);
        const is_approval = try parseOptionalBool(getOptionalField(transfer_obj, "is_approval")) orelse false;

        transfers[index] = model.Transfer{
            .account_id = try parseEntityId(account_str),
            .amount = model.Hbar.fromTinybars(amount),
            .is_approval = is_approval,
        };
    }

    return model.TransactionRecord{
        .transaction_hash = transaction_hash,
        .consensus_timestamp = consensus_timestamp,
        .transaction_id = transaction_id,
        .memo = memo,
        .transaction_fee = transaction_fee,
        .transfer_list = transfers,
        .duplicates = emptyTransactionRecordSlice(),
        .children = emptyTransactionRecordSlice(),
    };
}

pub fn parseTransactionRecord(
    allocator: std.mem.Allocator,
    body: []const u8,
    expected_transaction_id: model.TransactionId,
) ParseError!model.TransactionRecord {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);
    const tx_array = try getTransactionsArray(obj);
    const tx_obj = try getTransactionObjectAt(tx_array, 0);
    var record = try parseTransactionRecordObject(allocator, tx_obj);
    record.transaction_id = expected_transaction_id;
    return record;
}

pub fn parseTransactionReceipt(
    allocator: std.mem.Allocator,
    body: []const u8,
    expected_transaction_id: model.TransactionId,
) ParseError!model.TransactionReceipt {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);
    const tx_array = try getTransactionsArray(obj);
    const tx_obj = try getTransactionObjectAt(tx_array, 0);

    const status = try parseTransactionStatusField(tx_obj);
    return model.TransactionReceipt{ .status = status, .transaction_id = expected_transaction_id };
}

fn mapTokenType(token_type: []const u8) ParseError!model.TokenType {
    if (mem.eql(u8, token_type, "FUNGIBLE_COMMON")) return .fungible_common;
    if (mem.eql(u8, token_type, "NON_FUNGIBLE_UNIQUE")) return .non_fungible_unique;
    return ParseError.InvalidFormat;
}

fn mapSupplyType(supply_type: []const u8) ParseError!model.TokenSupplyType {
    if (mem.eql(u8, supply_type, "INFINITE")) return .infinite;
    if (mem.eql(u8, supply_type, "FINITE")) return .finite;
    return ParseError.InvalidFormat;
}

pub fn parseTokenInfo(
    allocator: std.mem.Allocator,
    body: []const u8,
    token_id: model.TokenId,
) ParseError!model.TokenInfo {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);

    const name_val = try getField(obj, "name");
    const symbol_val = try getField(obj, "symbol");
    const decimals_val = try getField(obj, "decimals");
    const total_supply_val = try getField(obj, "total_supply");
    const type_val = try getField(obj, "type");
    const supply_type_val = try getField(obj, "supply_type");
    const treasury_val = try getField(obj, "treasury_account_id");

    const name = switch (name_val) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };
    const symbol = switch (symbol_val) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };
    const type_str = switch (type_val) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };
    const supply_type_str = switch (supply_type_val) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };
    const treasury_str = switch (treasury_val) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };

    var info = model.TokenInfo{
        .token_id = token_id,
        .name = try dupString(allocator, name),
        .symbol = try dupString(allocator, symbol),
        .decimals = @as(u32, @intCast(try parseU64(decimals_val))),
        .total_supply = try parseU64(total_supply_val),
        .treasury_account_id = try parseEntityId(treasury_str),
        .admin_key = null,
        .kyc_key = null,
        .freeze_key = null,
        .wipe_key = null,
        .supply_key = null,
        .fee_schedule_key = null,
        .pause_key = null,
        .token_type = try mapTokenType(type_str),
        .supply_type = try mapSupplyType(supply_type_str),
        .max_supply = try parseOptionalU64(getOptionalField(obj, "max_supply")),
        .freeze_default = try parseOptionalBool(getOptionalField(obj, "freeze_default")) orelse false,
        .pause_status = false,
        .deleted = try parseOptionalBool(getOptionalField(obj, "deleted")) orelse false,
        .expiry_timestamp = try parseOptionalTimestamp(getOptionalField(obj, "expiry_timestamp")),
        .auto_renew_period = try parseOptionalI64(getOptionalField(obj, "auto_renew_period")),
        .auto_renew_account_id = null,
        .memo = "",
        .custom_fees = &.{},
    };

    if (getOptionalField(obj, "auto_renew_account")) |autoacct_val| switch (autoacct_val) {
        .string => |s| info.auto_renew_account_id = try parseEntityId(s),
        .null => info.auto_renew_account_id = null,
        else => return ParseError.InvalidType,
    };

    if (getOptionalField(obj, "pause_status")) |pause_val| switch (pause_val) {
        .string => |s| info.pause_status = mem.eql(u8, s, "PAUSED"),
        .null => info.pause_status = false,
        else => return ParseError.InvalidType,
    };

    if (getOptionalField(obj, "memo")) |memo_val| switch (memo_val) {
        .string => |memo_str| info.memo = try dupString(allocator, memo_str),
        .null => info.memo = "",
        else => return ParseError.InvalidType,
    };

    return info;
}

pub fn parseTokenBalances(allocator: std.mem.Allocator, body: []const u8) ParseError!model.TokenBalances {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);
    const tokens_val = try getField(obj, "tokens");

    const tokens_array = switch (tokens_val) {
        .array => |arr| arr,
        else => return ParseError.InvalidType,
    };

    const token_count = tokens_array.items.len;
    var balances = try allocator.alloc(model.TokenBalance, token_count);
    var balance_index: usize = 0;
    errdefer {
        if (balances.len > 0) allocator.free(balances);
    }

    for (tokens_array.items) |token_val| {
        const token_obj = try expectObject(token_val);
        const token_id_str = switch (try getField(token_obj, "token_id")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const balance_val = try getField(token_obj, "balance");
        const decimals_val = try getField(token_obj, "decimals");

        const token_id = try parseEntityId(token_id_str);
        const balance = try parseU64(balance_val);
        const decimals = @as(u32, @intCast(try parseU64(decimals_val)));

        balances[balance_index] = model.TokenBalance{
            .token_id = token_id,
            .balance = balance,
            .decimals = decimals,
        };
        balance_index += 1;
    }

    return model.TokenBalances{ .balances = balances[0..balance_index] };
}

pub fn parseNftInfo(
    allocator: std.mem.Allocator,
    body: []const u8,
    expected_token_id: model.TokenId,
    expected_serial: u64,
) ParseError!model.NftInfo {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const obj = try expectObject(parsed.value);

    const token_id_str = switch (try getField(obj, "token_id")) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };
    const parsed_token_id = try parseEntityId(token_id_str);
    if (parsed_token_id.shard != expected_token_id.shard or
        parsed_token_id.realm != expected_token_id.realm or
        parsed_token_id.num != expected_token_id.num)
    {
        return ParseError.InvalidFormat;
    }

    const serial_number = switch (try getField(obj, "serial_number")) {
        .integer => |i| if (i < 0) ParseError.InvalidFormat else @as(u64, @intCast(i)),
        .string => |s| try std.fmt.parseInt(u64, s, 10),
        else => return ParseError.InvalidType,
    };
    if (serial_number != expected_serial) return ParseError.InvalidFormat;

    const owner_str = switch (try getField(obj, "account_id")) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };
    const metadata_str = switch (try getField(obj, "metadata")) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };
    const created_val = try getField(obj, "created_timestamp");

    const metadata_copy = try decodeBase64(allocator, metadata_str);
    errdefer allocator.free(metadata_copy);

    var info = model.NftInfo{
        .id = model.NftId.init(expected_token_id, expected_serial),
        .owner_account_id = try parseEntityId(owner_str),
        .spender_account_id = null,
        .delegating_spender_account_id = null,
        .created_timestamp = switch (created_val) {
            .string => |s| try parseTimestamp(s),
            else => return ParseError.InvalidType,
        },
        .modified_timestamp = try parseOptionalTimestamp(getOptionalField(obj, "modified_timestamp")),
        .metadata = metadata_copy,
        .ledger_id = null,
        .deleted = try parseOptionalBool(getOptionalField(obj, "deleted")) orelse false,
    };

    if (getOptionalField(obj, "spender")) |spender_val| switch (spender_val) {
        .string => |s| info.spender_account_id = try parseEntityId(s),
        .null => info.spender_account_id = null,
        else => return ParseError.InvalidType,
    };

    if (getOptionalField(obj, "delegating_spender")) |delegate_val| switch (delegate_val) {
        .string => |s| info.delegating_spender_account_id = try parseEntityId(s),
        .null => info.delegating_spender_account_id = null,
        else => return ParseError.InvalidType,
    };

    if (getOptionalField(obj, "ledger_id")) |ledger_val| switch (ledger_val) {
        .string => |s| info.ledger_id = try dupString(allocator, s),
        .null => info.ledger_id = null,
        else => return ParseError.InvalidType,
    };

    return info;
}

pub fn parseTokenAllowances(
    allocator: std.mem.Allocator,
    body: []const u8,
) ParseError!model.TokenAllowancesPage {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root_obj = try expectObject(parsed.value);
    const allowances_val = try getField(root_obj, "allowances");
    const allowances_arr = switch (allowances_val) {
        .array => |arr| arr,
        else => return ParseError.InvalidType,
    };

    const total = allowances_arr.items.len;
    var items = try allocator.alloc(model.TokenAllowance, total);
    errdefer allocator.free(items);

    for (allowances_arr.items, 0..) |entry_val, idx| {
        const entry = try expectObject(entry_val);
        const owner_str = switch (try getField(entry, "owner")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const spender_str = switch (try getField(entry, "spender")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const token_str = switch (try getField(entry, "token_id")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const amount_val = try getField(entry, "amount");
        const timestamp_val = getOptionalField(entry, "timestamp");

        items[idx] = model.TokenAllowance{
            .owner_account_id = try parseEntityId(owner_str),
            .spender_account_id = try parseEntityId(spender_str),
            .token_id = try parseEntityId(token_str),
            .amount = try parseU64(amount_val),
            .timestamp = try parseOptionalTimestamp(timestamp_val),
        };
    }

    var next: ?[]u8 = null;
    if (root_obj.get("links")) |links_val| {
        const links_obj = try expectObject(links_val);
        if (links_obj.get("next")) |next_val| switch (next_val) {
            .string => |s| {
                if (s.len > 0) next = try dupString(allocator, s);
            },
            .null => next = null,
            else => return ParseError.InvalidType,
        };
    }

    return model.TokenAllowancesPage{
        .allowances = items,
        .next = next,
    };
}

pub fn parseTokenNftAllowances(
    allocator: std.mem.Allocator,
    body: []const u8,
) ParseError!model.TokenNftAllowancesPage {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root_obj = try expectObject(parsed.value);
    const allowances_val = try getField(root_obj, "allowances");
    const allowances_arr = switch (allowances_val) {
        .array => |arr| arr,
        else => return ParseError.InvalidType,
    };

    const total = allowances_arr.items.len;
    var allowances = try allocator.alloc(model.TokenNftAllowance, total);
    errdefer {
        for (allowances) |*item| item.deinit(allocator);
        allocator.free(allowances);
    }

    for (allowances_arr.items, 0..) |entry_val, idx| {
        const entry = try expectObject(entry_val);
        const owner_str = switch (try getField(entry, "owner")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const spender_str = switch (try getField(entry, "spender")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };
        const token_str = switch (try getField(entry, "token_id")) {
            .string => |s| s,
            else => return ParseError.InvalidType,
        };

        const approved_val = getOptionalField(entry, "approved_for_all");
        const timestamp_val = getOptionalField(entry, "timestamp");

        const serials_val = getOptionalField(entry, "serial_numbers") orelse json.Value{ .array = .{ .items = &[_]json.Value{} } };
        const serials_arr = switch (serials_val) {
            .array => |arr| arr,
            else => return ParseError.InvalidType,
        };

        var serials = try allocator.alloc(u64, serials_arr.items.len);
        errdefer allocator.free(serials);
        for (serials_arr.items, 0..) |serial_val, sidx| {
            serials[sidx] = try parseU64(serial_val);
        }

        allowances[idx] = model.TokenNftAllowance{
            .owner_account_id = try parseEntityId(owner_str),
            .spender_account_id = try parseEntityId(spender_str),
            .token_id = try parseEntityId(token_str),
            .serial_numbers = serials,
            .approved_for_all = try parseOptionalBool(approved_val) orelse false,
            .timestamp = try parseOptionalTimestamp(timestamp_val),
        };
    }

    var next: ?[]u8 = null;
    if (root_obj.get("links")) |links_val| {
        const links_obj = try expectObject(links_val);
        if (links_obj.get("next")) |next_val| switch (next_val) {
            .string => |s| {
                if (s.len > 0) next = try dupString(allocator, s);
            },
            .null => next = null,
            else => return ParseError.InvalidType,
        };
    }

    return model.TokenNftAllowancesPage{
        .allowances = allowances,
        .next = next,
    };
}

pub fn parseContractInfo(
    allocator: std.mem.Allocator,
    body: []const u8,
    contract_id: model.ContractId,
) ParseError!model.ContractInfo {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);

    const account_id_val = try getField(obj, "account_id");
    const account_id_str = switch (account_id_val) {
        .string => |s| s,
        else => return ParseError.InvalidType,
    };
    const account_id = try parseEntityId(account_id_str);

    var info = model.ContractInfo{
        .contract_id = contract_id,
        .account_id = account_id,
        .contract_account_id = null,
        .admin_key = null,
        .initcode = "",
        .bytecode = "",
        .expiry_timestamp = try parseOptionalTimestamp(getOptionalField(obj, "expiration_timestamp")),
        .auto_renew_period = try parseOptionalI64(getOptionalField(obj, "auto_renew_period")),
        .auto_renew_account_id = null,
        .memo = "",
        .max_automatic_token_associations = @as(u32, @intCast(try parseOptionalU64(getOptionalField(obj, "max_automatic_token_associations")) orelse 0)),
        .ethereum_nonce = try parseOptionalI64(getOptionalField(obj, "ethereum_nonce")) orelse 0,
        .staking_info = null,
    };

    if (getOptionalField(obj, "contract_account_id")) |contract_account_val| switch (contract_account_val) {
        .string => |s| info.contract_account_id = try dupOptionalString(allocator, s),
        .null => info.contract_account_id = null,
        else => return ParseError.InvalidType,
    };

    if (getOptionalField(obj, "memo")) |memo_val| switch (memo_val) {
        .string => |memo_str| info.memo = try dupString(allocator, memo_str),
        .null => info.memo = "",
        else => return ParseError.InvalidType,
    };

    if (getOptionalField(obj, "auto_renew_account_id")) |auto_val| switch (auto_val) {
        .string => |s| info.auto_renew_account_id = try parseEntityId(s),
        .null => info.auto_renew_account_id = null,
        else => return ParseError.InvalidType,
    };

    const staking_val = getOptionalField(obj, "staking") orelse getOptionalField(obj, "staking_info");
    if (staking_val) |val| {
        const staking_obj = try expectObject(val);
        var staking = model.StakingInfo{};
        staking.decline_staking_reward = try parseOptionalBool(getOptionalField(staking_obj, "decline_reward")) orelse false;
        staking.pending_reward = try parseOptionalU64(getOptionalField(staking_obj, "pending_reward")) orelse 0;
        staking.staked_to_me = try parseOptionalU64(getOptionalField(staking_obj, "staked_to_me")) orelse 0;
        if (getOptionalField(staking_obj, "stake_period_start")) |ts_val| switch (ts_val) {
            .string => |ts| staking.stake_period_start = try parseTimestamp(ts),
            .null => staking.stake_period_start = null,
            else => return ParseError.InvalidType,
        };
        if (getOptionalField(staking_obj, "staked_account_id")) |acct_val| switch (acct_val) {
            .string => |s| staking.staked_account_id = try parseEntityId(s),
            .null => staking.staked_account_id = null,
            else => return ParseError.InvalidType,
        };
        if (getOptionalField(staking_obj, "staked_node_id")) |node_val| {
            const node = try parseI64(node_val);
            staking.staked_node_id = if (node >= 0) @as(u64, @intCast(node)) else null;
        }
        info.staking_info = staking;
    }

    return info;
}

pub fn parseContractCallResult(allocator: std.mem.Allocator, body: []const u8, contract_id: model.ContractId) ParseError!model.ContractFunctionResult {
    var parsed = json.parseFromSlice(json.Value, allocator, body, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ParseError.InvalidJson,
    };
    defer parsed.deinit();

    const root = parsed.value;
    const obj = try expectObject(root);

    const gas_used = try parseOptionalU64(getOptionalField(obj, "gas_used")) orelse 0;
    const gas = try parseOptionalU64(getOptionalField(obj, "gas")) orelse 0;

    var result_bytes: []const u8 = "";
    if (getOptionalField(obj, "result")) |result_val| switch (result_val) {
        .string => |result_str| result_bytes = try decodeHex(allocator, result_str),
        .null => result_bytes = "",
        else => return ParseError.InvalidType,
    };

    var bloom_bytes: []const u8 = "";
    if (getOptionalField(obj, "bloom")) |bloom_val| switch (bloom_val) {
        .string => |bloom_str| bloom_bytes = try decodeHex(allocator, bloom_str),
        .null => bloom_bytes = "",
        else => return ParseError.InvalidType,
    };

    var error_message: ?[]const u8 = null;
    if (getOptionalField(obj, "error_message")) |err_val| switch (err_val) {
        .string => |err_str| error_message = try dupOptionalString(allocator, err_str),
        .null => error_message = null,
        else => return ParseError.InvalidType,
    };

    var sender_account_id: ?model.AccountId = null;
    if (getOptionalField(obj, "from")) |from_val| switch (from_val) {
        .string => |from_str| sender_account_id = try parseEntityId(from_str),
        .null => sender_account_id = null,
        else => return ParseError.InvalidType,
    };

    return model.ContractFunctionResult{
        .contract_id = contract_id,
        .contract_call_result = result_bytes,
        .error_message = error_message,
        .bloom = bloom_bytes,
        .gas_used = gas_used,
        .gas = gas,
        .hbar_amount = model.Hbar.ZERO,
        .function_parameters = "",
        .sender_account_id = sender_account_id,
    };
}

// --------------------------- Tests ---------------------------

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

test "parse nft info" {
    const allocator = std.testing.allocator;
    const token_id = model.TokenId.init(0, 0, 6001);
    const body =
        "{\n" ++ "  \"token_id\": \"0.0.6001\",\n" ++ "  \"serial_number\": 42,\n" ++ "  \"account_id\": \"0.0.5005\",\n" ++ "  \"metadata\": \"SGVsbG8=\",\n" ++ "  \"created_timestamp\": \"1700000000.123456789\",\n" ++ "  \"modified_timestamp\": \"1700000001.000000000\",\n" ++ "  \"spender\": \"0.0.7007\",\n" ++ "  \"delegating_spender\": null,\n" ++ "  \"deleted\": false,\n" ++ "  \"ledger_id\": \"mainnet\"\n" ++ "}";

    var info = try parseNftInfo(allocator, body, token_id, 42);
    defer info.deinit(allocator);

    try std.testing.expectEqual(token_id.num, info.id.token_id.num);
    try std.testing.expectEqual(@as(u64, 42), info.id.serial);
    try std.testing.expectEqual(@as(u64, 5005), info.owner_account_id.num);
    try std.testing.expect(info.spender_account_id != null);
    try std.testing.expectEqual(@as(u64, 7007), info.spender_account_id.?.num);
    try std.testing.expectEqualStrings("Hello", info.metadata);
    try std.testing.expect(info.ledger_id != null);
    try std.testing.expectEqualStrings("mainnet", info.ledger_id.?);
}

test "parse token allowances" {
    const allocator = std.testing.allocator;
    const body =
        "{\n" ++ "  \"allowances\": [\n" ++ "    {\n" ++ "      \"amount\": \"100\",\n" ++ "      \"owner\": \"0.0.1001\",\n" ++ "      \"spender\": \"0.0.2002\",\n" ++ "      \"token_id\": \"0.0.3003\",\n" ++ "      \"timestamp\": \"1700000002.123456789\"\n" ++ "    }\n" ++ "  ],\n" ++ "  \"links\": { \"next\": \"/api/v1/accounts/0.0.1001/allowances/tokens?timestamp=lt:1700000002.123456789\" }\n" ++ "}";

    var page = try parseTokenAllowances(allocator, body);
    defer page.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), page.allowances.len);
    try std.testing.expect(page.next != null);
    try std.testing.expectEqualStrings("/api/v1/accounts/0.0.1001/allowances/tokens?timestamp=lt:1700000002.123456789", page.next.?);
    try std.testing.expectEqual(@as(u64, 100), page.allowances[0].amount);
    try std.testing.expectEqual(@as(u64, 1001), page.allowances[0].owner_account_id.num);
    try std.testing.expectEqual(@as(u64, 2002), page.allowances[0].spender_account_id.num);
    try std.testing.expect(page.allowances[0].timestamp != null);
}

test "parse token nft allowances" {
    const allocator = std.testing.allocator;
    const body =
        "{\n" ++ "  \"allowances\": [\n" ++ "    {\n" ++ "      \"approved_for_all\": false,\n" ++ "      \"owner\": \"0.0.4004\",\n" ++ "      \"spender\": \"0.0.5005\",\n" ++ "      \"token_id\": \"0.0.6006\",\n" ++ "      \"serial_numbers\": [1, 3, 5]\n" ++ "    }\n" ++ "  ],\n" ++ "  \"links\": { \"next\": null }\n" ++ "}";

    var page = try parseTokenNftAllowances(allocator, body);
    defer page.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), page.allowances.len);
    try std.testing.expect(page.next == null);
    try std.testing.expectEqual(@as(usize, 3), page.allowances[0].serial_numbers.len);
    try std.testing.expectEqual(@as(u64, 3), page.allowances[0].serial_numbers[1]);
    try std.testing.expect(!page.allowances[0].approved_for_all);
}

test "parse account info" {
    const allocator = std.testing.allocator;
    const body = "{\n" ++
        "  \"account\": \"0.0.1001\",\n" ++
        "  \"memo\": \"demo account\",\n" ++
        "  \"receiver_sig_required\": true,\n" ++
        "  \"ethereum_nonce\": 2,\n" ++
        "  \"max_automatic_token_associations\": 10,\n" ++
        "  \"owned_nfts\": 5,\n" ++
        "  \"auto_renew_period\": 7776000,\n" ++
        "  \"expiry_timestamp\": \"1700000000.123456789\",\n" ++
        "  \"deleted\": false,\n" ++
        "  \"contract_account_id\": \"00000000000000000000000000000000000003e9\",\n" ++
        "  \"staking\": {\n" ++
        "    \"decline_reward\": false,\n" ++
        "    \"pending_reward\": 100,\n" ++
        "    \"staked_to_me\": 200,\n" ++
        "    \"staked_node_id\": 3,\n" ++
        "    \"stake_period_start\": \"1690000000.000000000\"\n" ++
        "  }\n" ++
        "}";

    const account_id = model.AccountId.init(0, 0, 1001);
    var info = try parseAccountInfo(allocator, body, account_id);
    defer info.deinit(allocator);

    try expectEqual(account_id, info.account_id);
    try expect(std.mem.eql(u8, info.memo, "demo account"));
    try expect(info.receiver_sig_required);
    try expectEqual(@as(i64, 2), info.ethereum_nonce);
    try expectEqual(@as(u32, 10), info.max_automatic_token_associations);
    try expectEqual(@as(u64, 5), info.owned_nfts);
    try expect(info.auto_renew_period != null);
    try expect(info.expiry_timestamp != null);
    try expect(info.staking_info != null);
}

test "parse account allowances" {
    const allocator = std.testing.allocator;
    const body = "{\n" ++
        "  \"allowances\": [\n" ++
        "    {\n" ++
        "      \"owner\": \"0.0.1001\",\n" ++
        "      \"spender\": \"0.0.2002\",\n" ++
        "      \"amount\": 5000,\n" ++
        "      \"timestamp\": \"1700000000.100000000\"\n" ++
        "    }\n" ++
        "  ],\n" ++
        "  \"token_allowances\": [\n" ++
        "    {\n" ++
        "      \"owner\": \"0.0.1001\",\n" ++
        "      \"spender\": \"0.0.2002\",\n" ++
        "      \"token_id\": \"0.0.3003\",\n" ++
        "      \"amount\": 42,\n" ++
        "      \"timestamp\": \"1700000001.000000000\"\n" ++
        "    }\n" ++
        "  ],\n" ++
        "  \"nft_allowances\": [\n" ++
        "    {\n" ++
        "      \"owner\": \"0.0.1001\",\n" ++
        "      \"spender\": \"0.0.2002\",\n" ++
        "      \"token_id\": \"0.0.4004\",\n" ++
        "      \"serial_numbers\": [1, 2],\n" ++
        "      \"approved_for_all\": false,\n" ++
        "      \"timestamp\": \"1700000002.000000000\"\n" ++
        "    }\n" ++
        "  ]\n" ++
        "}";

    const owner = model.AccountId.init(0, 0, 1001);
    var allowances = try parseAccountAllowances(allocator, body, owner);
    defer allowances.deinit(allocator);

    try expectEqual(@as(usize, 1), allowances.crypto.len);
    try expectEqual(@as(usize, 1), allowances.token.len);
    try expectEqual(@as(usize, 1), allowances.nft.len);
    try expectEqual(@as(i64, 5000), allowances.crypto[0].amount.toTinybars());
    try expectEqual(@as(u64, 42), allowances.token[0].amount);
    try expectEqual(@as(usize, 2), allowances.nft[0].serial_numbers.len);
    try expect(!allowances.nft[0].approved_for_all);
    try expect(allowances.crypto[0].timestamp != null);
    try expect(allowances.token[0].timestamp != null);
    try expect(allowances.nft[0].timestamp != null);
}

test "parse account records" {
    const allocator = std.testing.allocator;
    const body = "{\n" ++
        "  \"transactions\": [\n" ++
        "    {\n" ++
        "      \"transaction_id\": \"0.0.1001-1700000000-000000001\",\n" ++
        "      \"consensus_timestamp\": \"1700000001.000000000\",\n" ++
        "      \"transaction_hash\": \"YWJj\",\n" ++
        "      \"memo_base64\": \"VGVzdA==\",\n" ++
        "      \"charged_tx_fee\": 1000,\n" ++
        "      \"result\": \"SUCCESS\",\n" ++
        "      \"transfers\": [\n" ++
        "        { \"account\": \"0.0.1001\", \"amount\": -1000 },\n" ++
        "        { \"account\": \"0.0.2002\", \"amount\": 1000 }\n" ++
        "      ]\n" ++
        "    }\n" ++
        "  ]\n" ++
        "}";

    var records = try parseAccountRecords(allocator, body);
    defer records.deinit(allocator);

    try expectEqual(@as(usize, 1), records.records.len);
    const record = records.records[0];
    try expectEqual(model.TransactionStatus.success, mapTransactionStatus("SUCCESS"));
    try expectEqual(model.TransactionStatus.unknown, mapTransactionStatus("UNKNOWN"));
    try expectEqual(model.TransactionStatus.failed, mapTransactionStatus("FAILURE"));
    try expectEqual(@as(i64, 1000), record.transaction_fee.toTinybars());
    try expectEqual(@as(u64, 2), record.transfer_list.len);
    try expectEqual(@as(usize, 0), record.duplicates.len);
    try expectEqual(@as(usize, 0), record.children.len);
}

test "parse transaction receipt" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const body = "{" ++
        "\"transactions\":[{" ++
        "\"transaction_id\":\"0.0.500-1700000001-42\"," ++
        "\"consensus_timestamp\":\"1700000002.000000123\"," ++
        "\"transaction_hash\":\"AQID\"," ++
        "\"memo_base64\":\"bWVtbw==\"," ++
        "\"charged_tx_fee\":1000," ++
        "\"result\":\"SUCCESS\"," ++
        "\"transfers\":[{" ++
        "\"account\":\"0.0.500\"," ++
        "\"amount\":-10," ++
        "\"is_approval\":false},{" ++
        "\"account\":\"0.0.600\"," ++
        "\"amount\":10," ++
        "\"is_approval\":false}]}]}";

    const expected_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 500),
        .valid_start = .{ .seconds = 1_700_000_001, .nanos = 42 },
        .nonce = null,
        .scheduled = false,
    };

    const receipt = try parseTransactionReceipt(allocator, body, expected_id);
    try expectEqual(model.TransactionStatus.success, receipt.status);
    try expectEqual(expected_id.account_id.num, receipt.transaction_id.account_id.num);
    try expectEqual(expected_id.valid_start.seconds, receipt.transaction_id.valid_start.seconds);
    try expectEqual(expected_id.valid_start.nanos, receipt.transaction_id.valid_start.nanos);
}

test "parse transaction record" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const body = "{" ++
        "\"transactions\":[{" ++
        "\"transaction_id\":\"0.0.500-1700000001-42\"," ++
        "\"consensus_timestamp\":\"1700000002.000000123\"," ++
        "\"transaction_hash\":\"AQID\"," ++
        "\"memo_base64\":\"bWVtbw==\"," ++
        "\"charged_tx_fee\":1000," ++
        "\"result\":\"SUCCESS\"," ++
        "\"transfers\":[{" ++
        "\"account\":\"0.0.500\"," ++
        "\"amount\":-10," ++
        "\"is_approval\":false},{" ++
        "\"account\":\"0.0.600\"," ++
        "\"amount\":10," ++
        "\"is_approval\":true}]}]}";

    const expected_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 500),
        .valid_start = .{ .seconds = 1_700_000_001, .nanos = 42 },
        .nonce = null,
        .scheduled = false,
    };

    var record = try parseTransactionRecord(allocator, body, expected_id);
    defer record.deinit(allocator);

    try expectEqual(expected_id.account_id.num, record.transaction_id.account_id.num);
    try expectEqual(expected_id.valid_start.seconds, record.transaction_id.valid_start.seconds);
    try expectEqual(expected_id.valid_start.nanos, record.transaction_id.valid_start.nanos);
    try expectEqual(@as(i64, 1_000), record.transaction_fee.toTinybars());
    try expectEqual(@as(usize, 2), record.transfer_list.len);
    try expectEqual(@as(i64, -10), record.transfer_list[0].amount.toTinybars());
    try expectEqual(@as(i64, 10), record.transfer_list[1].amount.toTinybars());
    try expect(!record.transfer_list[0].is_approval);
    try expect(record.transfer_list[1].is_approval);
    try expect(mem.eql(u8, record.memo, "memo"));
    const expected_hash = [_]u8{ 0x01, 0x02, 0x03 };
    try expect(mem.eql(u8, record.transaction_hash, &expected_hash));
    try expectEqual(@as(usize, 0), record.duplicates.len);
    try expectEqual(@as(usize, 0), record.children.len);
}

test "parse transactions page" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const body = "{\n" ++
        "  \"transactions\": [\n" ++
        "    {\n" ++
        "      \"transaction_id\": \"0.0.1001-1700000000-1\",\n" ++
        "      \"consensus_timestamp\": \"1700000000.000000001\",\n" ++
        "      \"transaction_hash\": \"AQID\",\n" ++
        "      \"memo_base64\": \"bWVtbw==\",\n" ++
        "      \"charged_tx_fee\": 1,\n" ++
        "      \"result\": \"SUCCESS\",\n" ++
        "      \"transfers\": [\n" ++
        "        { \"account\": \"0.0.1001\", \"amount\": -1 },\n" ++
        "        { \"account\": \"0.0.2002\", \"amount\": 1 }\n" ++
        "      ]\n" ++
        "    }\n" ++
        "  ],\n" ++
        "  \"links\": { \"next\": \"/api/v1/transactions?timestamp=gt:1700000000.000000001\" }\n" ++
        "}";

    var page = try parseTransactionsPage(allocator, body);
    defer {
        for (page.records) |*record| record.deinit(allocator);
        if (page.records.len > 0) allocator.free(page.records);
        if (page.next) |token| allocator.free(token);
    }

    try expectEqual(@as(usize, 1), page.records.len);
    try expect(page.next != null);
    try std.testing.expectEqualStrings("/api/v1/transactions?timestamp=gt:1700000000.000000001", page.next.?);
    try expectEqual(@as(usize, 0), page.records[0].duplicates.len);
    try expectEqual(@as(usize, 0), page.records[0].children.len);
}

test "parse token info" {
    const allocator = std.testing.allocator;
    const body = "{\n" ++
        "  \"token_id\": \"0.0.5005\",\n" ++
        "  \"name\": \"Demo Token\",\n" ++
        "  \"symbol\": \"DT\",\n" ++
        "  \"decimals\": 8,\n" ++
        "  \"total_supply\": \"1000000\",\n" ++
        "  \"type\": \"FUNGIBLE_COMMON\",\n" ++
        "  \"supply_type\": \"FINITE\",\n" ++
        "  \"max_supply\": 1000000,\n" ++
        "  \"treasury_account_id\": \"0.0.1234\",\n" ++
        "  \"freeze_default\": false,\n" ++
        "  \"deleted\": false,\n" ++
        "  \"memo\": \"Token memo\"\n" ++
        "}";

    const token_id = model.TokenId.init(0, 0, 5005);
    var info = try parseTokenInfo(allocator, body, token_id);
    defer info.deinit(allocator);

    try expectEqual(token_id, info.token_id);
    try expect(mem.eql(u8, info.name, "Demo Token"));
    try expectEqual(model.TokenType.fungible_common, info.token_type);
    try expectEqual(model.TokenSupplyType.finite, info.supply_type);
}

test "parse token balances" {
    const allocator = std.testing.allocator;
    const body = "{\n" ++
        "  \"tokens\": [\n" ++
        "    { \"token_id\": \"0.0.5005\", \"balance\": \"1000\", \"decimals\": 8 },\n" ++
        "    { \"token_id\": \"0.0.6006\", \"balance\": 10, \"decimals\": 0 }\n" ++
        "  ]\n" ++
        "}";

    var balances = try parseTokenBalances(allocator, body);
    defer balances.deinit(allocator);

    try expectEqual(@as(usize, 2), balances.balances.len);
    try expectEqual(@as(u64, 1000), balances.balances[0].balance);
}

test "parse contract info" {
    const allocator = std.testing.allocator;
    const body = "{\n" ++
        "  \"contract_id\": \"0.0.9000\",\n" ++
        "  \"account_id\": \"0.0.9000\",\n" ++
        "  \"contract_account_id\": \"0000000000000000000000000000000000002328\",\n" ++
        "  \"memo\": \"Contract memo\",\n" ++
        "  \"auto_renew_period\": 7776000,\n" ++
        "  \"expiration_timestamp\": \"1700000000.000000000\",\n" ++
        "  \"max_automatic_token_associations\": 5\n" ++
        "}";

    const contract_id = model.ContractId.init(0, 0, 9000);
    var info = try parseContractInfo(allocator, body, contract_id);
    defer info.deinit(allocator);

    try expectEqual(contract_id, info.contract_id);
    try expect(mem.eql(u8, info.memo, "Contract memo"));
}

test "parse contract call result" {
    const allocator = std.testing.allocator;
    const body = "{\n" ++
        "  \"result\": \"0x010203\",\n" ++
        "  \"bloom\": \"0x00\",\n" ++
        "  \"gas_used\": 12345,\n" ++
        "  \"gas\": 200000,\n" ++
        "  \"error_message\": null\n" ++
        "}";

    const contract_id = model.ContractId.init(0, 0, 9000);
    var result = try parseContractCallResult(allocator, body, contract_id);
    defer result.deinit(allocator);

    try expectEqual(@as(u64, 12345), result.gas_used);
    try expectEqual(@as(usize, 3), result.contract_call_result.len);
}
