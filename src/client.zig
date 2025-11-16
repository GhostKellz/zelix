//! Client for interacting with Hedera network

const std = @import("std");
const model = @import("model.zig");
const config = @import("config.zig");
const consensus = @import("consensus.zig");
const mirror = @import("mirror.zig");
const mirror_parse = @import("mirror_parse.zig");
const tx = @import("tx.zig");

pub const Client = struct {
    allocator: std.mem.Allocator,
    network: model.Network,
    mirror_client: mirror.MirrorClient,
    consensus_client: consensus.ConsensusClient,
    operator: ?config.Operator,

    pub const MirrorOverrides = struct {
        transport: mirror.Transport = .rest,
        base_url: ?[]const u8 = null,
        grpc_endpoint: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator, network: model.Network) !Client {
        return try initWithOverrides(allocator, network, .{});
    }

    pub fn initFromEnv(allocator: std.mem.Allocator) !Client {
        var cfg = try config.Config.loadFromEnv(allocator);
        defer cfg.deinit();
        var overrides = try loadMirrorOverridesFromEnv(allocator);
        defer overrides.deinit(allocator);
        return try initFromConfigWithOverrides(allocator, &cfg, overrides.values);
    }

    pub fn initFromConfigFile(allocator: std.mem.Allocator, path: []const u8) !Client {
        var cfg = try config.Config.loadFromFile(allocator, path);
        defer cfg.deinit();
        var overrides = try loadMirrorOverridesFromEnv(allocator);
        defer overrides.deinit(allocator);
        return try initFromConfigWithOverrides(allocator, &cfg, overrides.values);
    }

    pub fn initFromConfig(allocator: std.mem.Allocator, cfg: *const config.Config) !Client {
        return try initFromConfigWithOverrides(allocator, cfg, .{});
    }

    pub fn initWithOverrides(
        allocator: std.mem.Allocator,
        network: model.Network,
        overrides: MirrorOverrides,
    ) !Client {
        var cfg = try config.Config.forNetwork(allocator, network);
        defer cfg.deinit();

        if (overrides.base_url) |url| {
            try cfg.setMirrorUrl(url);
        }

        return try initFromConfigWithOverrides(allocator, &cfg, overrides);
    }

    fn initFromConfigWithOverrides(
        allocator: std.mem.Allocator,
        cfg: *const config.Config,
        overrides: MirrorOverrides,
    ) !Client {
        var mirror_client = try mirror.MirrorClient.initWithOptions(.{
            .allocator = allocator,
            .network = cfg.network,
            .base_url = overrides.base_url orelse cfg.mirror_url,
            .transport = overrides.transport,
            .grpc_endpoint = overrides.grpc_endpoint,
        });
        errdefer mirror_client.deinit();

        var consensus_client = try consensus.ConsensusClient.init(.{
            .allocator = allocator,
            .network = cfg.network,
            .nodes = cfg.nodes.items,
            .operator = cfg.operator,
        });
        errdefer consensus_client.deinit();

        mirror_client.setGrpcPayloadLogging(cfg.grpc_debug_payloads);
        consensus_client.setGrpcPayloadLogging(cfg.grpc_debug_payloads);

        return .{
            .allocator = allocator,
            .network = cfg.network,
            .mirror_client = mirror_client,
            .consensus_client = consensus_client,
            .operator = cfg.operator,
        };
    }

    const MirrorOverrideHandles = struct {
        values: MirrorOverrides,
        base_url: ?[]u8 = null,
        grpc_endpoint: ?[]u8 = null,

        fn deinit(self: *MirrorOverrideHandles, allocator: std.mem.Allocator) void {
            if (self.base_url) |buf| allocator.free(buf);
            self.base_url = null;
            if (self.grpc_endpoint) |buf| allocator.free(buf);
            self.grpc_endpoint = null;
        }
    };

    fn loadMirrorOverridesFromEnv(allocator: std.mem.Allocator) !MirrorOverrideHandles {
        var handles = MirrorOverrideHandles{ .values = .{} };

        if (std.process.getEnvVarOwned(allocator, "ZELIX_MIRROR_TRANSPORT")) |transport_raw| {
            defer allocator.free(transport_raw);
            if (std.ascii.eqlIgnoreCase(transport_raw, "grpc")) {
                handles.values.transport = .grpc;
            } else if (std.ascii.eqlIgnoreCase(transport_raw, "rest")) {
                handles.values.transport = .rest;
            }
        } else |err| switch (err) {
            error.EnvironmentVariableNotFound => {},
            else => return err,
        }

        if (std.process.getEnvVarOwned(allocator, "ZELIX_MIRROR_BASE_URL")) |base_url| {
            handles.base_url = base_url;
            handles.values.base_url = base_url;
        } else |err| switch (err) {
            error.EnvironmentVariableNotFound => {},
            else => return err,
        }

        if (std.process.getEnvVarOwned(allocator, "ZELIX_MIRROR_GRPC_ENDPOINT")) |endpoint| {
            handles.grpc_endpoint = endpoint;
            handles.values.grpc_endpoint = endpoint;
        } else |err| switch (err) {
            error.EnvironmentVariableNotFound => {},
            else => return err,
        }

        return handles;
    }

    pub fn deinit(self: *Client) void {
        self.consensus_client.deinit();
        self.mirror_client.deinit();
    }

    pub fn getAccountBalance(self: *Client, account_id: model.AccountId) !model.Hbar {
        return try self.mirror_client.getAccountBalance(account_id);
    }

    pub fn getAccountInfo(self: *Client, account_id: model.AccountId) !model.AccountInfo {
        var detailed = try self.mirror_client.getAccountInfoDetailed(account_id);
        defer detailed.allowances.deinit(self.allocator);
        return detailed.info;
    }

    pub fn getAccountRecords(self: *Client, account_id: model.AccountId) !model.AccountRecords {
        const body = try self.mirror_client.getJson("{s}/accounts/{d}.{d}.{d}/transactions", .{
            self.mirror_client.base_url,
            account_id.shard,
            account_id.realm,
            account_id.num,
        });
        defer self.allocator.free(body);
        return try mirror_parse.parseAccountRecords(self.allocator, body);
    }

    pub fn getTokenInfo(self: *Client, token_id: model.TokenId) !model.TokenInfo {
        return try self.mirror_client.getTokenInfo(token_id);
    }

    pub fn getTokenBalances(self: *Client, account_id: model.AccountId) !model.TokenBalances {
        const body = try self.mirror_client.getJson("{s}/accounts/{d}.{d}.{d}/tokens", .{
            self.mirror_client.base_url,
            account_id.shard,
            account_id.realm,
            account_id.num,
        });
        defer self.allocator.free(body);
        return try mirror_parse.parseTokenBalances(self.allocator, body);
    }

    pub fn getNftInfo(self: *Client, token_id: model.TokenId, serial: u64) !model.NftInfo {
        return try self.mirror_client.getNftInfo(token_id, serial);
    }

    pub fn getTokenAllowances(
        self: *Client,
        account_id: model.AccountId,
        options: mirror.MirrorClient.TokenAllowanceQueryOptions,
    ) !model.TokenAllowancesPage {
        return try self.mirror_client.getTokenAllowances(account_id, options);
    }

    pub fn getTokenNftAllowances(
        self: *Client,
        account_id: model.AccountId,
        options: mirror.MirrorClient.TokenNftAllowanceQueryOptions,
    ) !model.TokenNftAllowancesPage {
        return try self.mirror_client.getTokenNftAllowances(account_id, options);
    }

    pub fn getFileContents(self: *Client, file_id: model.FileId) ![]u8 {
        return try self.mirror_client.getFileContents(file_id);
    }

    pub fn getContractInfo(self: *Client, contract_id: model.ContractId) !model.ContractInfo {
        const body = try self.mirror_client.getJson("{s}/contracts/{d}.{d}.{d}", .{
            self.mirror_client.base_url,
            contract_id.shard,
            contract_id.realm,
            contract_id.num,
        });
        defer self.allocator.free(body);
        return try mirror_parse.parseContractInfo(self.allocator, body, contract_id);
    }

    pub fn contractCall(
        self: *Client,
        contract_id: model.ContractId,
        gas: u64,
        function_parameters: ?model.ContractFunctionParameters,
        sender_account_id: ?model.AccountId,
    ) !model.ContractFunctionResult {
        _ = self;
        _ = gas;
        _ = function_parameters;
        _ = sender_account_id;
        return model.ContractFunctionResult{
            .contract_id = contract_id,
            .contract_call_result = "",
            .gas_used = 0,
        };
    }

    pub fn submitTransaction(self: *Client, tx_bytes: []const u8) !model.TransactionResponse {
        return try self.consensus_client.submitTransaction(tx_bytes);
    }

    pub fn submitTopicMessage(self: *Client, transaction: *tx.TopicMessageSubmitTransaction) !model.TransactionResponse {
        return try self.consensus_client.submitTopicMessage(transaction);
    }

    pub fn getTransactionReceipt(self: *Client, transaction_id: model.TransactionId) !model.TransactionReceipt {
        return try self.getTransactionReceiptWithMirrorOptions(transaction_id, .{});
    }

    pub fn getTransactionReceiptWithMirrorOptions(
        self: *Client,
        transaction_id: model.TransactionId,
        options: mirror.MirrorClient.TransactionReceiptQueryOptions,
    ) !model.TransactionReceipt {
        var receipt = try self.mirror_client.getTransactionReceipt(transaction_id, options);
        if (receipt.status == model.TransactionStatus.unknown) {
            const info = try self.mirror_client.waitForTransaction(transaction_id, 30_000);
            receipt.status = if (info.successful) model.TransactionStatus.success else model.TransactionStatus.failed;
            receipt.transaction_id = info.transaction_id;
        }
        return receipt;
    }

    pub fn getTransactionReceiptWithOptions(
        self: *Client,
        transaction_id: model.TransactionId,
        options: consensus.ConsensusClient.ReceiptOptions,
    ) !model.TransactionReceipt {
        return try self.consensus_client.getTransactionReceiptWithOptions(transaction_id, options);
    }

    pub fn getTransactionRecord(self: *Client, transaction_id: model.TransactionId) !model.TransactionRecord {
        return try self.getTransactionRecordWithMirrorOptions(transaction_id, .{});
    }

    pub fn getTransactionRecordWithMirrorOptions(
        self: *Client,
        transaction_id: model.TransactionId,
        options: mirror.MirrorClient.TransactionRecordQueryOptions,
    ) !model.TransactionRecord {
        return try self.mirror_client.getTransactionRecord(transaction_id, options);
    }

    pub fn getScheduleInfo(self: *Client, schedule_id: model.ScheduleId) !model.ScheduleInfo {
        return try self.consensus_client.getScheduleInfo(schedule_id);
    }
};
