///! Block Stream protobuf parser for extracting transaction data from BlockItems.
///! Implements parsing for HIP-1056/1081 Block Stream format.

const std = @import("std");
const model = @import("model.zig");
const proto = @import("ser/proto.zig");

/// Parsed transaction from event_transaction BlockItem
pub const ParsedTransaction = struct {
    transaction_id: model.TransactionId,
    consensus_timestamp: model.Timestamp,
    memo: ?[]const u8 = null,
    transaction_fee: u64 = 0,
    transfers: std.ArrayList(Transfer),

    pub const Transfer = struct {
        account_id: model.AccountId,
        amount: i64,
    };

    pub fn init(allocator: std.mem.Allocator) ParsedTransaction {
        return .{
            .transaction_id = .{},
            .consensus_timestamp = .{},
            .transfers = std.ArrayList(Transfer).init(allocator),
        };
    }

    pub fn deinit(self: *ParsedTransaction) void {
        self.transfers.deinit();
    }

    /// Convert to TransactionRecord for compatibility with existing APIs
    pub fn toTransactionRecord(self: *const ParsedTransaction, allocator: std.mem.Allocator) !model.TransactionRecord {
        _ = allocator;
        return model.TransactionRecord{
            .transaction_id = self.transaction_id,
            .consensus_timestamp = self.consensus_timestamp,
            .memo = self.memo,
            .transaction_fee = self.transaction_fee,
            .transfers = try self.transfers.clone(),
            .status = .success,
            .is_duplicate = false,
            .is_child = false,
        };
    }
};

/// Parsed transaction result from transaction_result BlockItem
pub const ParsedTransactionResult = struct {
    consensus_timestamp: model.Timestamp,
    status: model.ResponseCode = .success,
    transaction_fee_charged: u64 = 0,

    pub fn init() ParsedTransactionResult {
        return .{
            .consensus_timestamp = .{},
        };
    }
};

/// Parsed transaction output from transaction_output BlockItem (for contract calls)
pub const ParsedTransactionOutput = struct {
    consensus_timestamp: model.Timestamp,
    contract_call_result: ?ContractCallResult = null,

    pub const ContractCallResult = struct {
        contract_id: model.ContractId,
        output: []const u8,
        gas_used: u64,
        error_message: ?[]const u8 = null,
    };

    pub fn init() ParsedTransactionOutput {
        return .{
            .consensus_timestamp = .{},
        };
    }
};

/// State change entry from state_changes BlockItem
pub const StateChange = struct {
    consensus_timestamp: model.Timestamp,
    change_type: ChangeType,

    pub const ChangeType = enum {
        account_balance,
        token_balance,
        contract_storage,
        file_content,
        unknown,
    };

    pub fn init() StateChange {
        return .{
            .consensus_timestamp = .{},
            .change_type = .unknown,
        };
    }
};

/// Parse event_transaction BlockItem into ParsedTransaction
pub fn parseEventTransaction(allocator: std.mem.Allocator, data: []const u8) !ParsedTransaction {
    var tx = ParsedTransaction.init(allocator);
    errdefer tx.deinit();

    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        switch (field.field_number) {
            1 => { // transaction_id
                if (field.data == .bytes) {
                    tx.transaction_id = try parseTransactionId(field.data.bytes);
                }
            },
            2 => { // consensus_timestamp
                if (field.data == .bytes) {
                    tx.consensus_timestamp = try parseTimestamp(field.data.bytes);
                }
            },
            3 => { // memo
                if (field.data == .bytes) {
                    tx.memo = field.data.bytes;
                }
            },
            4 => { // transaction_fee
                if (field.data == .varint) {
                    tx.transaction_fee = field.data.varint;
                }
            },
            5 => { // transfer_list
                if (field.data == .bytes) {
                    try parseTransferList(&tx.transfers, field.data.bytes);
                }
            },
            else => {
                // Skip unknown fields
                try reader.skip(field.wire_type);
            },
        }
    }

    return tx;
}

/// Parse transaction_result BlockItem into ParsedTransactionResult
pub fn parseTransactionResult(data: []const u8) !ParsedTransactionResult {
    var result = ParsedTransactionResult.init();

    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        switch (field.field_number) {
            1 => { // consensus_timestamp
                if (field.data == .bytes) {
                    result.consensus_timestamp = try parseTimestamp(field.data.bytes);
                }
            },
            2 => { // status (enum value)
                if (field.data == .varint) {
                    result.status = intToResponseCode(@intCast(field.data.varint));
                }
            },
            3 => { // transaction_fee_charged
                if (field.data == .varint) {
                    result.transaction_fee_charged = field.data.varint;
                }
            },
            else => {
                try reader.skip(field.wire_type);
            },
        }
    }

    return result;
}

/// Parse transaction_output BlockItem into ParsedTransactionOutput
pub fn parseTransactionOutput(data: []const u8) !ParsedTransactionOutput {
    var output = ParsedTransactionOutput.init();

    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        switch (field.field_number) {
            1 => { // consensus_timestamp
                if (field.data == .bytes) {
                    output.consensus_timestamp = try parseTimestamp(field.data.bytes);
                }
            },
            2 => { // contract_call_result
                if (field.data == .bytes) {
                    output.contract_call_result = try parseContractCallResult(field.data.bytes);
                }
            },
            else => {
                try reader.skip(field.wire_type);
            },
        }
    }

    return output;
}

/// Parse state_changes BlockItem into list of StateChange entries
pub fn parseStateChanges(allocator: std.mem.Allocator, data: []const u8) !std.ArrayList(StateChange) {
    var changes = std.ArrayList(StateChange).init(allocator);
    errdefer changes.deinit();

    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        if (field.field_number == 1 and field.data == .bytes) {
            // Parse individual state change
            const change = try parseStateChange(field.data.bytes);
            try changes.append(change);
        } else {
            try reader.skip(field.wire_type);
        }
    }

    return changes;
}

// Helper functions

fn parseTransactionId(data: []const u8) !model.TransactionId {
    var tx_id = model.TransactionId{};
    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        switch (field.field_number) {
            1 => { // account_id
                if (field.data == .bytes) {
                    tx_id.account_id = try parseAccountId(field.data.bytes);
                }
            },
            2 => { // transaction_valid_start
                if (field.data == .bytes) {
                    tx_id.valid_start = try parseTimestamp(field.data.bytes);
                }
            },
            else => try reader.skip(field.wire_type),
        }
    }

    return tx_id;
}

fn parseTimestamp(data: []const u8) !model.Timestamp {
    var timestamp = model.Timestamp{};
    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        switch (field.field_number) {
            1 => { // seconds
                if (field.data == .varint) {
                    timestamp.seconds = @intCast(field.data.varint);
                }
            },
            2 => { // nanos
                if (field.data == .varint) {
                    timestamp.nanos = @intCast(field.data.varint);
                }
            },
            else => try reader.skip(field.wire_type),
        }
    }

    return timestamp;
}

fn parseAccountId(data: []const u8) !model.AccountId {
    var account_id = model.AccountId{};
    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        switch (field.field_number) {
            1 => { // shard_num
                if (field.data == .varint) {
                    account_id.shard = @intCast(field.data.varint);
                }
            },
            2 => { // realm_num
                if (field.data == .varint) {
                    account_id.realm = @intCast(field.data.varint);
                }
            },
            3 => { // account_num
                if (field.data == .varint) {
                    account_id.num = @intCast(field.data.varint);
                }
            },
            else => try reader.skip(field.wire_type),
        }
    }

    return account_id;
}

fn parseTransferList(transfers: *std.ArrayList(ParsedTransaction.Transfer), data: []const u8) !void {
    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        if (field.field_number == 1 and field.data == .bytes) {
            // Parse individual transfer
            const transfer = try parseTransfer(field.data.bytes);
            try transfers.append(transfer);
        } else {
            try reader.skip(field.wire_type);
        }
    }
}

fn parseTransfer(data: []const u8) !ParsedTransaction.Transfer {
    var transfer = ParsedTransaction.Transfer{
        .account_id = .{},
        .amount = 0,
    };
    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        switch (field.field_number) {
            1 => { // account_id
                if (field.data == .bytes) {
                    transfer.account_id = try parseAccountId(field.data.bytes);
                }
            },
            2 => { // amount (sint64)
                if (field.data == .varint) {
                    transfer.amount = @bitCast(field.data.varint);
                }
            },
            else => try reader.skip(field.wire_type),
        }
    }

    return transfer;
}

fn parseContractCallResult(data: []const u8) !ParsedTransactionOutput.ContractCallResult {
    var result = ParsedTransactionOutput.ContractCallResult{
        .contract_id = .{},
        .output = &[_]u8{},
        .gas_used = 0,
    };
    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        switch (field.field_number) {
            1 => { // contract_id
                if (field.data == .bytes) {
                    result.contract_id = try parseContractId(field.data.bytes);
                }
            },
            2 => { // output
                if (field.data == .bytes) {
                    result.output = field.data.bytes;
                }
            },
            3 => { // gas_used
                if (field.data == .varint) {
                    result.gas_used = field.data.varint;
                }
            },
            4 => { // error_message
                if (field.data == .bytes) {
                    result.error_message = field.data.bytes;
                }
            },
            else => try reader.skip(field.wire_type),
        }
    }

    return result;
}

fn parseContractId(data: []const u8) !model.ContractId {
    var contract_id = model.ContractId{};
    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        switch (field.field_number) {
            1 => { // shard_num
                if (field.data == .varint) {
                    contract_id.shard = @intCast(field.data.varint);
                }
            },
            2 => { // realm_num
                if (field.data == .varint) {
                    contract_id.realm = @intCast(field.data.varint);
                }
            },
            3 => { // contract_num
                if (field.data == .varint) {
                    contract_id.num = @intCast(field.data.varint);
                }
            },
            else => try reader.skip(field.wire_type),
        }
    }

    return contract_id;
}

fn parseStateChange(data: []const u8) !StateChange {
    var change = StateChange.init();
    var reader = proto.Reader.init(data);

    while (try reader.readField()) |field| {
        switch (field.field_number) {
            1 => { // consensus_timestamp
                if (field.data == .bytes) {
                    change.consensus_timestamp = try parseTimestamp(field.data.bytes);
                }
            },
            2 => { // change_type
                if (field.data == .varint) {
                    change.change_type = intToChangeType(@intCast(field.data.varint));
                }
            },
            else => try reader.skip(field.wire_type),
        }
    }

    return change;
}

fn intToResponseCode(value: u32) model.ResponseCode {
    return switch (value) {
        0 => .ok,
        1 => .invalid_transaction,
        2 => .payer_account_not_found,
        3 => .invalid_node_account,
        4 => .transaction_expired,
        5 => .invalid_transaction_start,
        6 => .invalid_transaction_duration,
        7 => .invalid_signature,
        8 => .memo_too_long,
        9 => .insufficient_tx_fee,
        10 => .insufficient_payer_balance,
        11 => .duplicate_transaction,
        12 => .busy,
        13 => .not_supported,
        14 => .invalid_file_id,
        15 => .invalid_account_id,
        16 => .invalid_contract_id,
        17 => .invalid_transaction_id,
        18 => .receipt_not_found,
        19 => .record_not_found,
        20 => .invalid_solidity_id,
        21 => .unknown,
        22 => .success,
        23 => .fail_invalid,
        24 => .fail_fee,
        25 => .fail_balance,
        else => .unknown,
    };
}

fn intToChangeType(value: u32) StateChange.ChangeType {
    return switch (value) {
        1 => .account_balance,
        2 => .token_balance,
        3 => .contract_storage,
        4 => .file_content,
        else => .unknown,
    };
}
