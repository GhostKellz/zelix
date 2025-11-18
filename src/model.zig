//! Core model types for Zelix Hedera SDK

const std = @import("std");
const crypto = @import("crypto.zig");

fn freeConstSlice(allocator: std.mem.Allocator, slice: []const u8) void {
    if (slice.len == 0) return;
    allocator.free(@constCast(slice));
}

fn freeOptionalConstSlice(allocator: std.mem.Allocator, slice: ?[]const u8) void {
    if (slice) |s| freeConstSlice(allocator, s);
}

// Entity IDs: AccountId, TokenId, etc.

pub const EntityId = struct {
    shard: u64,
    realm: u64,
    num: u64,

    pub fn init(shard: u64, realm: u64, num: u64) EntityId {
        return .{ .shard = shard, .realm = realm, .num = num };
    }

    pub fn fromString(str: []const u8) !EntityId {
        var parts = std.mem.splitSequence(u8, str, ".");
        const shard_str = parts.next() orelse return error.InvalidFormat;
        const realm_str = parts.next() orelse return error.InvalidFormat;
        const num_str = parts.next() orelse return error.InvalidFormat;
        if (parts.next() != null) return error.InvalidFormat;

        const shard = try std.fmt.parseInt(u64, shard_str, 10);
        const realm = try std.fmt.parseInt(u64, realm_str, 10);
        const num = try std.fmt.parseInt(u64, num_str, 10);

        return init(shard, realm, num);
    }

    pub fn format(self: EntityId, comptime fmt: []const u8, options: anytype, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d}.{d}.{d}", .{ self.shard, self.realm, self.num });
    }

    pub fn toString(self: EntityId, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{}", .{self});
    }
};

pub const AccountId = EntityId;
pub const TokenId = EntityId;
pub const ContractId = EntityId;
pub const TopicId = EntityId;
pub const FileId = EntityId;
pub const ScheduleId = EntityId;

// Timestamp
pub const Timestamp = struct {
    seconds: i64,
    nanos: i64,

    pub fn now() Timestamp {
        // const instant = std.time.Instant.now() catch @panic("time failed");
        // const now_ns = instant.timestamp.tv_sec * std.time.ns_per_s + instant.timestamp.tv_nsec;
        const now_ns = 1700000000000000000; // dummy
        const seconds = @divFloor(now_ns, std.time.ns_per_s);
        const nanos = @mod(now_ns, std.time.ns_per_s);
        return .{ .seconds = seconds, .nanos = nanos };
    }

    pub fn format(self: Timestamp, comptime fmt: []const u8, options: anytype, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d}.{d}", .{ self.seconds, self.nanos });
    }

    pub fn fromString(raw: []const u8) !Timestamp {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len == 0) return error.InvalidFormat;

        if (std.mem.indexOfScalar(u8, trimmed, '.')) |dot| {
            const seconds_part = trimmed[0..dot];
            const nanos_part = trimmed[dot + 1 ..];
            if (nanos_part.len == 0) return error.InvalidFormat;

            const seconds = try std.fmt.parseInt(i64, seconds_part, 10);
            const nanos = try std.fmt.parseInt(i64, nanos_part, 10);
            if (nanos < 0 or nanos >= std.time.ns_per_s) return error.InvalidFormat;
            return .{ .seconds = seconds, .nanos = nanos };
        } else {
            const seconds = try std.fmt.parseInt(i64, trimmed, 10);
            return .{ .seconds = seconds, .nanos = 0 };
        }
    }
};

// TransactionId
pub const TransactionId = struct {
    account_id: AccountId,
    valid_start: Timestamp,
    nonce: ?i32 = null,
    scheduled: bool = false,

    pub fn init(account_id: AccountId, valid_start: Timestamp) TransactionId {
        return .{ .account_id = account_id, .valid_start = valid_start };
    }

    pub fn generate(account_id: AccountId) TransactionId {
        // Add some random offset like Rust does
        const offset_ns: i64 = 6_000_000_000;
        const now = Timestamp.now();
        const valid_start = Timestamp{
            .seconds = now.seconds,
            .nanos = now.nanos - offset_ns,
        };
        return init(account_id, valid_start);
    }

    pub fn format(self: TransactionId, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{}@{}.{}", .{ self.account_id, self.valid_start.seconds, self.valid_start.nanos });
    }

    pub fn parse(str: []const u8) !TransactionId {
        if (str.len == 0) return error.InvalidFormat;

        if (std.mem.indexOfScalar(u8, str, '@')) |at| {
            const account_part = str[0..at];
            const timestamp_part = str[at + 1 ..];
            _ = std.mem.indexOfScalar(u8, timestamp_part, '.') orelse return error.InvalidFormat;
            const account_id = try AccountId.fromString(account_part);
            const timestamp = try Timestamp.fromString(timestamp_part);
            return .{ .account_id = account_id, .valid_start = timestamp };
        }

        var parts = std.mem.splitScalar(u8, str, '-');
        const account_str = parts.next() orelse return error.InvalidFormat;
        const seconds_str = parts.next() orelse return error.InvalidFormat;
        const nanos_str = parts.next() orelse return error.InvalidFormat;
        if (parts.next() != null) return error.InvalidFormat;

        const account_id = try AccountId.fromString(account_str);
        const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
        const nanos = try std.fmt.parseInt(i64, nanos_str, 10);
        if (nanos < 0 or nanos >= std.time.ns_per_s) return error.InvalidFormat;
        return .{ .account_id = account_id, .valid_start = .{ .seconds = seconds, .nanos = nanos } };
    }
};

// Hbar
pub const Hbar = struct {
    tinybars: i64,

    pub const ZERO = Hbar{ .tinybars = 0 };
    pub const HBAR_IN_TINYBARS = 100_000_000;

    pub fn fromTinybars(tinybars: i64) Hbar {
        return .{ .tinybars = tinybars };
    }

    pub fn fromHbars(hbars: i64) Hbar {
        return .{ .tinybars = hbars * HBAR_IN_TINYBARS };
    }

    pub fn toTinybars(self: Hbar) i64 {
        return self.tinybars;
    }

    // pub fn toHbars(self: Hbar) f64 {
    //     return @floatFromInt(self.tinybars) / 100_000_000.0;
    // }

    pub fn format(self: Hbar, writer: anytype) !void {
        try writer.print("{d}", .{self.tinybars});
    }
};

// Network
pub const Network = enum {
    mainnet,
    testnet,
    previewnet,
    custom,
};

// Errors
pub const HelixError = error{
    Network,
    Decode,
    Sign,
    InvalidId,
    Unsupported,
};

// Account Info
pub const AccountInfo = struct {
    account_id: AccountId,
    alias_key: ?[]const u8 = null,
    contract_account_id: ?[]const u8 = null,
    deleted: bool = false,
    expiry_timestamp: ?Timestamp = null,
    key: ?crypto.PublicKey = null,
    auto_renew_period: ?i64 = null,
    memo: []const u8 = "",
    owned_nfts: u64 = 0,
    max_automatic_token_associations: u32 = 0,
    receiver_sig_required: bool = false,
    ethereum_nonce: i64 = 0,
    staking_info: ?StakingInfo = null,

    pub fn deinit(self: *AccountInfo, allocator: std.mem.Allocator) void {
        freeOptionalConstSlice(allocator, self.alias_key);
        self.alias_key = null;
        freeOptionalConstSlice(allocator, self.contract_account_id);
        self.contract_account_id = null;
        freeConstSlice(allocator, self.memo);
        self.memo = "";
        self.staking_info = null;
    }
};

pub const StakingInfo = struct {
    decline_staking_reward: bool = false,
    stake_period_start: ?Timestamp = null,
    pending_reward: u64 = 0,
    staked_to_me: u64 = 0,
    staked_account_id: ?AccountId = null,
    staked_node_id: ?u64 = null,
};

// Account Records
pub const AccountRecords = struct {
    records: []TransactionRecord,

    pub fn deinit(self: *AccountRecords, allocator: std.mem.Allocator) void {
        for (self.records) |*record| record.deinit(allocator);
        if (self.records.len > 0) allocator.free(self.records);
        self.records = @constCast((&[_]TransactionRecord{})[0..]);
    }
};

pub const TransactionRecord = struct {
    transaction_hash: []const u8,
    consensus_timestamp: Timestamp,
    transaction_id: TransactionId,
    memo: []const u8 = "",
    transaction_fee: Hbar,
    transfer_list: []Transfer,
    duplicates: []TransactionRecord = @constCast((&[_]TransactionRecord{})[0..]),
    children: []TransactionRecord = @constCast((&[_]TransactionRecord{})[0..]),

    pub fn deinit(self: *TransactionRecord, allocator: std.mem.Allocator) void {
        freeConstSlice(allocator, self.transaction_hash);
        self.transaction_hash = "";
        freeConstSlice(allocator, self.memo);
        self.memo = "";
        if (self.transfer_list.len > 0) allocator.free(self.transfer_list);
        self.transfer_list = @constCast((&[_]Transfer{})[0..]);
        for (self.duplicates) |*record| record.deinit(allocator);
        if (self.duplicates.len > 0) allocator.free(self.duplicates);
        self.duplicates = @constCast((&[_]TransactionRecord{})[0..]);
        for (self.children) |*record| record.deinit(allocator);
        if (self.children.len > 0) allocator.free(self.children);
        self.children = @constCast((&[_]TransactionRecord{})[0..]);
    }
};

pub const Transfer = struct {
    account_id: AccountId,
    amount: Hbar,
    is_approval: bool = false,
};

pub const TransactionReceipt = struct {
    status: TransactionStatus,
    transaction_id: TransactionId,
    account_id: ?AccountId = null,
    file_id: ?FileId = null,
    contract_id: ?ContractId = null,
    topic_id: ?TopicId = null,
    token_id: ?TokenId = null,
    schedule_id: ?ScheduleId = null,
    scheduled_transaction_id: ?TransactionId = null,
    serial_numbers: std.ArrayList(i64) = .{},
    duplicates: std.ArrayList(TransactionReceipt) = .{},
    children: std.ArrayList(TransactionReceipt) = .{},

    pub fn deinit(self: *TransactionReceipt, allocator: std.mem.Allocator) void {
        self.serial_numbers.deinit(allocator);
        for (self.duplicates.items) |*dup| {
            dup.deinit(allocator);
        }
        self.duplicates.deinit(allocator);
        for (self.children.items) |*child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
    }
};

pub const TransactionResponse = struct {
    transaction_id: ?TransactionId = null,
    node_id: ?AccountId = null,
    status: []u8 = "",
    hash: ?[]u8 = null,
    status_code: u16 = 0,
    error_message: ?[]u8 = null,
    success: bool = false,

    pub fn deinit(self: *TransactionResponse, allocator: std.mem.Allocator) void {
        if (self.status.len > 0) allocator.free(self.status);
        self.status = "";
        if (self.hash) |h| allocator.free(h);
        self.hash = null;
        if (self.error_message) |msg| allocator.free(msg);
        self.error_message = null;
    }
};

pub const ScheduleInfo = struct {
    schedule_id: ScheduleId,
    memo: []const u8 = "",
    creator_account_id: ?AccountId = null,
    payer_account_id: ?AccountId = null,
    expiration_time: ?Timestamp = null,
    execution_time: ?Timestamp = null,
    deletion_time: ?Timestamp = null,
    scheduled_transaction_id: ?TransactionId = null,
    ledger_id: ?[]const u8 = null,
    wait_for_expiry: bool = false,

    pub fn deinit(self: *ScheduleInfo, allocator: std.mem.Allocator) void {
        freeConstSlice(allocator, self.memo);
        self.memo = "";
        if (self.ledger_id) |bytes| allocator.free(bytes);
        self.ledger_id = null;
    }
};

test "TransactionId parsing" {
    const id1 = try TransactionId.parse("0.0.123@1700000000.42");
    try std.testing.expectEqual(@as(u64, 0), id1.account_id.shard);
    try std.testing.expectEqual(@as(i64, 1700000000), id1.valid_start.seconds);
    try std.testing.expectEqual(@as(i64, 42), id1.valid_start.nanos);

    const id2 = try TransactionId.parse("0.0.500-1700000001-84");
    try std.testing.expectEqual(@as(u64, 500), id2.account_id.num);
    try std.testing.expectEqual(@as(i64, 1700000001), id2.valid_start.seconds);
    try std.testing.expectEqual(@as(i64, 84), id2.valid_start.nanos);

    try std.testing.expectError(error.InvalidFormat, TransactionId.parse(""));
}

test "Timestamp fromString" {
    const ts1 = try Timestamp.fromString("1700000000.42");
    try std.testing.expectEqual(@as(i64, 1700000000), ts1.seconds);
    try std.testing.expectEqual(@as(i64, 42), ts1.nanos);

    const ts2 = try Timestamp.fromString("1700000001");
    try std.testing.expectEqual(@as(i64, 1700000001), ts2.seconds);
    try std.testing.expectEqual(@as(i64, 0), ts2.nanos);

    try std.testing.expectError(error.InvalidFormat, Timestamp.fromString(""));
    try std.testing.expectError(error.InvalidFormat, Timestamp.fromString("1700."));
    try std.testing.expectError(error.InvalidFormat, Timestamp.fromString("1700.-10"));
    try std.testing.expectError(error.InvalidFormat, Timestamp.fromString("1700.2000000000"));
}

pub const TransactionStatus = enum {
    success,
    failed,
    unknown,
    // TODO: Add more status codes from Hedera
};

// Token Types
pub const TokenType = enum {
    fungible_common,
    non_fungible_unique,
};

pub const TokenSupplyType = enum {
    infinite,
    finite,
};

pub const TokenInfo = struct {
    token_id: TokenId,
    name: []const u8,
    symbol: []const u8,
    decimals: u32,
    total_supply: u64,
    treasury_account_id: AccountId,
    admin_key: ?crypto.PublicKey = null,
    kyc_key: ?crypto.PublicKey = null,
    freeze_key: ?crypto.PublicKey = null,
    wipe_key: ?crypto.PublicKey = null,
    supply_key: ?crypto.PublicKey = null,
    fee_schedule_key: ?crypto.PublicKey = null,
    pause_key: ?crypto.PublicKey = null,
    token_type: TokenType,
    supply_type: TokenSupplyType,
    max_supply: ?u64 = null,
    freeze_default: bool = false,
    pause_status: bool = false,
    deleted: bool = false,
    expiry_timestamp: ?Timestamp = null,
    auto_renew_period: ?i64 = null,
    auto_renew_account_id: ?AccountId = null,
    memo: []const u8 = "",
    custom_fees: []CustomFee = &.{},

    pub fn deinit(self: *TokenInfo, allocator: std.mem.Allocator) void {
        freeConstSlice(allocator, self.name);
        self.name = "";
        freeConstSlice(allocator, self.symbol);
        self.symbol = "";
        freeConstSlice(allocator, self.memo);
        self.memo = "";
        if (self.custom_fees.len > 0) allocator.free(self.custom_fees);
        self.custom_fees = @constCast((&[_]CustomFee{})[0..]);
    }
};

pub const NftId = struct {
    token_id: TokenId,
    serial: u64,

    pub fn init(token_id: TokenId, serial: u64) NftId {
        return .{ .token_id = token_id, .serial = serial };
    }

    pub fn format(self: NftId, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{}.{}", .{ self.token_id, self.serial });
    }
};

pub const NftInfo = struct {
    id: NftId,
    owner_account_id: AccountId,
    spender_account_id: ?AccountId = null,
    delegating_spender_account_id: ?AccountId = null,
    created_timestamp: Timestamp,
    modified_timestamp: ?Timestamp = null,
    metadata: []const u8,
    ledger_id: ?[]const u8 = null,
    deleted: bool = false,

    pub fn deinit(self: *NftInfo, allocator: std.mem.Allocator) void {
        freeConstSlice(allocator, self.metadata);
        self.metadata = "";
        freeOptionalConstSlice(allocator, self.ledger_id);
        self.ledger_id = null;
    }
};

pub const CryptoAllowance = struct {
    owner_account_id: AccountId,
    spender_account_id: AccountId,
    amount: Hbar,
    timestamp: ?Timestamp = null,
};

pub const TokenAllowance = struct {
    owner_account_id: AccountId,
    spender_account_id: AccountId,
    token_id: TokenId,
    amount: u64,
    timestamp: ?Timestamp = null,
};

pub const TokenAllowancesPage = struct {
    allowances: []TokenAllowance,
    next: ?[]u8,

    pub fn deinit(self: *TokenAllowancesPage, allocator: std.mem.Allocator) void {
        if (self.allowances.len > 0) allocator.free(self.allowances);
        self.allowances = @constCast((&[_]TokenAllowance{})[0..]);
        if (self.next) |token| allocator.free(token);
        self.next = null;
    }
};

pub const TokenNftAllowance = struct {
    owner_account_id: AccountId,
    spender_account_id: AccountId,
    token_id: TokenId,
    serial_numbers: []u64,
    approved_for_all: bool = false,
    timestamp: ?Timestamp = null,

    pub fn deinit(self: *TokenNftAllowance, allocator: std.mem.Allocator) void {
        if (self.serial_numbers.len > 0) allocator.free(self.serial_numbers);
        self.serial_numbers = @constCast((&[_]u64{})[0..]);
    }
};

pub const TokenNftAllowancesPage = struct {
    allowances: []TokenNftAllowance,
    next: ?[]u8,

    pub fn deinit(self: *TokenNftAllowancesPage, allocator: std.mem.Allocator) void {
        for (self.allowances) |*allowance| allowance.deinit(allocator);
        if (self.allowances.len > 0) allocator.free(self.allowances);
        self.allowances = @constCast((&[_]TokenNftAllowance{})[0..]);
        if (self.next) |token| allocator.free(token);
        self.next = null;
    }
};

pub const AccountAllowances = struct {
    crypto: []CryptoAllowance,
    token: []TokenAllowance,
    nft: []TokenNftAllowance,

    pub fn empty() AccountAllowances {
        return .{
            .crypto = @constCast((&[_]CryptoAllowance{})[0..]),
            .token = @constCast((&[_]TokenAllowance{})[0..]),
            .nft = @constCast((&[_]TokenNftAllowance{})[0..]),
        };
    }

    pub fn deinit(self: *AccountAllowances, allocator: std.mem.Allocator) void {
        if (self.crypto.len > 0) allocator.free(self.crypto);
        self.crypto = @constCast((&[_]CryptoAllowance{})[0..]);
        if (self.token.len > 0) allocator.free(self.token);
        self.token = @constCast((&[_]TokenAllowance{})[0..]);
        for (self.nft) |*allowance| allowance.deinit(allocator);
        if (self.nft.len > 0) allocator.free(self.nft);
        self.nft = @constCast((&[_]TokenNftAllowance{})[0..]);
    }
};

pub const CustomFee = union(enum) {
    fixed_fee: FixedFee,
    fractional_fee: FractionalFee,
    royalty_fee: RoyaltyFee,
};

pub const FixedFee = struct {
    amount: u64,
    denominating_token_id: ?TokenId = null,
    fee_collector_account_id: ?AccountId = null,
};

pub const FractionalFee = struct {
    numerator: u64,
    denominator: u64,
    minimum_amount: u64 = 0,
    maximum_amount: u64 = 0,
    assessment_method: bool = false, // false = receiver, true = sender
    fee_collector_account_id: ?AccountId = null,
};

pub const RoyaltyFee = struct {
    numerator: u64,
    denominator: u64,
    fallback_fee: ?FixedFee = null,
    fee_collector_account_id: ?AccountId = null,
};

pub const TokenBalance = struct {
    token_id: TokenId,
    balance: u64,
    decimals: u32,
};

pub const TokenBalances = struct {
    balances: []TokenBalance,

    pub fn deinit(self: *TokenBalances, allocator: std.mem.Allocator) void {
        if (self.balances.len > 0) allocator.free(self.balances);
        self.balances = @constCast((&[_]TokenBalance{})[0..]);
    }
};

pub const TokenAssociation = struct {
    token_id: TokenId,
    account_id: AccountId,
    balance: u64,
    frozen: bool = false,
    kyc_granted: bool = true,
};

// Contract Types
pub const ContractInfo = struct {
    contract_id: ContractId,
    account_id: AccountId, // The account ID associated with the contract
    contract_account_id: ?[]const u8 = null,
    admin_key: ?crypto.PublicKey = null,
    initcode: []const u8 = "",
    bytecode: []const u8 = "",
    expiry_timestamp: ?Timestamp = null,
    auto_renew_period: ?i64 = null,
    auto_renew_account_id: ?AccountId = null,
    memo: []const u8 = "",
    max_automatic_token_associations: u32 = 0,
    ethereum_nonce: i64 = 0,
    staking_info: ?StakingInfo = null,

    pub fn deinit(self: *ContractInfo, allocator: std.mem.Allocator) void {
        freeOptionalConstSlice(allocator, self.contract_account_id);
        self.contract_account_id = null;
        freeConstSlice(allocator, self.initcode);
        self.initcode = "";
        freeConstSlice(allocator, self.bytecode);
        self.bytecode = "";
        freeConstSlice(allocator, self.memo);
        self.memo = "";
        self.staking_info = null;
    }
};

pub const ContractFunctionParameters = struct {
    data: []const u8,

    pub fn init(data: []const u8) ContractFunctionParameters {
        return .{ .data = data };
    }

    pub fn fromString(str: []const u8) ContractFunctionParameters {
        return .{ .data = str };
    }

    // TODO: Add ABI encoding/decoding helpers
};

pub const ContractFunctionResult = struct {
    contract_id: ContractId,
    contract_call_result: []const u8,
    error_message: ?[]const u8 = null,
    bloom: []const u8 = "",
    gas_used: u64 = 0,
    gas: u64 = 0,
    hbar_amount: Hbar = Hbar.ZERO,
    function_parameters: []const u8 = "",
    sender_account_id: ?AccountId = null,

    pub fn deinit(self: *ContractFunctionResult, allocator: std.mem.Allocator) void {
        freeConstSlice(allocator, self.contract_call_result);
        self.contract_call_result = "";
        freeOptionalConstSlice(allocator, self.error_message);
        self.error_message = null;
        freeConstSlice(allocator, self.bloom);
        self.bloom = "";
        freeConstSlice(allocator, self.function_parameters);
        self.function_parameters = "";
    }
};

test "AccountId parsing" {
    const id = try AccountId.fromString("0.0.123");
    try std.testing.expectEqual(@as(u64, 0), id.shard);
    try std.testing.expectEqual(@as(u64, 0), id.realm);
    try std.testing.expectEqual(@as(u64, 123), id.num);

    // var buf: [64]u8 = undefined;
    // const str = try id.toString(std.testing.allocator, &buf);
    // defer std.testing.allocator.free(str);
    // try std.testing.expectEqualStrings("0.0.123", str);
}

test "Hbar math" {
    const hbar = Hbar.fromHbars(1);
    try std.testing.expectEqual(@as(i64, 100_000_000), hbar.toTinybars());
    // const hbar2 = Hbar.fromTinybars(250);
    // try std.testing.expectEqual(@as(f64, 0.0000025), hbar2.toHbars());
}

test "TransactionId generation" {
    const account_id = AccountId.init(0, 0, 123);
    const tx_id = TransactionId.generate(account_id);
    try std.testing.expectEqual(account_id, tx_id.account_id);
    try std.testing.expect(tx_id.valid_start.seconds > 0);
}
