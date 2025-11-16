//! Protobuf helpers for Hedera consensus network queries.

const std = @import("std");
const model = @import("model.zig");
const proto = @import("ser/proto.zig");

pub fn encodeTransactionGetReceiptQuery(
    allocator: std.mem.Allocator,
    tx_id: model.TransactionId,
    include_duplicates: bool,
    include_child_receipts: bool,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const header_bytes = try encodeQueryHeader(allocator);
    defer allocator.free(header_bytes);
    try writer.writeFieldBytes(1, header_bytes);

    const tx_bytes = try encodeTransactionId(allocator, tx_id);
    defer allocator.free(tx_bytes);
    try writer.writeFieldBytes(2, tx_bytes);

    if (include_duplicates) try writer.writeFieldBool(3, true);
    if (include_child_receipts) try writer.writeFieldBool(4, true);

    const body = try writer.toOwnedSlice();
    defer allocator.free(body);

    return try wrapQuery(allocator, 14, body);
}

pub fn encodeTransactionGetRecordQuery(
    allocator: std.mem.Allocator,
    tx_id: model.TransactionId,
    include_duplicates: bool,
    include_child_records: bool,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const header_bytes = try encodeQueryHeader(allocator);
    defer allocator.free(header_bytes);
    try writer.writeFieldBytes(1, header_bytes);

    const tx_bytes = try encodeTransactionId(allocator, tx_id);
    defer allocator.free(tx_bytes);
    try writer.writeFieldBytes(2, tx_bytes);

    if (include_duplicates) try writer.writeFieldBool(3, true);
    if (include_child_records) try writer.writeFieldBool(4, true);

    const body = try writer.toOwnedSlice();
    defer allocator.free(body);

    return try wrapQuery(allocator, 15, body);
}

pub fn encodeScheduleGetInfoQuery(
    allocator: std.mem.Allocator,
    schedule_id: model.ScheduleId,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const header_bytes = try encodeQueryHeader(allocator);
    defer allocator.free(header_bytes);
    try writer.writeFieldBytes(1, header_bytes);

    const schedule_bytes = try encodeAccountId(allocator, schedule_id);
    defer allocator.free(schedule_bytes);
    try writer.writeFieldBytes(2, schedule_bytes);

    const body = try writer.toOwnedSlice();
    defer allocator.free(body);

    return try wrapQuery(allocator, 53, body);
}

pub fn decodeTransactionGetReceiptResponse(
    payload: []const u8,
    fallback_tx_id: model.TransactionId,
) !model.TransactionReceipt {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    var receipt_bytes: ?[]const u8 = null;

    while (try reader.next()) |field| {
        if (field.number == 14 and field.wire == .length_delimited) {
            receipt_bytes = try extractReceipt(field.value);
            break;
        }
    }

    const receipt_payload = receipt_bytes orelse return error.MalformedResponse;
    const status_code = try decodeReceiptStatus(receipt_payload);
    const status = mapStatus(status_code);

    return .{ .status = status, .transaction_id = fallback_tx_id };
}

pub fn decodeTransactionGetRecordResponse(
    allocator: std.mem.Allocator,
    payload: []const u8,
) !model.TransactionRecord {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    var record_bytes: ?[]const u8 = null;

    while (try reader.next()) |field| {
        if (field.number == 15 and field.wire == .length_delimited) {
            record_bytes = try extractRecord(field.value);
            break;
        }
    }

    const record_payload = record_bytes orelse return error.MalformedResponse;
    return try decodeTransactionRecord(allocator, record_payload);
}

pub fn decodeScheduleGetInfoResponse(
    allocator: std.mem.Allocator,
    payload: []const u8,
) !model.ScheduleInfo {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    var info_bytes: ?[]const u8 = null;

    while (try reader.next()) |field| {
        if (field.number == 153 and field.wire == .length_delimited) {
            info_bytes = try extractScheduleInfo(field.value);
            break;
        }
    }

    const schedule_payload = info_bytes orelse return error.MalformedResponse;
    return try decodeScheduleInfo(allocator, schedule_payload);
}

pub const TransactionSubmitResult = struct {
    precheck_code: u32,
    cost: u64,
};

pub fn decodeTransactionResponse(payload: []const u8) !TransactionSubmitResult {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    var code: u32 = 0;
    var cost: u64 = 0;
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => code = @intCast(field.varint),
            2 => cost = field.varint,
            else => {},
        }
    }
    return .{ .precheck_code = code, .cost = cost };
}

pub fn extractTransactionId(tx_bytes: []const u8) !?model.TransactionId {
    var reader = ProtoReader{ .data = tx_bytes, .index = 0 };
    while (try reader.next()) |field| {
        switch (field.number) {
            1, 4 => {
                if (field.wire == .length_delimited) {
                    if (try extractTransactionIdFromBody(field.value)) |tx_id| return tx_id;
                }
            },
            2 => {
                if (field.wire == .length_delimited) {
                    if (try extractTransactionIdFromSigMapBody(field.value)) |tx_id| return tx_id;
                }
            },
            5 => {
                if (field.wire == .length_delimited) {
                    if (try extractTransactionIdFromSigned(field.value)) |tx_id| return tx_id;
                }
            },
            else => {},
        }
    }
    return null;
}

pub fn responseCodeLabel(code: u32) ?[]const u8 {
    return switch (code) {
        0 => "OK",
        1 => "INVALID_TRANSACTION",
        2 => "PAYER_ACCOUNT_NOT_FOUND",
        3 => "INVALID_NODE_ACCOUNT",
        4 => "TRANSACTION_EXPIRED",
        5 => "INVALID_TRANSACTION_START",
        6 => "INVALID_TRANSACTION_DURATION",
        7 => "BUSY",
        8 => "NOT_SUPPORTED",
        9 => "INVALID_FILE_ID",
        10 => "INSUFFICIENT_TX_FEE",
        11 => "INSUFFICIENT_PAYER_BALANCE",
        12 => "DUPLICATE_TRANSACTION",
        13 => "BUSY_RETRY",
        14 => "NOT_SUPPORTED_FEE",
        15 => "INSUFFICIENT_ACCOUNT_BALANCE",
        21 => "UNKNOWN",
        22 => "SUCCESS",
        23 => "FAIL_INVALID",
        24 => "FAIL_FEE",
        25 => "FAIL_BALANCE",
        else => null,
    };
}

pub fn isPrecheckSuccess(code: u32) bool {
    return code == 0 or code == 22;
}

fn wrapQuery(allocator: std.mem.Allocator, field_number: u32, body: []const u8) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldBytes(field_number, body);
    return try writer.toOwnedSlice();
}

fn encodeQueryHeader(allocator: std.mem.Allocator) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    // ResponseType.ANSWER_ONLY = 0
    try writer.writeFieldVarint(2, 0);
    return try writer.toOwnedSlice();
}

fn encodeTransactionId(allocator: std.mem.Allocator, tx_id: model.TransactionId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    const ts_bytes = try encodeTimestamp(allocator, tx_id.valid_start);
    defer allocator.free(ts_bytes);
    try writer.writeFieldBytes(1, ts_bytes);

    const account_bytes = try encodeAccountId(allocator, tx_id.account_id);
    defer allocator.free(account_bytes);
    try writer.writeFieldBytes(2, account_bytes);

    if (tx_id.scheduled) try writer.writeFieldBool(3, true);
    if (tx_id.nonce) |nonce| try writer.writeFieldInt64(4, nonce);

    return try writer.toOwnedSlice();
}

fn encodeAccountId(allocator: std.mem.Allocator, id: model.AccountId) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldInt64(1, @intCast(id.shard));
    try writer.writeFieldInt64(2, @intCast(id.realm));
    try writer.writeFieldInt64(3, @intCast(id.num));
    return try writer.toOwnedSlice();
}

fn encodeTimestamp(allocator: std.mem.Allocator, ts: model.Timestamp) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldInt64(1, ts.seconds);
    try writer.writeFieldInt64(2, ts.nanos);
    return try writer.toOwnedSlice();
}

fn extractReceipt(container: []const u8) ![]const u8 {
    var reader = ProtoReader{ .data = container, .index = 0 };
    while (try reader.next()) |field| {
        if (field.number == 2 and field.wire == .length_delimited) {
            return field.value;
        }
    }
    return error.MalformedResponse;
}

fn extractRecord(container: []const u8) ![]const u8 {
    var reader = ProtoReader{ .data = container, .index = 0 };
    while (try reader.next()) |field| {
        if (field.number == 3 and field.wire == .length_delimited) {
            return field.value;
        }
    }
    return error.MalformedResponse;
}

fn extractScheduleInfo(container: []const u8) ![]const u8 {
    var reader = ProtoReader{ .data = container, .index = 0 };
    while (try reader.next()) |field| {
        if (field.number == 2 and field.wire == .length_delimited) {
            return field.value;
        }
    }
    return error.MalformedResponse;
}

fn decodeReceiptStatus(payload: []const u8) !u32 {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    while (try reader.next()) |field| {
        if (field.number == 1) {
            return @intCast(field.varint);
        }
    }
    return error.MalformedResponse;
}

fn decodeTransactionRecord(allocator: std.mem.Allocator, payload: []const u8) !model.TransactionRecord {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    var transaction_hash: []u8 = &[_]u8{};
    var consensus_timestamp = model.Timestamp{ .seconds = 0, .nanos = 0 };
    var transaction_id: ?model.TransactionId = null;
    var memo: []u8 = &[_]u8{};
    var transaction_fee: u64 = 0;
    var transfers = std.ArrayList(model.Transfer).empty;
    errdefer {
        transfers.deinit(allocator);
        if (transaction_hash.len > 0) allocator.free(transaction_hash);
        if (memo.len > 0) allocator.free(memo);
    }

    while (try reader.next()) |field| {
        switch (field.number) {
            2 => {
                if (transaction_hash.len > 0) allocator.free(transaction_hash);
                transaction_hash = try allocator.dupe(u8, field.value);
            },
            3 => consensus_timestamp = try decodeTimestamp(field.value),
            4 => transaction_id = try decodeTransactionId(field.value),
            5 => {
                if (memo.len > 0) allocator.free(memo);
                memo = try allocator.dupe(u8, field.value);
            },
            6 => transaction_fee = field.varint,
            10 => try decodeTransferList(allocator, &transfers, field.value),
            else => {},
        }
    }

    const tx_id_final = transaction_id orelse return error.MalformedResponse;
    const fee_hbar = model.Hbar.fromTinybars(@as(i64, @intCast(transaction_fee)));
    const transfer_slice = try transfers.toOwnedSlice(allocator);

    return .{
        .transaction_hash = transaction_hash,
        .consensus_timestamp = consensus_timestamp,
        .transaction_id = tx_id_final,
        .memo = memo,
        .transaction_fee = fee_hbar,
        .transfer_list = transfer_slice,
    };
}

fn extractTransactionIdFromBody(payload: []const u8) !?model.TransactionId {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    while (try reader.next()) |field| {
        if (field.number == 1 and field.wire == .length_delimited) {
            return try decodeTransactionId(field.value);
        }
    }
    return null;
}

fn extractTransactionIdFromSigned(payload: []const u8) !?model.TransactionId {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    while (try reader.next()) |field| {
        if (field.number == 1 and field.wire == .length_delimited) {
            return try extractTransactionIdFromBody(field.value);
        }
    }
    return null;
}

fn extractTransactionIdFromSigMapBody(payload: []const u8) !?model.TransactionId {
    // Some encoders place the transaction body directly alongside the signature map.
    return try extractTransactionIdFromBody(payload);
}

fn decodeTransferList(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(model.Transfer),
    payload: []const u8,
) !void {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    while (try reader.next()) |field| {
        if (field.number == 1 and field.wire == .length_delimited) {
            const transfer = try decodeAccountAmount(field.value);
            try list.append(allocator, transfer);
        }
    }
}

fn decodeAccountAmount(payload: []const u8) !model.Transfer {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    var account: ?model.AccountId = null;
    var amount: i64 = 0;
    var is_approval = false;
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => account = try decodeAccountId(field.value),
            2 => amount = zigzagDecode64(field.varint),
            3 => is_approval = field.varint != 0,
            else => {},
        }
    }
    return .{
        .account_id = account orelse return error.MalformedResponse,
        .amount = model.Hbar.fromTinybars(amount),
        .is_approval = is_approval,
    };
}

fn decodeTransactionId(payload: []const u8) !model.TransactionId {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    var account: ?model.AccountId = null;
    var valid_start = model.Timestamp{ .seconds = 0, .nanos = 0 };
    var scheduled = false;
    var nonce: ?i32 = null;
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => valid_start = try decodeTimestamp(field.value),
            2 => account = try decodeAccountId(field.value),
            3 => scheduled = field.varint != 0,
            4 => nonce = @intCast(field.varint),
            else => {},
        }
    }
    const tx_id = model.TransactionId{
        .account_id = account orelse return error.MalformedResponse,
        .valid_start = valid_start,
        .scheduled = scheduled,
        .nonce = nonce,
    };
    return tx_id;
}

fn decodeAccountId(payload: []const u8) !model.AccountId {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    var shard: i64 = 0;
    var realm: i64 = 0;
    var num: i64 = 0;
    while (try reader.next()) |field| {
        switch (field.number) {
            1 => shard = @intCast(field.varint),
            2 => realm = @intCast(field.varint),
            3 => num = @intCast(field.varint),
            else => {},
        }
    }
    return model.AccountId.init(@intCast(shard), @intCast(realm), @intCast(num));
}

fn decodeTimestamp(payload: []const u8) !model.Timestamp {
    var reader = ProtoReader{ .data = payload, .index = 0 };
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

fn decodeScheduleInfo(allocator: std.mem.Allocator, payload: []const u8) !model.ScheduleInfo {
    var reader = ProtoReader{ .data = payload, .index = 0 };
    var schedule_id: ?model.ScheduleId = null;
    var memo: []u8 = &[_]u8{};
    var creator: ?model.AccountId = null;
    var payer: ?model.AccountId = null;
    var expiration_time: ?model.Timestamp = null;
    var execution_time: ?model.Timestamp = null;
    var deletion_time: ?model.Timestamp = null;
    var scheduled_tx_id: ?model.TransactionId = null;
    var ledger_id: ?[]u8 = null;
    var wait_for_expiry = false;

    errdefer {
        if (memo.len > 0) allocator.free(memo);
        if (ledger_id) |bytes| allocator.free(bytes);
    }

    while (try reader.next()) |field| {
        switch (field.number) {
            1 => schedule_id = try decodeAccountId(field.value),
            2 => deletion_time = try decodeTimestamp(field.value),
            3 => execution_time = try decodeTimestamp(field.value),
            4 => expiration_time = try decodeTimestamp(field.value),
            5 => {},
            6 => {
                if (memo.len > 0) allocator.free(memo);
                memo = try allocator.dupe(u8, field.value);
            },
            7 => {},
            8 => {},
            9 => creator = try decodeAccountId(field.value),
            10 => payer = try decodeAccountId(field.value),
            11 => scheduled_tx_id = try decodeTransactionId(field.value),
            12 => {
                if (ledger_id) |bytes| allocator.free(bytes);
                ledger_id = try allocator.dupe(u8, field.value);
            },
            13 => wait_for_expiry = field.varint != 0,
            else => {},
        }
    }

    const schedule_id_final = schedule_id orelse return error.MalformedResponse;
    return .{
        .schedule_id = schedule_id_final,
        .memo = memo,
        .creator_account_id = creator,
        .payer_account_id = payer,
        .expiration_time = expiration_time,
        .execution_time = execution_time,
        .deletion_time = deletion_time,
        .scheduled_transaction_id = scheduled_tx_id,
        .ledger_id = ledger_id,
        .wait_for_expiry = wait_for_expiry,
    };
}

fn mapStatus(code: u32) model.TransactionStatus {
    return switch (code) {
        22, 0 => .success,
        21 => .unknown,
        else => .failed,
    };
}

const ProtoReader = struct {
    data: []const u8,
    index: usize,

    const WireType = enum { varint, length_delimited };

    const Field = struct {
        number: u32,
        wire: WireType,
        varint: u64 = 0,
        value: []const u8 = &[_]u8{},
    };

    fn next(self: *ProtoReader) !?Field {
        if (self.index >= self.data.len) return null;
        const key = try readVarint(self.data, &self.index);
        const number: u32 = @intCast(key >> 3);
        const wire_raw: u3 = @intCast(key & 0x7);
        var field = Field{ .number = number, .wire = switch (wire_raw) {
            0 => .varint,
            2 => .length_delimited,
            else => return error.UnsupportedWireType,
        } };
        switch (field.wire) {
            .varint => field.varint = try readVarint(self.data, &self.index),
            .length_delimited => {
                const len = try readVarint(self.data, &self.index);
                const start = self.index;
                const end = start + len;
                if (end > self.data.len) return error.UnexpectedEndOfStream;
                field.value = self.data[start..end];
                self.index = end;
            },
        }
        return field;
    }
};

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

fn zigzagDecode64(value: u64) i64 {
    const shifted: i64 = @intCast(value >> 1);
    const negate: i64 = @intCast(value & 1);
    return shifted ^ -negate;
}

test "encodeScheduleGetInfoQuery embeds schedule id" {
    const allocator = std.testing.allocator;
    const schedule_id = model.ScheduleId.init(0, 0, 42);
    const encoded = try encodeScheduleGetInfoQuery(allocator, schedule_id);
    defer allocator.free(encoded);

    var reader = ProtoReader{ .data = encoded, .index = 0 };
    var schedule_body: ?[]const u8 = null;
    while (try reader.next()) |field| {
        if (field.number == 53 and field.wire == .length_delimited) {
            schedule_body = field.value;
            break;
        }
    }
    try std.testing.expect(schedule_body != null);
    var inner_reader = ProtoReader{ .data = schedule_body.?, .index = 0 };
    var extracted: ?model.ScheduleId = null;
    while (try inner_reader.next()) |field| {
        if (field.number == 2 and field.wire == .length_delimited) {
            extracted = try decodeAccountId(field.value);
        }
    }

    try std.testing.expect(extracted != null);
    try std.testing.expectEqual(schedule_id.num, extracted.?.num);
}

test "decodeScheduleGetInfoResponse parses memo and execution timestamp" {
    const allocator = std.testing.allocator;
    const schedule_id = model.ScheduleId.init(0, 0, 1337);

    const schedule_id_bytes = try encodeAccountId(allocator, schedule_id);
    defer allocator.free(schedule_id_bytes);

    const execution_ts = model.Timestamp{ .seconds = 1700, .nanos = 42 };
    const execution_bytes = try encodeTimestamp(allocator, execution_ts);
    defer allocator.free(execution_bytes);

    var schedule_info_writer = proto.Writer.init(allocator);
    defer schedule_info_writer.deinit();
    try schedule_info_writer.writeFieldBytes(1, schedule_id_bytes);
    try schedule_info_writer.writeFieldBytes(3, execution_bytes);
    try schedule_info_writer.writeFieldString(6, "test schedule");

    const schedule_info_bytes = try schedule_info_writer.toOwnedSlice();
    defer allocator.free(schedule_info_bytes);

    var response_body_writer = proto.Writer.init(allocator);
    defer response_body_writer.deinit();
    try response_body_writer.writeFieldBytes(2, schedule_info_bytes);
    const response_body = try response_body_writer.toOwnedSlice();
    defer allocator.free(response_body);

    var envelope_writer = proto.Writer.init(allocator);
    defer envelope_writer.deinit();
    try envelope_writer.writeFieldBytes(153, response_body);
    const envelope_bytes = try envelope_writer.toOwnedSlice();
    defer allocator.free(envelope_bytes);

    var info = try decodeScheduleGetInfoResponse(allocator, envelope_bytes);
    defer info.deinit(allocator);

    try std.testing.expectEqual(schedule_id.num, info.schedule_id.num);
    try std.testing.expect(info.execution_time != null);
    try std.testing.expectEqual(execution_ts.seconds, info.execution_time.?.seconds);
    try std.testing.expectEqualStrings("test schedule", info.memo);
}

test "decodeTransactionResponse parses precheck code and cost" {
    const allocator = std.testing.allocator;
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeFieldUint64(1, 22);
    try writer.writeFieldUint64(2, 1234);
    const payload = try writer.toOwnedSlice();
    defer allocator.free(payload);

    const result = try decodeTransactionResponse(payload);
    try std.testing.expectEqual(@as(u32, 22), result.precheck_code);
    try std.testing.expectEqual(@as(u64, 1234), result.cost);
}

test "extractTransactionId recovers id from signed transaction" {
    const tx = @import("tx.zig");
    const allocator = std.testing.allocator;
    var submit = tx.TopicMessageSubmitTransaction.init(allocator);
    defer submit.deinit();

    const tx_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 4242),
        .valid_start = .{ .seconds = 1_700_000_000, .nanos = 123 },
        .nonce = null,
        .scheduled = false,
    };

    _ = submit
        .setTopicId(model.TopicId.init(0, 0, 6006))
        .setTransactionId(tx_id)
        .setNodeAccountId(model.AccountId.init(0, 0, 3));
    _ = try submit.setMessage("hello-world");
    try submit.freeze();

    const bytes = try submit.toBytes();
    defer allocator.free(bytes);

    const extracted = try extractTransactionId(bytes);
    try std.testing.expect(extracted != null);
    try std.testing.expectEqual(tx_id.account_id.num, extracted.?.account_id.num);
    try std.testing.expectEqual(tx_id.valid_start.seconds, extracted.?.valid_start.seconds);
    try std.testing.expectEqual(tx_id.valid_start.nanos, extracted.?.valid_start.nanos);
}

test "responseCodeLabel returns expected literals" {
    try std.testing.expect(std.mem.eql(u8, responseCodeLabel(0).?, "OK"));
    try std.testing.expect(responseCodeLabel(999) == null);
    try std.testing.expect(isPrecheckSuccess(22));
    try std.testing.expect(isPrecheckSuccess(0));
    try std.testing.expect(!isPrecheckSuccess(7));
}
