//! Consensus network client for transaction submission

const std = @import("std");
const model = @import("model.zig");
const config = @import("config.zig");
const tx = @import("tx.zig");
const grpc_web = @import("grpc_web.zig");
const consensus_proto = @import("consensus_proto.zig");

const base64 = std.base64;
const json = std.json;
const math = std.math;
const log = std.log.scoped(.consensus);

// Protobuf message definitions (simplified for demonstration)
// In a real implementation, these would be generated from .proto files
pub const Transaction = struct {
    // Protobuf fields would be defined here
    body: TransactionBody,
    sigs: []SignaturePair,

    pub const TransactionBody = struct {
        transaction_id: model.TransactionId,
        node_account_id: ?model.AccountId = null,
        transaction_fee: model.Hbar,
        transaction_valid_duration: i64,
        generate_record: bool = false,
        memo: []const u8 = "",
        data: TransactionData,
    };

    pub const TransactionData = union(enum) {
        crypto_create_account: CryptoCreateAccountTransactionBody,
        crypto_transfer: CryptoTransferTransactionBody,
        token_create: TokenCreateTransactionBody,
        contract_create_instance: ContractCreateInstanceTransactionBody,
        // ... other transaction types
    };

    pub const CryptoCreateAccountTransactionBody = struct {
        key: ?[]const u8 = null, // Serialized public key
        initial_balance: u64,
        proxy_account_id: ?model.AccountId = null,
        send_record_threshold: u64 = 0,
        receive_record_threshold: u64 = 0,
        receiver_sig_required: bool = false,
        auto_renew_period: ?i64 = null,
        shard_id: ?u64 = null,
        realm_id: ?u64 = null,
        new_realm_admin_key: ?[]const u8 = null,
    };

    pub const CryptoTransferTransactionBody = struct {
        transfers: []Transfer,
    };

    pub const Transfer = struct {
        account_id: model.AccountId,
        amount: i64,
        is_approval: bool = false,
    };

    pub const TokenCreateTransactionBody = struct {
        name: []const u8,
        symbol: []const u8,
        decimals: u32,
        initial_supply: u64,
        treasury: model.AccountId,
        admin_key: ?[]const u8 = null,
        kyc_key: ?[]const u8 = null,
        freeze_key: ?[]const u8 = null,
        wipe_key: ?[]const u8 = null,
        supply_key: ?[]const u8 = null,
        freeze_default: bool = false,
        expiry: ?i64 = null,
        auto_renew_account: ?model.AccountId = null,
        auto_renew_period: ?i64 = null,
        memo: []const u8 = "",
        token_supply_type: model.TokenSupplyType = .infinite,
        max_supply: ?u64 = null,
        fee_schedule_key: ?[]const u8 = null,
        custom_fees: []model.CustomFee = &.{},
        pause_key: ?[]const u8 = null,
    };

    pub const ContractCreateInstanceTransactionBody = struct {
        initcode: []const u8,
        gas: i64,
        initial_balance: u64,
        proxy_account_id: ?model.AccountId = null,
        auto_renew_period: ?i64 = null,
        constructor_parameters: ?[]const u8 = null,
        shard_id: ?u64 = null,
        realm_id: ?u64 = null,
        new_realm_admin_key: ?[]const u8 = null,
        memo: []const u8 = "",
        max_automatic_token_associations: ?i32 = null,
        decline_reward: bool = false,
        auto_renew_account_id: ?model.AccountId = null,
        staked_account_id: ?model.AccountId = null,
        staked_node_id: ?i64 = null,
    };
};

pub const SignaturePair = struct {
    pub_key_prefix: []const u8,
    signature: []const u8, // ED25519 signature bytes
};

pub const ResponseCodeEnum = enum {
    ok,
    invalid_transaction,
    payer_account_not_found,
    invalid_node_account,
    transaction_expired,
    invalid_transaction_start,
    invalid_transaction_duration,
    invalid_signature,
    memo_too_long,
    insufficient_tx_fee,
    insufficient_payer_balance,
    duplicate_transaction,
    busy,
    not_supported,
    invalid_file_id,
    invalid_account_id,
    invalid_contract_id,
    invalid_transaction_id,
    receipt_not_found,
    record_not_found,
    invalid_solidity_id,
    unknown,
    success,
    fail_invalid,
    fail_fee,
    fail_balance,
    key_required,
    bad_encoding,
    insufficient_account_balance,
    incorrect_size,
    invalid_max_results,
    not_admin,
    platform_not_active,
    max_entities_in_price_regime_have_been_created,
    invalid_node_account_duplicate, // Renamed to avoid duplicate
    account_deleted,
    file_deleted,
    account_repeated_in_account_amounts,
    setting_negative_account_balance,
    obtainer_required,
    obtainer_same_contract_id,
    obtainer_does_not_exist,
    modifying_immutable_contract,
    file_system_exception,
    autonomy_only,
    consensus_submit_message_invalid,
    invalid_ethereum_transaction,
    wrong_chain_id,
    ethereum_transaction_unsigned,
    ethereum_transaction_wrong_account_id,
    ethereum_transaction_wrong_contract_id,
    invalid_fee_submitted,
    invalid_payer_signature,
    key_not_provided,
    invalid_expiration_time,
    ethereum_transaction_inaccessible_sender_account,
    ethereum_transaction_wrong_nonce,
    ethereum_access_list_invalid,
    migration_not_allowed,
    account_id_does_not_exist,
    contract_id_does_not_exist,
    invalid_signature_type_mismatch,
    invalid_signature_count_mismatch,
};

pub const ResponseType = enum {
    answer_only,
    answer_state_proof,
    cost_answer,
    cost_answer_state_proof,
};

pub const Query = struct {
    query: QueryData,

    pub const QueryData = union(enum) {
        transaction_get_receipt: TransactionGetReceiptQuery,
        transaction_get_record: TransactionGetRecordQuery,
        schedule_get_info: ScheduleGetInfoQuery,
        // ... other query types
    };
};

pub const TransactionGetReceiptQuery = struct {
    transaction_id: model.TransactionId,
    include_duplicates: bool = false,
};

pub const TransactionGetRecordQuery = struct {
    transaction_id: model.TransactionId,
    include_duplicates: bool = false,
};

pub const ScheduleGetInfoQuery = struct {
    schedule_id: model.ScheduleId,
};

pub const QueryResponse = struct {
    response: QueryResponseData,

    pub const QueryResponseData = union(enum) {
        transaction_get_receipt: TransactionGetReceiptResponse,
        transaction_get_record: TransactionGetRecordResponse,
        schedule_get_info: ScheduleGetInfoResponse,
    };
};

pub const TransactionGetReceiptResponse = struct {
    receipt: model.TransactionReceipt,
};

pub const TransactionGetRecordResponse = struct {
    record: model.TransactionRecord,
};

pub const ScheduleGetInfoResponse = struct {
    info: model.ScheduleInfo,
};

pub const ConsensusClient = struct {
    allocator: std.mem.Allocator,
    network: model.Network,
    nodes: std.ArrayList(NodeEndpoint),
    next_index: usize,
    operator: ?config.Operator,
    submit_url: []u8,
    http_client: std.http.Client,
    threaded_io: std.Io.Threaded,
    receipt_max_wait_ns: u64,
    receipt_poll_interval_ns: u64,
    query_deadline_ns: u64,
    grpc_options: grpc_web.Options,
    node_failure_threshold: usize,
    node_cooldown_ns: u64,
    receipt_pending_attempts: usize,
    grpc_debug_payloads: bool = false,

    pub const InitOptions = struct {
        allocator: std.mem.Allocator,
        network: model.Network,
        nodes: []const config.Node,
        operator: ?config.Operator = null,
        submit_url: ?[]const u8 = null,
        receipt_max_wait_ns: u64 = 30 * std.time.ns_per_s,
        receipt_poll_interval_ns: u64 = 500 * std.time.ns_per_ms,
        query_deadline_ns: u64 = 10 * std.time.ns_per_s,
        grpc_max_retries: usize = 2,
        grpc_base_backoff_ns: u64 = 150 * std.time.ns_per_ms,
        grpc_max_backoff_ns: u64 = 3 * std.time.ns_per_s,
        node_failure_threshold: usize = 3,
        node_cooldown_ns: u64 = 5 * std.time.ns_per_s,
    };

    pub const GrpcSummary = struct {
        total_requests: usize = 0,
        total_retries: usize = 0,
        total_failures: usize = 0,
        last_latency_ns: u64 = 0,
        last_status_code: u32 = 0,
        last_http_status: u16 = 0,
    };

    pub const NodeEndpoint = struct {
        address: []u8,
        account_id: model.AccountId,
        healthy: bool = true,
        grpc_endpoint: ?[]u8 = null,
        grpc_client: ?grpc_web.GrpcWebClient = null,
        consecutive_failures: usize = 0,
        cooldown_until_ns: i128 = 0,
    };

    pub fn init(options: InitOptions) !ConsensusClient {
        var nodes = std.ArrayList(NodeEndpoint).empty;
        errdefer nodes.deinit(options.allocator);

        for (options.nodes) |node_cfg| {
            const copy = try options.allocator.dupe(u8, node_cfg.address);
            errdefer options.allocator.free(copy);
            try nodes.append(options.allocator, .{
                .address = copy,
                .account_id = node_cfg.account_id,
                .healthy = true,
                .grpc_endpoint = null,
                .grpc_client = null,
            });
        }

        if (options.receipt_max_wait_ns == 0) return error.InvalidReceiptTimeout;
        if (options.receipt_poll_interval_ns == 0) return error.InvalidPollInterval;

        var submit_url: []u8 = "";
        if (try determineSubmitUrl(options)) |url| {
            submit_url = url;
        }

        const sanitized_failure_threshold = if (options.node_failure_threshold == 0) 1 else options.node_failure_threshold;
        const grpc_options = grpc_web.Options{
            .max_retries = options.grpc_max_retries,
            .base_backoff_ns = options.grpc_base_backoff_ns,
            .max_backoff_ns = options.grpc_max_backoff_ns,
            .deadline_ns = null,
        };

        var result = ConsensusClient{
            .allocator = options.allocator,
            .network = options.network,
            .nodes = nodes,
            .next_index = 0,
            .operator = options.operator,
            .submit_url = submit_url,
            .http_client = undefined,
            .threaded_io = std.Io.Threaded.init(options.allocator),
            .receipt_max_wait_ns = options.receipt_max_wait_ns,
            .receipt_poll_interval_ns = options.receipt_poll_interval_ns,
            .query_deadline_ns = options.query_deadline_ns,
            .grpc_options = grpc_options,
            .node_failure_threshold = sanitized_failure_threshold,
            .node_cooldown_ns = options.node_cooldown_ns,
            .receipt_pending_attempts = 0,
            .grpc_debug_payloads = false,
        };
        result.http_client = std.http.Client{ .allocator = options.allocator, .io = result.threaded_io.io() };
        return result;
    }

    pub fn deinit(self: *ConsensusClient) void {
        self.http_client.deinit();
        if (self.submit_url.len > 0) self.allocator.free(self.submit_url);
        self.submit_url = "";
        for (self.nodes.items) |*node| {
            if (node.grpc_client) |*client| client.deinit();
            node.grpc_client = null;
            if (node.grpc_endpoint) |endpoint| self.allocator.free(endpoint);
            node.grpc_endpoint = null;
            if (node.address.len > 0) self.allocator.free(node.address);
            node.address = @constCast((&[_]u8{})[0..]);
        }
        self.nodes.deinit(self.allocator);
        self.next_index = 0;
        self.operator = null;
    }

    pub fn setGrpcPayloadLogging(self: *ConsensusClient, enable: bool) void {
        self.grpc_debug_payloads = enable;
        for (self.nodes.items) |*node| {
            if (node.grpc_client) |*client| {
                client.setDebugPayloadLogging(enable);
            }
        }
    }

    pub fn snapshotGrpcSummary(self: *const ConsensusClient) GrpcSummary {
        var summary: GrpcSummary = .{};
        for (self.nodes.items) |node| {
            if (node.grpc_client) |*client| {
                const stats = client.getStats();
                summary.total_requests += stats.total_requests;
                summary.total_retries += stats.total_retries;
                summary.total_failures += stats.total_failures;
                if (stats.last_latency_ns > summary.last_latency_ns) summary.last_latency_ns = stats.last_latency_ns;
                if (stats.last_status_code != 0) summary.last_status_code = stats.last_status_code;
                if (stats.last_http_status != 0) summary.last_http_status = stats.last_http_status;
            }
        }
        return summary;
    }

    fn selectNode(self: *ConsensusClient) !*NodeEndpoint {
        const count = self.nodes.items.len;
        if (count == 0) return error.NoNodesConfigured;

        const start_index = self.next_index;
        var checked: usize = 0;
        while (checked < count) : (checked += 1) {
            const idx = (start_index + checked) % count;
            const node = &self.nodes.items[idx];
            if (self.isNodeEligible(node)) {
                self.next_index = (idx + 1) % count;
                return node;
            }
        }

        return error.NoHealthyNodes;
    }

    fn isNodeEligible(self: *ConsensusClient, node: *NodeEndpoint) bool {
        if (!node.healthy) {
            if (self.node_cooldown_ns == 0) {
                node.consecutive_failures = 0;
                node.cooldown_until_ns = 0;
                node.healthy = true;
                return true;
            }

            const now = std.time.nanoTimestamp();
            if (now >= node.cooldown_until_ns) {
                node.consecutive_failures = 0;
                node.cooldown_until_ns = 0;
                node.healthy = true;
                return true;
            }
            return false;
        }
        return true;
    }

    fn registerNodeSuccess(_: *ConsensusClient, node: *NodeEndpoint) void {
        node.consecutive_failures = 0;
        node.cooldown_until_ns = 0;
        node.healthy = true;
    }

    fn registerNodeFailure(self: *ConsensusClient, node: *NodeEndpoint) void {
        node.consecutive_failures += 1;
        if (node.consecutive_failures >= self.node_failure_threshold) {
            self.applyCooldown(node);
        }
    }

    fn applyCooldown(self: *ConsensusClient, node: *NodeEndpoint) void {
        node.healthy = false;
        const now = std.time.nanoTimestamp();
        const delta: i128 = @intCast(self.node_cooldown_ns);
        node.cooldown_until_ns = now + delta;
        log.warn("marking node {d}.{d}.{d} unhealthy for {d} ms", .{
            node.account_id.shard,
            node.account_id.realm,
            node.account_id.num,
            self.node_cooldown_ns / std.time.ns_per_ms,
        });
    }

    /// Submit a transaction to the consensus network using gRPC first, falling back to REST if needed
    pub fn submitTransaction(self: *ConsensusClient, tx_bytes: []const u8) !model.TransactionResponse {
        var grpc_err: ?anyerror = null;
        var tx_id_hint: ?model.TransactionId = null;
        tx_id_hint = consensus_proto.extractTransactionId(tx_bytes) catch |err| {
            log.debug("unable to derive transaction id from submission payload: {s}", .{@errorName(err)});
            null;
        };

        if (self.nodes.items.len > 0) {
            const grpc_result: ?model.TransactionResponse = blk: {
                const resp = self.submitTransactionGrpc(tx_bytes, tx_id_hint) catch |err| {
                    grpc_err = err;
                    break :blk null;
                };
                break :blk resp;
            };
            if (grpc_result) |resp| return resp;
        }

        if (self.submit_url.len > 0) {
            return self.submitTransactionRest(tx_bytes) catch |err| {
                return switch (grpc_err) {
                    null => err,
                    else => |prev| prev,
                };
            };
        }

        return grpc_err orelse error.SubmitEndpointUnavailable;
    }

    fn submitTransactionGrpc(self: *ConsensusClient, tx_bytes: []const u8, tx_id_hint: ?model.TransactionId) !model.TransactionResponse {
        if (self.nodes.items.len == 0) return error.NoNodesConfigured;

        const start_ns = std.time.nanoTimestamp();
        const attempts = @min(self.nodes.items.len, 3);
        var attempt: usize = 0;
        var last_err: ?anyerror = null;

        while (attempt < attempts) : (attempt += 1) {
            const node = try self.selectNode();
            const response = self.performSubmitGrpc(node, tx_bytes, tx_id_hint) catch |err| {
                self.registerNodeFailure(node);
                log.err("submit (grpc) attempt {d} failed: {s}", .{ attempt + 1, @errorName(err) });
                last_err = err;
                if (attempt + 1 < attempts) {
                    const backoff_ns = self.computeGrpcRetryDelay(attempt);
                    const secs = backoff_ns / std.time.ns_per_s;
                    const nanos = backoff_ns % std.time.ns_per_s;
                    std.posix.nanosleep(secs, nanos);
                }
                continue;
            };
            self.registerNodeSuccess(node);
            const elapsed_ns = std.time.nanoTimestamp() - start_ns;
            const elapsed_ms = @as(u64, @intCast(@max(elapsed_ns, 0) / @as(i128, std.time.ns_per_ms)));
            const summary = self.snapshotGrpcSummary();
            log.info(
                "submit via gRPC succeeded in {d} attempt(s) ({d} ms) [requests={d} retries={d} failures={d} last_status={d} last_http={d} last_latency_ms={d}]",
                .{
                    attempt + 1,
                    elapsed_ms,
                    summary.total_requests,
                    summary.total_retries,
                    summary.total_failures,
                    summary.last_status_code,
                    summary.last_http_status,
                    summary.last_latency_ns / std.time.ns_per_ms,
                },
            );
            return response;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_ns;
        const elapsed_ms = @as(u64, @intCast(@max(elapsed_ns, 0) / @as(i128, std.time.ns_per_ms)));
        const summary = self.snapshotGrpcSummary();
        log.err(
            "submit via gRPC failed after {d} attempt(s) ({d} ms): {s} [requests={d} retries={d} failures={d} last_status={d} last_http={d} last_latency_ms={d}]",
            .{
                attempts,
                elapsed_ms,
                @errorName(last_err orelse error.SubmitRejected),
                summary.total_requests,
                summary.total_retries,
                summary.total_failures,
                summary.last_status_code,
                summary.last_http_status,
                summary.last_latency_ns / std.time.ns_per_ms,
            },
        );
        return last_err orelse error.SubmitRejected;
    }

    fn submitTransactionRest(self: *ConsensusClient, tx_bytes: []const u8) !model.TransactionResponse {
        if (self.submit_url.len == 0) return error.SubmitEndpointUnavailable;

        const start_ns = std.time.nanoTimestamp();
        const attempts = if (self.nodes.items.len == 0) 1 else @min(self.nodes.items.len, 3);
        var attempt: usize = 0;
        var last_err: ?anyerror = null;
        while (attempt < attempts) : (attempt += 1) {
            const node = try self.selectNode();
            const response = self.performSubmitRest(node, tx_bytes) catch |err| {
                self.registerNodeFailure(node);
                log.err("submit (rest) attempt {d} failed: {s}", .{ attempt + 1, @errorName(err) });
                last_err = err;
                if (attempt + 1 < attempts) {
                    const shift: u6 = @intCast(attempt);
                    const delay_ms: u64 = 200 * (@as(u64, 1) << shift);
                    const backoff = std.time.ns_per_ms * delay_ms;
                    const secs = backoff / std.time.ns_per_s;
                    const nanos = backoff % std.time.ns_per_s;
                    std.posix.nanosleep(secs, nanos);
                }
                continue;
            };
            self.registerNodeSuccess(node);
            const elapsed_ns = std.time.nanoTimestamp() - start_ns;
            const elapsed_ms = @as(u64, @intCast(@max(elapsed_ns, 0) / @as(i128, std.time.ns_per_ms)));
            log.info("submit via REST succeeded in {d} attempt(s) ({d} ms)", .{ attempt + 1, elapsed_ms });
            return response;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_ns;
        const elapsed_ms = @as(u64, @intCast(@max(elapsed_ns, 0) / @as(i128, std.time.ns_per_ms)));
        log.err("submit via REST failed after {d} attempt(s) ({d} ms): {s}", .{
            attempts,
            elapsed_ms,
            @errorName(last_err orelse error.SubmitRejected),
        });
        return last_err orelse error.SubmitRejected;
    }

    /// Convenience helper for submitting topic message transactions
    pub fn submitTopicMessage(self: *ConsensusClient, transaction: *tx.TopicMessageSubmitTransaction) !model.TransactionResponse {
        try transaction.freeze();
        const bytes = try transaction.toBytes();
        defer transaction.allocator.free(bytes);
        return try self.submitTransaction(bytes);
    }

    fn performSubmitRest(self: *ConsensusClient, node: *NodeEndpoint, tx_bytes: []const u8) !model.TransactionResponse {
        const encoded = try base64.standard.Encoder.encodeAlloc(self.allocator, tx_bytes);
        defer self.allocator.free(encoded);

        const node_str = try std.fmt.allocPrint(self.allocator, "{d}.{d}.{d}", .{ node.account_id.shard, node.account_id.realm, node.account_id.num });
        defer self.allocator.free(node_str);

        const payload = try std.fmt.allocPrint(self.allocator, "{{\"transaction\":\"{s}\",\"nodeId\":\"{s}\"}}", .{ encoded, node_str });
        defer self.allocator.free(payload);

        const uri = try std.Uri.parse(self.submit_url);

        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        try headers.append("content-type", "application/json");
        try headers.append("accept", "application/json");

        var request = try self.http_client.request(.POST, uri, headers, .{});
        defer request.deinit();

        try request.start();
        try request.writeAll(payload);
        try request.finish();
        try request.wait();

        const status = request.response.status;
        const status_code: u16 = @intFromEnum(status);
        const body = try request.reader().readAllAlloc(self.allocator, 1 * 1024 * 1024);
        defer self.allocator.free(body);

        switch (status) {
            .ok, .created, .accepted => return try self.parseSubmissionResponse(body, status_code),
            else => return try self.parseErrorResponse(body, status_code),
        }
    }

    fn performSubmitGrpc(self: *ConsensusClient, node: *NodeEndpoint, tx_bytes: []const u8, tx_id_hint: ?model.TransactionId) !model.TransactionResponse {
        const client = try self.ensureNodeGrpcClient(node);
        client.configureDeadline(null);

        const response_bytes = try client.unary("/proto.CryptoService/submitTransaction", tx_bytes, self.allocator);
        defer self.allocator.free(response_bytes);

        const parsed = try consensus_proto.decodeTransactionResponse(response_bytes);
        const status_code = parsed.precheck_code;

        var status_copy: []u8 = undefined;
        if (consensus_proto.responseCodeLabel(status_code)) |label| {
            status_copy = try self.allocator.dupe(u8, label);
        } else {
            status_copy = try std.fmt.allocPrint(self.allocator, "CODE_{d}", .{status_code});
        }

        const success = consensus_proto.isPrecheckSuccess(status_code);
        var error_copy: ?[]u8 = null;
        if (!success) {
            const summary = self.snapshotGrpcSummary();
            if (parsed.cost != 0) {
                error_copy = try std.fmt.allocPrint(
                    self.allocator,
                    "precheck {s}; cost={d}; grpc requests={d} retries={d} failures={d} last_status={d} last_http={d} last_latency_ms={d}",
                    .{
                        status_copy,
                        parsed.cost,
                        summary.total_requests,
                        summary.total_retries,
                        summary.total_failures,
                        summary.last_status_code,
                        summary.last_http_status,
                        summary.last_latency_ns / std.time.ns_per_ms,
                    },
                );
            } else {
                error_copy = try std.fmt.allocPrint(
                    self.allocator,
                    "precheck {s}; grpc requests={d} retries={d} failures={d} last_status={d} last_http={d} last_latency_ms={d}",
                    .{
                        status_copy,
                        summary.total_requests,
                        summary.total_retries,
                        summary.total_failures,
                        summary.last_status_code,
                        summary.last_http_status,
                        summary.last_latency_ns / std.time.ns_per_ms,
                    },
                );
            }
        }

        const stats = client.getStats();
        log.debug(
            "submit grpc node {d}.{d}.{d} status={d} http={d} latency={d} ms",
            .{
                node.account_id.shard,
                node.account_id.realm,
                node.account_id.num,
                stats.last_status_code,
                stats.last_http_status,
                stats.last_latency_ns / std.time.ns_per_ms,
            },
        );

        return .{
            .transaction_id = tx_id_hint,
            .node_id = node.account_id,
            .status = status_copy,
            .hash = null,
            .status_code = @intCast(status_code),
            .error_message = error_copy,
            .success = success,
        };
    }

    fn computeGrpcRetryDelay(self: *const ConsensusClient, attempt: usize) u64 {
        var base: u64 = self.grpc_options.base_backoff_ns;
        if (base == 0) base = 200 * std.time.ns_per_ms;

        const max_allowed: u64 = if (self.grpc_options.max_backoff_ns == 0)
            base * 16
        else
            self.grpc_options.max_backoff_ns;

        const capped_attempt = if (attempt > 6) 6 else attempt;
        var delay = base;
        if (capped_attempt > 0) {
            const shift: u6 = @intCast(capped_attempt);
            if (shift < 63 and base <= (math.maxInt(u64) >> shift)) {
                delay = base << shift;
            } else {
                delay = max_allowed;
            }
        }

        if (delay > max_allowed) delay = max_allowed;

        const jitter_percent: u64 = 80 + (std.crypto.random.int(u64) % 41);
        delay = (delay * jitter_percent) / 100;
        if (delay == 0) delay = base;
        if (delay > max_allowed) delay = max_allowed;
        return delay;
    }

    fn performQuery(self: *ConsensusClient, node: *NodeEndpoint, query: Query) !QueryResponse {
        const client = try self.ensureNodeGrpcClient(node);
        const deadline_opt: ?u64 = if (self.query_deadline_ns == 0) null else self.query_deadline_ns;
        client.configureDeadline(deadline_opt);
        const path: []const u8 = switch (query.query) {
            .transaction_get_receipt => "/proto.CryptoService/getTransactionReceipts",
            .transaction_get_record => "/proto.CryptoService/getTxRecordByTxID",
            .schedule_get_info => "/proto.ScheduleService/getScheduleInfo",
        };

        const request_bytes = switch (query.query) {
            .transaction_get_receipt => |receipt_query| try consensus_proto.encodeTransactionGetReceiptQuery(
                self.allocator,
                receipt_query.transaction_id,
                receipt_query.include_duplicates,
                false,
            ),
            .transaction_get_record => |record_query| try consensus_proto.encodeTransactionGetRecordQuery(
                self.allocator,
                record_query.transaction_id,
                record_query.include_duplicates,
                false,
            ),
            .schedule_get_info => |schedule_query| try consensus_proto.encodeScheduleGetInfoQuery(
                self.allocator,
                schedule_query.schedule_id,
            ),
        };
        defer self.allocator.free(request_bytes);

        const response_bytes = try client.unary(path, request_bytes, self.allocator);
        defer self.allocator.free(response_bytes);

        const transport_stats = client.getStats();
        log.debug("query grpc status={d} http={d} latency={d} ms", .{
            transport_stats.last_status_code,
            transport_stats.last_http_status,
            transport_stats.last_latency_ns / std.time.ns_per_ms,
        });

        switch (query.query) {
            .transaction_get_receipt => |receipt_query| {
                const receipt = try consensus_proto.decodeTransactionGetReceiptResponse(response_bytes, receipt_query.transaction_id);
                return QueryResponse{
                    .response = .{
                        .transaction_get_receipt = TransactionGetReceiptResponse{ .receipt = receipt },
                    },
                };
            },
            .transaction_get_record => |_| {
                const record = try consensus_proto.decodeTransactionGetRecordResponse(self.allocator, response_bytes);
                return QueryResponse{
                    .response = .{ .transaction_get_record = TransactionGetRecordResponse{ .record = record } },
                };
            },
            .schedule_get_info => |_| {
                const info = try consensus_proto.decodeScheduleGetInfoResponse(self.allocator, response_bytes);
                return QueryResponse{
                    .response = .{ .schedule_get_info = ScheduleGetInfoResponse{ .info = info } },
                };
            },
        }
    }

    fn ensureNodeGrpcClient(self: *ConsensusClient, node: *NodeEndpoint) !*grpc_web.GrpcWebClient {
        if (node.grpc_client) |*client| return client;
        if (node.grpc_endpoint == null) {
            node.grpc_endpoint = try std.fmt.allocPrint(self.allocator, "https://{s}", .{node.address});
        }
        const client = try grpc_web.GrpcWebClient.initWithOptions(self.allocator, node.grpc_endpoint.?, self.grpc_options);
        node.grpc_client = client;
        var client_ref = &node.grpc_client.?;
        client_ref.setDebugPayloadLogging(self.grpc_debug_payloads);
        return client_ref;
    }

    pub const ReceiptOptions = struct {
        timeout_ns: ?u64 = null,
        poll_interval_ns: ?u64 = null,
    };

    /// Get transaction receipt using configured polling defaults
    pub fn getTransactionReceipt(self: *ConsensusClient, transaction_id: model.TransactionId) !model.TransactionReceipt {
        return try self.getTransactionReceiptWithOptions(transaction_id, .{});
    }

    /// Get transaction receipt with custom polling controls
    pub fn getTransactionReceiptWithOptions(
        self: *ConsensusClient,
        transaction_id: model.TransactionId,
        options: ReceiptOptions,
    ) !model.TransactionReceipt {
        const timeout_ns = options.timeout_ns orelse self.receipt_max_wait_ns;
        const poll_ns = options.poll_interval_ns orelse self.receipt_poll_interval_ns;
        if (timeout_ns == 0) return error.InvalidReceiptTimeout;
        if (poll_ns == 0) return error.InvalidPollInterval;

        const query = Query{
            .query = .{
                .transaction_get_receipt = TransactionGetReceiptQuery{
                    .transaction_id = transaction_id,

                    .include_duplicates = false,
                },
            },
        };

        var timer = try std.time.Timer.start();
        while (true) {
            const response = try self.executeQuery(query);
            switch (response.response) {
                .transaction_get_receipt => |receipt_response| {
                    const receipt = receipt_response.receipt;
                    if (receipt.status != .unknown) return receipt;
                },
            }

            const elapsed = timer.read();
            if (elapsed >= timeout_ns) break;

            const remaining = timeout_ns - elapsed;
            const sleep_ns = if (poll_ns < remaining) poll_ns else remaining;
            if (sleep_ns == 0) break;
            const secs = sleep_ns / std.time.ns_per_s;
            const nanos = sleep_ns % std.time.ns_per_s;
            std.posix.nanosleep(secs, nanos);
        }

        return error.ReceiptTimedOut;
    }

    pub fn setReceiptPendingAttemptsForTest(self: *ConsensusClient, attempts: usize) void {
        self.receipt_pending_attempts = attempts;
    }

    /// Get transaction record
    pub fn getTransactionRecord(self: *ConsensusClient, transaction_id: model.TransactionId) !model.TransactionRecord {
        // Build the query
        const query = Query{
            .query = .{
                .transaction_get_record = TransactionGetRecordQuery{
                    .transaction_id = transaction_id,
                    .include_duplicates = false,
                },
            },
        };

        // In a real implementation, this would:
        // 1. Serialize the query to protobuf
        // 2. Send via gRPC to consensus node
        // 3. Deserialize the response

        // For now, simulate the gRPC call
        const response = try self.executeQuery(query);

        // Extract the record from response
        switch (response.response) {
            .transaction_get_record => |record_response| {
                return record_response.record;
            },
        }
    }

    pub fn getScheduleInfo(self: *ConsensusClient, schedule_id: model.ScheduleId) !model.ScheduleInfo {
        const query = Query{
            .query = .{
                .schedule_get_info = ScheduleGetInfoQuery{
                    .schedule_id = schedule_id,
                },
            },
        };

        const response = try self.executeQuery(query);
        switch (response.response) {
            .schedule_get_info => |info_response| return info_response.info,
            else => return error.QueryFailed,
        }
    }

    /// Execute a query against the consensus network
    fn executeQuery(self: *ConsensusClient, query: Query) !QueryResponse {
        switch (query.query) {
            .transaction_get_receipt => |receipt_query| {
                if (self.receipt_pending_attempts > 0) {
                    self.receipt_pending_attempts -= 1;
                    return QueryResponse{
                        .response = .{
                            .transaction_get_receipt = TransactionGetReceiptResponse{
                                .receipt = model.TransactionReceipt{
                                    .status = .unknown,
                                    .transaction_id = receipt_query.transaction_id,
                                },
                            },
                        },
                    };
                }
            },
            else => {},
        }

        const start_ns = std.time.nanoTimestamp();
        const attempts = if (self.nodes.items.len == 0) 1 else @min(self.nodes.items.len, 3);
        var attempt: usize = 0;
        var last_err: ?anyerror = null;
        while (attempt < attempts) : (attempt += 1) {
            const node = try self.selectNode();
            const response = self.performQuery(node, query) catch |err| {
                self.registerNodeFailure(node);
                log.err("query attempt {d} failed: {s}", .{ attempt + 1, @errorName(err) });
                last_err = err;
                if (attempt + 1 < attempts) {
                    const backoff_ms: u64 = 200 * (@as(u64, 1) << @intCast(attempt));
                    const backoff_ns = backoff_ms * std.time.ns_per_ms;
                    const secs = backoff_ns / std.time.ns_per_s;
                    const nanos = backoff_ns % std.time.ns_per_s;
                    std.posix.nanosleep(secs, nanos);
                }
                continue;
            };
            self.registerNodeSuccess(node);
            const elapsed_ns = std.time.nanoTimestamp() - start_ns;
            const elapsed_ns_clamped = @max(elapsed_ns, 0);
            const elapsed_ms = @as(u64, @intCast(elapsed_ns_clamped / @as(i128, std.time.ns_per_ms)));
            log.info("query succeeded in {d} attempt(s) ({d} ms)", .{ attempt + 1, elapsed_ms });
            return response;
        }

        const elapsed_ns = std.time.nanoTimestamp() - start_ns;
        const elapsed_ns_clamped = @max(elapsed_ns, 0);
        const elapsed_ms = @as(u64, @intCast(elapsed_ns_clamped / @as(i128, std.time.ns_per_ms)));
        log.err("query failed after {d} attempt(s) ({d} ms): {s}", .{ attempts, elapsed_ms, @errorName(last_err orelse error.QueryFailed) });
        return last_err orelse error.QueryFailed;
    }
};

fn determineSubmitUrl(options: ConsensusClient.InitOptions) !?[]u8 {
    const source = options.submit_url orelse defaultSubmitUrl(options.network);
    if (source) |url| {
        return try options.allocator.dupe(u8, url);
    }
    return null;
}

fn defaultSubmitUrl(network: model.Network) ?[]const u8 {
    return switch (network) {
        .testnet => "https://testnet.hashio.io/api/v1/transactions",
        .previewnet => "https://previewnet.hashio.io/api/v1/transactions",
        .mainnet => "https://mainnet.hashio.io/api/v1/transactions",
        .custom => null,
    };
}

fn copyOptionalString(allocator: std.mem.Allocator, value: ?json.Value) ![]u8 {
    if (value) |val| switch (val) {
        .string => |s| {
            if (s.len == 0) return "";
            return try allocator.dupe(u8, s);
        },
        .null => return "",
        else => return error.ParseError,
    };
    return "";
}

fn dupOptionalString(allocator: std.mem.Allocator, value: ?json.Value) !?[]u8 {
    if (value) |val| switch (val) {
        .string => |s| return try allocator.dupe(u8, s),
        .null => return null,
        else => return error.ParseError,
    };
    return null;
}

fn parseOptionalNodeId(value: ?json.Value) !?model.AccountId {
    if (value) |val| switch (val) {
        .string => |s| return try model.AccountId.fromString(s),
        .null => return null,
        else => return error.ParseError,
    };
    return null;
}

fn parseSubmissionResponse(self: *ConsensusClient, body: []const u8, status_code: u16) !model.TransactionResponse {
    var parsed = try json.parseFromSlice(json.Value, self.allocator, body, .{});
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.ParseError,
    };

    const tx_id_value = obj.get("transactionId") orelse return error.ParseError;
    const tx_id_str = switch (tx_id_value) {
        .string => |s| s,
        else => return error.ParseError,
    };

    const transaction_id = try model.TransactionId.parse(tx_id_str);

    const status_copy = try copyOptionalString(self.allocator, obj.get("status"));
    errdefer if (status_copy.len > 0) self.allocator.free(status_copy);

    var hash_copy: ?[]u8 = null;
    if (obj.get("hash")) |hash_val| switch (hash_val) {
        .string => |s| hash_copy = try self.allocator.dupe(u8, s),
        .null => {},
        else => return error.ParseError,
    };
    errdefer if (hash_copy) |h| self.allocator.free(h);

    const node_id = try parseOptionalNodeId(obj.get("nodeId"));

    return model.TransactionResponse{
        .transaction_id = transaction_id,
        .node_id = node_id,
        .status = status_copy,
        .hash = hash_copy,
        .status_code = status_code,
        .success = true,
    };
}

fn parseErrorResponse(self: *ConsensusClient, body: []const u8, status_code: u16) !model.TransactionResponse {
    var parsed = try json.parseFromSlice(json.Value, self.allocator, body, .{});
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.ParseError,
    };

    var tx_id: ?model.TransactionId = null;
    if (obj.get("transactionId")) |tx_value| {
        const tx_str = switch (tx_value) {
            .string => |s| s,
            else => return error.ParseError,
        };
        tx_id = try model.TransactionId.parse(tx_str);
    }

    var status_value: ?json.Value = obj.get("status");
    if (status_value == null) status_value = obj.get("error");
    const status_copy = try copyOptionalString(self.allocator, status_value);
    errdefer if (status_copy.len > 0) self.allocator.free(status_copy);

    var message_value: ?json.Value = obj.get("message");
    if (message_value == null) message_value = obj.get("errorMessage");
    if (message_value == null) message_value = obj.get("detail");
    const message_copy = try dupOptionalString(self.allocator, message_value);
    errdefer if (message_copy) |msg| self.allocator.free(msg);

    var hash_copy: ?[]u8 = null;
    if (obj.get("hash")) |hash_val| switch (hash_val) {
        .string => |s| hash_copy = try self.allocator.dupe(u8, s),
        .null => {},
        else => return error.ParseError,
    };
    errdefer if (hash_copy) |h| self.allocator.free(h);

    const node_id = try parseOptionalNodeId(obj.get("nodeId"));

    const response = model.TransactionResponse{
        .transaction_id = tx_id,
        .node_id = node_id,
        .status = status_copy,
        .hash = hash_copy,
        .status_code = status_code,
        .error_message = message_copy,
        .success = false,
    };

    const log_message = if (message_copy) |msg| msg else status_copy;
    log.err("submit rejected {d}: {s}", .{ status_code, log_message });

    return response;
}

test "parseSubmissionResponse marks successful token transfer" {
    const allocator = std.testing.allocator;

    var client = try ConsensusClient.init(.{
        .allocator = allocator,
        .network = .testnet,
        .nodes = &[_]config.Node{},
    });
    defer client.deinit();

    const body = "{\"transactionId\":\"0.0.100-1700000001-1\",\"status\":\"SUCCESS\",\"hash\":\"deadbeef\",\"nodeId\":\"0.0.3\"}";
    var response = try client.parseSubmissionResponse(body, 202);
    defer response.deinit(allocator);

    try std.testing.expect(response.success);
    try std.testing.expectEqual(@as(u16, 202), response.status_code);
    try std.testing.expect(response.transaction_id != null);
    try std.testing.expectEqual(@as(u64, 100), response.transaction_id.?.account_id.num);
    try std.testing.expectEqualStrings("SUCCESS", response.status);
}

test "parseErrorResponse captures Hashio error details" {
    const allocator = std.testing.allocator;

    var client = try ConsensusClient.init(.{
        .allocator = allocator,
        .network = .testnet,
        .nodes = &[_]config.Node{},
    });
    defer client.deinit();

    const body = "{\"transactionId\":\"0.0.100-1700000001-1\",\"status\":\"INSUFFICIENT_PAYER_BALANCE\",\"message\":\"payer signature invalid\",\"hash\":\"facefeed\"}";
    var response = try client.parseErrorResponse(body, 400);
    defer response.deinit(allocator);

    try std.testing.expect(!response.success);
    try std.testing.expectEqual(@as(u16, 400), response.status_code);
    try std.testing.expect(response.error_message != null);
    try std.testing.expectEqualStrings("payer signature invalid", response.error_message.?);
}

test "getTransactionReceiptWithOptions eventually succeeds after pending attempts" {
    const allocator = std.testing.allocator;

    var client = try ConsensusClient.init(.{
        .allocator = allocator,
        .network = .testnet,
        .nodes = &[_]config.Node{},
    });
    defer client.deinit();

    client.setReceiptPendingAttemptsForTest(2);

    const tx_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 1234),
        .valid_start = .{ .seconds = 1_700_000_000, .nanos = 42 },
    };

    const receipt = try client.getTransactionReceiptWithOptions(tx_id, .{
        .timeout_ns = 10 * std.time.ns_per_ms,
        .poll_interval_ns = 1 * std.time.ns_per_ms,
    });

    try std.testing.expectEqual(model.TransactionStatus.success, receipt.status);
    try std.testing.expectEqual(tx_id.account_id.num, receipt.transaction_id.account_id.num);
    try std.testing.expectEqual(@as(usize, 0), client.receipt_pending_attempts);
}

test "getTransactionReceiptWithOptions times out when receipt stays pending" {
    const allocator = std.testing.allocator;

    var client = try ConsensusClient.init(.{
        .allocator = allocator,
        .network = .testnet,
        .nodes = &[_]config.Node{},
    });
    defer client.deinit();

    client.setReceiptPendingAttemptsForTest(100);

    const tx_id = model.TransactionId{
        .account_id = model.AccountId.init(0, 0, 5678),
        .valid_start = .{ .seconds = 1_700_000_100, .nanos = 10 },
    };

    try std.testing.expectError(error.ReceiptTimedOut, client.getTransactionReceiptWithOptions(tx_id, .{
        .timeout_ns = 5 * std.time.ns_per_ms,
        .poll_interval_ns = 2 * std.time.ns_per_ms,
    }));
}
