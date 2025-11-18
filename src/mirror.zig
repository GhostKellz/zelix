//! Mirror Node client for Hedera REST APIs and Block Streams.

const std = @import("std");
const model = @import("model.zig");
const config = @import("config.zig");
const mirror_parse = @import("mirror_parse.zig");
const grpc_web = @import("grpc_web.zig");
const mirror_proto = @import("mirror_proto.zig");
const block_stream = @import("block_stream.zig");

const fmt = std.fmt;
const mem = std.mem;
const log = std.log.scoped(.mirror_transport);

pub const Transport = enum {
    rest,
    grpc,
    block_stream,
};

pub const InitOptions = struct {
    allocator: std.mem.Allocator,
    network: model.Network,
    base_url: ?[]const u8 = null,
    transport: Transport = .rest,
    grpc_endpoint: ?[]const u8 = null,
    block_node_endpoint: ?[]const u8 = null,
};

pub const MirrorClient = struct {
    allocator: std.mem.Allocator,
    transport: Transport,
    base_url: []u8,
    grpc_endpoint: ?[]u8,
    block_node_endpoint: ?[]u8,
    grpc_fallback_logged: bool,
    http_client: std.http.Client,
    threaded_io: std.Io.Threaded,
    grpc_client: ?grpc_web.GrpcWebClient,
    block_stream_client: ?block_stream.BlockStreamClient,
    grpc_debug_payloads: bool = false,

    pub const TransactionReceiptQueryOptions = struct {
        include_duplicates: bool = false,
        include_children: bool = false,
    };

    pub const TransactionRecordQueryOptions = struct {
        include_duplicates: bool = false,
        include_children: bool = false,
    };

    pub const WaitOptions = struct {
        timeout_ns: u64 = 30 * std.time.ns_per_s,
        initial_poll_ns: u64 = std.time.ns_per_s,
        max_poll_ns: u64 = 5 * std.time.ns_per_s,
        backoff_multiplier: u32 = 1,
    };

    pub const TransactionStreamOptions = struct {
        start_time: ?model.Timestamp = null,
        limit: usize = 25,
        poll_interval_ns: u64 = 2 * std.time.ns_per_s,
        include_duplicates: bool = false,
        include_children: bool = false,
    };

    pub const TransactionStreamCallback = fn (*const model.TransactionRecord) anyerror!void;

    pub const TokenAllowanceQueryOptions = struct {
        limit: ?usize = null,
        token_id: ?model.TokenId = null,
        spender: ?model.AccountId = null,
        next: ?[]const u8 = null,
    };

    pub const TokenNftAllowanceQueryOptions = struct {
        limit: ?usize = null,
        token_id: ?model.TokenId = null,
        spender: ?model.AccountId = null,
        approved_for_all: ?bool = null,
        serial_number: ?u64 = null,
        next: ?[]const u8 = null,
    };

    pub const DetailedAccountInfo = struct {
        info: model.AccountInfo,
        balance: model.Hbar,
        allowances: model.AccountAllowances,

        pub fn init(info: model.AccountInfo, balance: model.Hbar, allowances: model.AccountAllowances) DetailedAccountInfo {
            return .{ .info = info, .balance = balance, .allowances = allowances };
        }

        pub fn deinit(self: *DetailedAccountInfo, allocator: std.mem.Allocator) void {
            self.info.deinit(allocator);
            self.allowances.deinit(allocator);
            self.balance = model.Hbar.ZERO;
        }
    };

    pub fn init(allocator: std.mem.Allocator, network: model.Network) !MirrorClient {
        return initWithOptions(.{
            .allocator = allocator,
            .network = network,
        });
    }

    pub fn initWithBaseUrl(allocator: std.mem.Allocator, base_url: []const u8) !MirrorClient {
        return initWithOptions(.{
            .allocator = allocator,
            .network = .custom,
            .base_url = base_url,
        });
    }

    pub fn initWithOptions(options: InitOptions) !MirrorClient {
        const base_source = options.base_url orelse config.defaultMirrorUrl(options.network);
        const base_copy = try options.allocator.dupe(u8, base_source);
        errdefer options.allocator.free(base_copy);

        var grpc_copy: ?[]u8 = null;
        var grpc_client: ?grpc_web.GrpcWebClient = null;
        if (options.grpc_endpoint) |endpoint| {
            grpc_copy = try options.allocator.dupe(u8, endpoint);
        } else if (options.transport == .grpc) {
            grpc_copy = try options.allocator.dupe(u8, config.defaultMirrorGrpcEndpoint(options.network));
        }

        if (options.transport == .grpc) {
            const endpoint_value = grpc_copy orelse return error.GrpcEndpointRequired;
            grpc_client = try grpc_web.GrpcWebClient.init(options.allocator, endpoint_value);
        }

        var block_node_copy: ?[]u8 = null;
        var block_stream_client: ?block_stream.BlockStreamClient = null;
        if (options.block_node_endpoint) |endpoint| {
            block_node_copy = try options.allocator.dupe(u8, endpoint);
        } else if (options.transport == .block_stream) {
            // Default block node endpoint for testnet/mainnet
            const default_endpoint = switch (options.network) {
                .mainnet => "https://mainnet.block.hedera.com:443",
                .testnet => "https://testnet.block.hedera.com:443",
                .previewnet => "https://previewnet.block.hedera.com:443",
                else => "https://testnet.block.hedera.com:443",
            };
            block_node_copy = try options.allocator.dupe(u8, default_endpoint);
        }

        if (options.transport == .block_stream) {
            const endpoint_value = block_node_copy orelse return error.BlockNodeEndpointRequired;
            block_stream_client = try block_stream.BlockStreamClient.init(.{
                .allocator = options.allocator,
                .block_node_endpoint = endpoint_value,
            });
        }

        var result = MirrorClient{
            .allocator = options.allocator,
            .transport = options.transport,
            .base_url = base_copy,
            .grpc_endpoint = grpc_copy,
            .block_node_endpoint = block_node_copy,
            .grpc_fallback_logged = false,
            .threaded_io = std.Io.Threaded.init(options.allocator),
            .http_client = undefined, // Will be set below
            .grpc_client = grpc_client,
            .block_stream_client = block_stream_client,
            .grpc_debug_payloads = false,
        };
        result.http_client = std.http.Client{ .allocator = options.allocator, .io = result.threaded_io.io() };
        return result;
    }

    pub fn deinit(self: *MirrorClient) void {
        self.http_client.deinit();
        if (self.grpc_client) |*client| client.deinit();
        self.grpc_client = null;
        if (self.block_stream_client) |*client| client.deinit();
        self.block_stream_client = null;
        if (self.base_url.len > 0) self.allocator.free(self.base_url);
        self.base_url = "";
        if (self.grpc_endpoint) |endpoint| self.allocator.free(endpoint);
        self.grpc_endpoint = null;
        if (self.block_node_endpoint) |endpoint| self.allocator.free(endpoint);
        self.block_node_endpoint = null;
        self.grpc_fallback_logged = false;
        self.grpc_debug_payloads = false;
    }

    pub fn setGrpcPayloadLogging(self: *MirrorClient, enable: bool) void {
        self.grpc_debug_payloads = enable;
        if (self.grpc_client) |*client| client.setDebugPayloadLogging(enable);
    }

    pub fn getGrpcStats(self: *const MirrorClient) ?grpc_web.Stats {
        if (self.grpc_client) |*client| {
            return client.getStats();
        }
        return null;
    }

    pub fn getAccountBalance(self: *MirrorClient, account_id: model.AccountId) !model.Hbar {
        return switch (self.transport) {
            .rest => try self.getAccountBalanceRest(account_id),
            .grpc => self.getAccountBalanceGrpc(account_id) catch |err| {
                self.logGrpcFallback("getAccountBalance", err);
                return try self.getAccountBalanceRest(account_id);
            },
            .block_stream => try self.getAccountBalanceRest(account_id), // Block streams don't support account queries
        };
    }

    pub fn getAccountInfo(self: *MirrorClient, account_id: model.AccountId) !AccountInfo {
        var detailed = try self.getAccountInfoDetailed(account_id);
        defer detailed.deinit(self.allocator);
        const account_copy = detailed.info.account_id;
        const balance = detailed.balance;
        return .{ .account_id = account_copy, .balance = balance };
    }

    pub fn getAccountInfoDetailed(self: *MirrorClient, account_id: model.AccountId) !DetailedAccountInfo {
        return switch (self.transport) {
            .rest => try self.getAccountInfoRestDetailed(account_id),
            .grpc => self.getAccountInfoGrpcDetailed(account_id) catch |err| {
                self.logGrpcFallback("getAccountInfo", err);
                return try self.getAccountInfoRestDetailed(account_id);
            },
            .block_stream => return error.NotSupported,
        };
    }

    pub fn getTokenInfo(self: *MirrorClient, token_id: model.TokenId) !model.TokenInfo {
        return switch (self.transport) {
            .rest => try self.getTokenInfoRest(token_id),
            .grpc => self.getTokenInfoGrpc(token_id) catch |err| {
                self.logGrpcFallback("getTokenInfo", err);
                return try self.getTokenInfoRest(token_id);
            },
            .block_stream => return error.NotSupported,
        };
    }

    pub fn getNftInfo(self: *MirrorClient, token_id: model.TokenId, serial: u64) !model.NftInfo {
        self.ensureGrpcFallback("getNftInfo");
        const url = try self.buildUrl("{s}/tokens/{d}.{d}.{d}/nfts/{d}", .{
            self.base_url,
            token_id.shard,
            token_id.realm,
            token_id.num,
            serial,
        });
        defer self.allocator.free(url);

        const body = try self.fetchJson(url);
        defer self.allocator.free(body);

        return try mirror_parse.parseNftInfo(self.allocator, body, token_id, serial);
    }

    pub fn getTokenAllowances(
        self: *MirrorClient,
        account_id: model.AccountId,
        options: TokenAllowanceQueryOptions,
    ) !model.TokenAllowancesPage {
        self.ensureGrpcFallback("getTokenAllowances");
        const url = try self.buildTokenAllowanceUrl(account_id, options);
        defer self.allocator.free(url);

        const body = try self.fetchJson(url);
        defer self.allocator.free(body);

        return try mirror_parse.parseTokenAllowances(self.allocator, body);
    }

    pub fn getTokenNftAllowances(
        self: *MirrorClient,
        account_id: model.AccountId,
        options: TokenNftAllowanceQueryOptions,
    ) !model.TokenNftAllowancesPage {
        self.ensureGrpcFallback("getTokenNftAllowances");
        const url = try self.buildTokenNftAllowanceUrl(account_id, options);
        defer self.allocator.free(url);

        const body = try self.fetchJson(url);
        defer self.allocator.free(body);

        return try mirror_parse.parseTokenNftAllowances(self.allocator, body);
    }

    pub fn getTransactionReceipt(
        self: *MirrorClient,
        tx_id: model.TransactionId,
        options: TransactionReceiptQueryOptions,
    ) !model.TransactionReceipt {
        return switch (self.transport) {
            .rest => try self.getTransactionReceiptRest(tx_id, options),
            .grpc => self.getTransactionReceiptGrpc(tx_id, options) catch |err| {
                self.logGrpcFallback("getTransactionReceipt", err);
                return try self.getTransactionReceiptRest(tx_id, options);
            },
        };
    }

    pub fn getTransactionRecord(
        self: *MirrorClient,
        tx_id: model.TransactionId,
        options: TransactionRecordQueryOptions,
    ) !model.TransactionRecord {
        return switch (self.transport) {
            .rest => try self.getTransactionRecordRest(tx_id, options),
            .grpc => self.getTransactionRecordGrpc(tx_id, options) catch |err| {
                self.logGrpcFallback("getTransactionRecord", err);
                return try self.getTransactionRecordRest(tx_id, options);
            },
        };
    }

    pub fn streamTransactions(
        self: *MirrorClient,
        options: TransactionStreamOptions,
        callback: TransactionStreamCallback,
    ) !void {
        return switch (self.transport) {
            .rest => try self.streamTransactionsRest(options, callback),
            .grpc => self.streamTransactionsGrpc(options, callback) catch |err| {
                self.logGrpcFallback("streamTransactions", err);
                return try self.streamTransactionsRest(options, callback);
            },
            .block_stream => try self.streamTransactionsBlockStream(options, callback),
        };
    }

    pub fn getFileContents(self: *MirrorClient, file_id: model.FileId) ![]u8 {
        self.ensureGrpcFallback("getFileContents");
        const url = try self.buildUrl("{s}/files/{d}.{d}.{d}/contents", .{
            self.base_url,
            file_id.shard,
            file_id.realm,
            file_id.num,
        });
        defer self.allocator.free(url);

        return try self.fetch(url, null);
    }

    pub fn getTransaction(self: *MirrorClient, tx_id: model.TransactionId) !TransactionInfo {
        self.ensureGrpcFallback("getTransaction");
        const url = try self.buildTransactionUrl(tx_id);
        defer self.allocator.free(url);

        const body = try self.fetchJson(url);
        defer self.allocator.free(body);

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
        defer parsed.deinit();

        const root = parsed.value;
        const obj = switch (root) {
            .object => |o| o,
            else => return error.ParseError,
        };

        const transactions_val = obj.get("transactions") orelse return error.ParseError;
        const transactions = switch (transactions_val) {
            .array => |arr| arr,
            else => return error.ParseError,
        };
        if (transactions.items.len == 0) return error.NotFound;

        const tx_obj = try expectObject(transactions.items[0]);
        const result_val = try getField(tx_obj, "result");
        const result_str = switch (result_val) {
            .string => |s| s,
            else => return error.ParseError,
        };
        const success = mem.eql(u8, result_str, "SUCCESS");
        return .{ .transaction_id = tx_id, .successful = success };
    }

    pub fn waitForTransaction(self: *MirrorClient, tx_id: model.TransactionId, timeout_ms: u64) !TransactionInfo {
        const max_ms: u64 = std.math.maxInt(u64) / std.time.ns_per_ms;
        const clamped_ms = if (timeout_ms > max_ms) max_ms else timeout_ms;
        return try self.waitForTransactionWithOptions(tx_id, .{
            .timeout_ns = clamped_ms * std.time.ns_per_ms,
        });
    }

    pub fn waitForTransactionWithOptions(
        self: *MirrorClient,
        tx_id: model.TransactionId,
        options: WaitOptions,
    ) !TransactionInfo {
        if (options.timeout_ns == 0) return error.InvalidTimeout;
        var poll_ns = options.initial_poll_ns;
        if (poll_ns == 0) return error.InvalidPollInterval;
        if (options.max_poll_ns != 0 and poll_ns > options.max_poll_ns) {
            poll_ns = options.max_poll_ns;
        }

        self.ensureGrpcFallback("waitForTransaction");

        const multiplier = if (options.backoff_multiplier == 0) @as(u32, 1) else options.backoff_multiplier;
        var timer = try std.time.Timer.start();

        while (true) {
            if (self.getTransaction(tx_id)) |info| {
                return info;
            } else |err| switch (err) {
                error.NotFound => {},
                else => return err,
            }

            const elapsed = timer.read();
            if (elapsed >= options.timeout_ns) break;

            const remaining = options.timeout_ns - elapsed;
            const sleep_ns = if (poll_ns > remaining) remaining else poll_ns;
            std.time.sleep(sleep_ns);

            if (multiplier > 1 and poll_ns < options.max_poll_ns) {
                const next_poll = poll_ns * multiplier;
                poll_ns = if (next_poll > options.max_poll_ns) options.max_poll_ns else next_poll;
            }
        }

        return error.Timeout;
    }

    pub fn getTopicMessages(
        self: *MirrorClient,
        topic_id: model.TopicId,
        limit: usize,
        next: ?[]const u8,
    ) !struct { messages: []TopicMessage, next: ?[]u8 } {
        return switch (self.transport) {
            .rest => try self.getTopicMessagesRest(topic_id, limit, next),
            .grpc => try self.getTopicMessagesGrpc(topic_id, limit, next),
        };
    }

    pub fn subscribeTopic(self: *MirrorClient, topic_id: model.TopicId, callback: fn (msg: TopicMessage) void) !void {
        return switch (self.transport) {
            .rest => self.subscribeTopicRest(topic_id, callback),
            .grpc => self.subscribeTopicGrpc(topic_id, callback) catch |err| {
                log.warn("mirror gRPC subscribeTopic unavailable: {s}; falling back to REST", .{@errorName(err)});
                return self.subscribeTopicRest(topic_id, callback);
            },
        };
    }

    fn subscribeTopicRest(self: *MirrorClient, topic_id: model.TopicId, callback: fn (msg: TopicMessage) void) !void {
        self.ensureGrpcFallback("subscribeTopic");
        var cursor: ?[]u8 = null;
        defer if (cursor) |token| self.allocator.free(token);

        while (true) {
            const batch = try self.getTopicMessagesRest(topic_id, 10, cursor);
            defer {
                for (batch.messages) |*msg| msg.deinit(self.allocator);
                self.allocator.free(batch.messages);
                if (batch.next) |token| self.allocator.free(token);
            }

            for (batch.messages) |msg| {
                callback(msg);
            }

            if (batch.next) |token| {
                if (cursor) |old| self.allocator.free(old);
                cursor = try self.allocator.dupe(u8, token);
            } else {
                std.time.sleep(5 * std.time.ns_per_s);
            }
        }
    }

    fn subscribeTopicGrpc(self: *MirrorClient, topic_id: model.TopicId, callback: fn (msg: TopicMessage) void) !void {
        var next_start: ?model.Timestamp = null;
        var reconnect_delay_ns: u64 = 500 * std.time.ns_per_ms;

        while (true) {
            const client = try self.getGrpcClient();
            const request_bytes = try mirror_proto.encodeConsensusTopicQuery(self.allocator, topic_id, next_start, null, null);
            defer self.allocator.free(request_bytes);

            var received: bool = false;
            const Handler = struct {
                allocator: std.mem.Allocator,
                callback: fn (TopicMessage) void,
                next_start: *?model.Timestamp,
                received: *bool,
                fn handle(ctx: *@This(), payload: []const u8) !void {
                    var decoded = try mirror_proto.decodeConsensusTopicResponse(ctx.allocator, payload);
                    defer decoded.deinit(ctx.allocator);

                    const owned = decoded.message;
                    decoded.message = &[_]u8{};

                    var msg = TopicMessage{
                        .sequence_number = decoded.sequence_number,
                        .message = owned,
                        .consensus_timestamp = decoded.consensus_timestamp,
                    };

                    ctx.callback(msg);

                    msg.deinit(ctx.allocator);
                    ctx.received.* = true;
                    ctx.next_start.* = MirrorClient.advanceTimestamp(decoded.consensus_timestamp);
                }
            };

            const handler = Handler{
                .allocator = self.allocator,
                .callback = callback,
                .next_start = &next_start,
                .received = &received,
            };

            client.serverStreaming(
                "/com.hedera.mirror.api.proto.ConsensusService/subscribeTopic",
                request_bytes,
                handler,
            ) catch |err| {
                log.warn("mirror gRPC subscribeTopic failed: {s}", .{@errorName(err)});
                std.time.sleep(reconnect_delay_ns);
                if (reconnect_delay_ns < 5 * std.time.ns_per_s) reconnect_delay_ns *= 2;
                continue;
            };

            if (!received) {
                std.time.sleep(2 * std.time.ns_per_s);
            }

            reconnect_delay_ns = 500 * std.time.ns_per_ms;
        }
    }

    pub fn getJson(self: *MirrorClient, comptime pattern: []const u8, args: anytype) ![]u8 {
        self.ensureGrpcFallback("getJson");
        const url = try self.buildUrl(pattern, args);
        defer self.allocator.free(url);
        return try self.fetchJson(url);
    }

    fn getAccountBalanceRest(self: *MirrorClient, account_id: model.AccountId) !model.Hbar {
        const url = try self.buildUrl("{s}/balances?account.id={d}.{d}.{d}", .{
            self.base_url,
            account_id.shard,
            account_id.realm,
            account_id.num,
        });
        defer self.allocator.free(url);

        const body = try self.fetchJson(url);
        defer self.allocator.free(body);

        return try mirror_parse.parseAccountBalance(self.allocator, body, account_id);
    }

    fn getAccountBalanceGrpc(self: *MirrorClient, account_id: model.AccountId) !model.Hbar {
        const request = try mirror_proto.encodeAccountBalanceQuery(self.allocator, account_id);
        defer self.allocator.free(request);

        const response = try self.callGrpcUnary("/proto.CryptoService/cryptoGetBalance", request);
        defer self.allocator.free(response);

        return try mirror_proto.decodeAccountBalanceResponse(response);
    }

    fn getAccountInfoRestDetailed(self: *MirrorClient, account_id: model.AccountId) !DetailedAccountInfo {
        const url = try self.buildUrl("{s}/accounts/{d}.{d}.{d}", .{
            self.base_url,
            account_id.shard,
            account_id.realm,
            account_id.num,
        });
        defer self.allocator.free(url);

        const body = try self.fetchJson(url);
        defer self.allocator.free(body);

        var info = try mirror_parse.parseAccountInfo(self.allocator, body, account_id);
        errdefer info.deinit(self.allocator);

        var allowances = try mirror_parse.parseAccountAllowances(self.allocator, body, account_id);
        errdefer allowances.deinit(self.allocator);

        const balance = try mirror_parse.parseAccountBalance(self.allocator, body, account_id);
        return DetailedAccountInfo.init(info, balance, allowances);
    }

    fn getAccountInfoGrpcDetailed(self: *MirrorClient, account_id: model.AccountId) !DetailedAccountInfo {
        const request = try mirror_proto.encodeAccountInfoQuery(self.allocator, account_id);
        defer self.allocator.free(request);

        const response = try self.callGrpcUnary("/proto.CryptoService/getAccountInfo", request);
        defer self.allocator.free(response);

        const decoded = try mirror_proto.decodeAccountInfoResponse(self.allocator, response, account_id);
        errdefer decoded.info.deinit(self.allocator);

        var allowances = try self.getAccountAllowancesGrpc(account_id);
        errdefer allowances.deinit(self.allocator);

        return DetailedAccountInfo.init(decoded.info, decoded.balance, allowances);
    }

    fn getAccountAllowancesGrpc(self: *MirrorClient, account_id: model.AccountId) !model.AccountAllowances {
        const request = try mirror_proto.encodeAccountDetailsQuery(self.allocator, account_id);
        defer self.allocator.free(request);

        const response = try self.callGrpcUnary("/proto.NetworkService/getAccountDetails", request);
        defer self.allocator.free(response);

        return try mirror_proto.decodeAccountDetailsAllowances(self.allocator, response, account_id);
    }

    fn getTokenInfoRest(self: *MirrorClient, token_id: model.TokenId) !model.TokenInfo {
        const url = try self.buildUrl("{s}/tokens/{d}.{d}.{d}", .{
            self.base_url,
            token_id.shard,
            token_id.realm,
            token_id.num,
        });
        defer self.allocator.free(url);

        const body = try self.fetchJson(url);
        defer self.allocator.free(body);

        return try mirror_parse.parseTokenInfo(self.allocator, body, token_id);
    }

    fn getTokenInfoGrpc(self: *MirrorClient, token_id: model.TokenId) !model.TokenInfo {
        const request = try mirror_proto.encodeTokenInfoQuery(self.allocator, token_id);
        defer self.allocator.free(request);

        const response = try self.callGrpcUnary("/proto.TokenService/getTokenInfo", request);
        defer self.allocator.free(response);

        return try mirror_proto.decodeTokenInfoResponse(self.allocator, response, token_id);
    }

    fn getTransactionReceiptRest(
        self: *MirrorClient,
        tx_id: model.TransactionId,
        options: TransactionReceiptQueryOptions,
    ) !model.TransactionReceipt {
        self.ensureGrpcFallback("getTransactionReceipt");
        const url = try self.buildTransactionUrl(tx_id);
        defer self.allocator.free(url);

        const body = try self.fetchJson(url);
        defer self.allocator.free(body);

        if (options.include_duplicates or options.include_children) {
            log.debug("mirror REST getTransactionReceipt ignoring duplicates/children flags", .{});
        }

        return mirror_parse.parseTransactionReceipt(self.allocator, body, tx_id) catch |err| switch (err) {
            mirror_parse.ParseError.MissingField => return error.NotFound,
            else => return err,
        };
    }

    fn getTransactionReceiptGrpc(
        self: *MirrorClient,
        tx_id: model.TransactionId,
        options: TransactionReceiptQueryOptions,
    ) !model.TransactionReceipt {
        const request = try mirror_proto.encodeTransactionGetReceiptQuery(
            self.allocator,
            tx_id,
            options.include_duplicates,
            options.include_children,
        );
        defer self.allocator.free(request);

        const response = try self.callGrpcUnary("/proto.CryptoService/getTransactionReceipts", request);
        defer self.allocator.free(response);

        return try mirror_proto.decodeTransactionReceiptResponse(response, tx_id);
    }

    fn getTransactionRecordRest(
        self: *MirrorClient,
        tx_id: model.TransactionId,
        options: TransactionRecordQueryOptions,
    ) !model.TransactionRecord {
        self.ensureGrpcFallback("getTransactionRecord");
        const url = try self.buildTransactionUrl(tx_id);
        defer self.allocator.free(url);

        const body = try self.fetchJson(url);
        defer self.allocator.free(body);

        if (options.include_duplicates or options.include_children) {
            log.debug("mirror REST getTransactionRecord ignoring duplicates/children flags", .{});
        }

        return mirror_parse.parseTransactionRecord(self.allocator, body, tx_id) catch |err| switch (err) {
            mirror_parse.ParseError.MissingField => return error.NotFound,
            else => return err,
        };
    }

    fn getTransactionRecordGrpc(
        self: *MirrorClient,
        tx_id: model.TransactionId,
        options: TransactionRecordQueryOptions,
    ) !model.TransactionRecord {
        const request = try mirror_proto.encodeTransactionGetRecordQuery(
            self.allocator,
            tx_id,
            options.include_duplicates,
            options.include_children,
        );
        defer self.allocator.free(request);

        const response = try self.callGrpcUnary("/proto.CryptoService/getTxRecordByTxID", request);
        defer self.allocator.free(response);

        return try mirror_proto.decodeTransactionRecordResponse(self.allocator, response, tx_id);
    }

    fn callGrpcUnary(self: *MirrorClient, method_path: []const u8, payload: []const u8) ![]u8 {
        const client = try self.getGrpcClient();
        return try client.unary(method_path, payload, self.allocator);
    }

    fn logGrpcFallback(self: *MirrorClient, comptime feature: []const u8, err: anyerror) void {
        if (self.transport != .grpc) return;
        if (!self.grpc_fallback_logged) {
            const endpoint = if (self.grpc_endpoint) |ep| ep else self.base_url;
            log.warn(
                "mirror gRPC {s} failed via {s}: {s}; falling back to REST",
                .{ feature, endpoint, @errorName(err) },
            );
            self.grpc_fallback_logged = true;
        } else {
            log.debug("mirror gRPC {s} falling back to REST: {s}", .{ feature, @errorName(err) });
        }
    }

    fn getTopicMessagesRest(
        self: *MirrorClient,
        topic_id: model.TopicId,
        limit: usize,
        next: ?[]const u8,
    ) !struct { messages: []TopicMessage, next: ?[]u8 } {
        self.ensureGrpcFallback("getTopicMessages");
        const url = try self.buildTopicUrl(topic_id, limit, next);
        defer self.allocator.free(url);

        const body = try self.fetchJson(url);
        defer self.allocator.free(body);

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
        defer parsed.deinit();

        const root = parsed.value;
        const obj = switch (root) {
            .object => |o| o,
            else => return error.ParseError,
        };

        const messages_val = try getField(obj, "messages");
        const messages_arr = switch (messages_val) {
            .array => |arr| arr,
            else => return error.ParseError,
        };

        var result = std.ArrayList(TopicMessage).empty;
        errdefer {
            for (result.items) |*msg| msg.deinit(self.allocator);
            result.deinit(self.allocator);
        }

        try result.ensureTotalCapacityPrecise(self.allocator, messages_arr.items.len);
        for (messages_arr.items) |entry| {
            const entry_obj = try expectObject(entry);
            const seq_val = try getField(entry_obj, "sequence_number");
            const seq = switch (seq_val) {
                .integer => |i| @as(u64, @intCast(i)),
                else => return error.ParseError,
            };
            const msg_val = try getField(entry_obj, "message");
            const msg_str = switch (msg_val) {
                .string => |s| s,
                else => return error.ParseError,
            };
            const decoded = try std.base64.standard.Decoder.decodeAlloc(self.allocator, msg_str);
            var consensus_timestamp: ?model.Timestamp = null;
            if (entry_obj.get("consensus_timestamp")) |ts_val| switch (ts_val) {
                .string => |ts_str| consensus_timestamp = parseTimestampString(ts_str) catch null,
                else => {},
            };
            try result.append(self.allocator, .{ .sequence_number = seq, .message = decoded, .consensus_timestamp = consensus_timestamp });
        }

        var next_token: ?[]u8 = null;
        if (obj.get("links")) |links_val| {
            const links_obj = try expectObject(links_val);
            if (links_obj.get("next")) |next_val| {
                switch (next_val) {
                    .string => |s| {
                        if (s.len > 0) next_token = try self.allocator.dupe(u8, s);
                    },
                    .null => {},
                    else => return error.ParseError,
                }
            }
        }

        const owned = try result.toOwnedSlice(self.allocator);
        return .{ .messages = owned, .next = next_token };
    }

    fn getTopicMessagesGrpc(
        self: *MirrorClient,
        topic_id: model.TopicId,
        limit: usize,
        next: ?[]const u8,
    ) !struct { messages: []TopicMessage, next: ?[]u8 } {
        const client = try self.getGrpcClient();
        const limit_u64: ?u64 = if (limit > 0) @intCast(limit) else null;

        var start_time: ?model.Timestamp = null;
        if (next) |token| {
            start_time = try parseGrpcToken(token);
        }

        const request_bytes = try mirror_proto.encodeConsensusTopicQuery(self.allocator, topic_id, start_time, null, limit_u64);
        defer self.allocator.free(request_bytes);

        var messages = std.ArrayList(TopicMessage).empty;
        errdefer {
            for (messages.items) |*msg| msg.deinit(self.allocator);
            messages.deinit(self.allocator);
        }

        var next_timestamp: ?model.Timestamp = null;

        const Handler = struct {
            allocator: std.mem.Allocator,
            list: *std.ArrayList(TopicMessage),
            next_ts: *?model.Timestamp,
            fn handle(ctx: *@This(), payload: []const u8) !void {
                var decoded = try mirror_proto.decodeConsensusTopicResponse(ctx.allocator, payload);
                defer decoded.deinit(ctx.allocator);
                const owned = decoded.message;
                decoded.message = &[_]u8{};
                try ctx.list.append(ctx.allocator, .{
                    .sequence_number = decoded.sequence_number,
                    .message = owned,
                    .consensus_timestamp = decoded.consensus_timestamp,
                });
                ctx.next_ts.* = decoded.consensus_timestamp;
            }
        };

        const handler = Handler{ .allocator = self.allocator, .list = &messages, .next_ts = &next_timestamp };
        try client.serverStreaming(
            "/com.hedera.mirror.api.proto.ConsensusService/subscribeTopic",
            request_bytes,
            handler,
        );

        const slice = try messages.toOwnedSlice(self.allocator);
        var next_token: ?[]u8 = null;
        if (next_timestamp) |ts| {
            const advanced = advanceTimestamp(ts);
            next_token = try self.formatGrpcNextToken(advanced);
        }

        return .{ .messages = slice, .next = next_token };
    }

    fn streamTransactionsRest(
        self: *MirrorClient,
        options: TransactionStreamOptions,
        callback: TransactionStreamCallback,
    ) !void {
        var next_token: ?[]u8 = null;
        defer if (next_token) |token| self.allocator.free(token);

        var start_time = options.start_time;
        var poll_ns = options.poll_interval_ns;
        if (poll_ns == 0) poll_ns = std.time.ns_per_s;
        const effective_limit: usize = if (options.limit == 0) 25 else options.limit;

        while (true) {
            const url = try blk: {
                if (next_token) |token| break :blk try self.resolveNextUrl(token);
                break :blk try self.buildTransactionsUrlWithOptions(
                    effective_limit,
                    start_time,
                    options.include_duplicates,
                    options.include_children,
                );
            };
            defer self.allocator.free(url);

            const body = try self.fetchJson(url);
            defer self.allocator.free(body);

            var page = try mirror_parse.parseTransactionsPage(self.allocator, body);
            const page_next = page.next;
            page.next = null;

            var last_timestamp: ?model.Timestamp = null;
            var idx: usize = 0;
            while (idx < page.records.len) : (idx += 1) {
                var record_ptr = &page.records[idx];
                const consensus_ts = record_ptr.consensus_timestamp;
                callback(record_ptr) catch |err| {
                    record_ptr.deinit(self.allocator);
                    for (page.records[idx + 1 ..]) |*remaining| remaining.deinit(self.allocator);
                    if (page.records.len > 0) self.allocator.free(page.records);
                    if (page_next) |token| self.allocator.free(token);
                    return err;
                };
                record_ptr.deinit(self.allocator);
                last_timestamp = consensus_ts;
            }

            if (page.records.len > 0) self.allocator.free(page.records);

            if (next_token) |token| {
                self.allocator.free(token);
                next_token = null;
            }

            if (page_next) |token| {
                next_token = token;
            }

            if (next_token == null and last_timestamp) |ts| {
                start_time = advanceTimestamp(ts);
            }

            if (page_next == null) {
                std.time.sleep(poll_ns);
            }
        }
    }

    fn streamTransactionsGrpc(
        self: *MirrorClient,
        options: TransactionStreamOptions,
        callback: TransactionStreamCallback,
    ) !void {
        // Note: Hedera Mirror Node doesn't provide a native gRPC transaction streaming endpoint.
        // This implementation uses REST with gRPC-style retry/backoff and metrics tracking.
        // When a proper gRPC endpoint becomes available, this can be replaced with server-streaming RPC.

        var next_token: ?[]u8 = null;
        defer if (next_token) |token| self.allocator.free(token);

        var start_time = options.start_time;
        var poll_ns = options.poll_interval_ns;
        if (poll_ns == 0) poll_ns = std.time.ns_per_s;
        const effective_limit: usize = if (options.limit == 0) 25 else options.limit;

        const grpc_client = try self.getGrpcClient();
        const initial_backoff = grpc_client.options.base_backoff_ns;
        const max_backoff = grpc_client.options.max_backoff_ns;
        var current_backoff = initial_backoff;
        var consecutive_errors: usize = 0;

        while (true) {
            const url = try blk: {
                if (next_token) |token| break :blk try self.resolveNextUrl(token);
                break :blk try self.buildTransactionsUrlWithOptions(
                    effective_limit,
                    start_time,
                    options.include_duplicates,
                    options.include_children,
                );
            };
            defer self.allocator.free(url);

            const body = self.fetchJson(url) catch |err| {
                consecutive_errors += 1;
                log.warn("Transaction stream fetch failed (attempt {d}): {s}", .{ consecutive_errors, @errorName(err) });

                if (consecutive_errors > grpc_client.options.max_retries) {
                    return err;
                }

                std.time.sleep(current_backoff);
                current_backoff = @min(current_backoff * 2, max_backoff);
                continue;
            };
            defer self.allocator.free(body);

            // Reset backoff on successful fetch
            consecutive_errors = 0;
            current_backoff = initial_backoff;

            var page = try mirror_parse.parseTransactionsPage(self.allocator, body);
            const page_next = page.next;
            page.next = null;

            var last_timestamp: ?model.Timestamp = null;
            var idx: usize = 0;
            while (idx < page.records.len) : (idx += 1) {
                var record_ptr = &page.records[idx];
                const consensus_ts = record_ptr.consensus_timestamp;
                callback(record_ptr) catch |err| {
                    record_ptr.deinit(self.allocator);
                    for (page.records[idx + 1 ..]) |*remaining| remaining.deinit(self.allocator);
                    if (page.records.len > 0) self.allocator.free(page.records);
                    if (page_next) |token| self.allocator.free(token);
                    return err;
                };
                record_ptr.deinit(self.allocator);
                last_timestamp = consensus_ts;
            }

            if (page.records.len > 0) self.allocator.free(page.records);

            if (next_token) |token| {
                self.allocator.free(token);
                next_token = null;
            }

            if (page_next) |token| {
                next_token = token;
            }

            if (next_token == null and last_timestamp) |ts| {
                start_time = advanceTimestamp(ts);
            }

            if (page_next == null) {
                std.time.sleep(poll_ns);
            }
        }
    }

    fn streamTransactionsBlockStream(
        self: *MirrorClient,
        options: TransactionStreamOptions,
        callback: TransactionStreamCallback,
    ) !void {
        // Block Stream implementation using BlockStreamService.subscribeBlockStream
        // This provides native streaming from Block Nodes (HIP-1056/1081)

        const block_client = try self.getBlockStreamClient();

        // Determine starting block number
        // TODO: Convert timestamp to block number if start_time is provided
        const start_block: u64 = 0; // 0 means current/latest
        const end_block: u64 = 0; // 0 means infinite stream

        log.info("Starting block stream from block {d} (end: {d})", .{ start_block, end_block });

        // Subscribe to block stream
        try block_client.subscribeBlocks(start_block, end_block, struct {
            allocator: std.mem.Allocator,
            callback: TransactionStreamCallback,
            include_duplicates: bool,
            include_children: bool,

            pub fn handle(ctx: *@This(), block_items: []block_stream.BlockItem) !void {
                // Extract transactions from block items
                for (block_items) |item| {
                    switch (item.item_type) {
                        .event_transaction => {
                            // Parse transaction and invoke callback
                            const tx_record = try extractTransactionRecord(ctx.allocator, item.data);
                            defer tx_record.deinit(ctx.allocator);

                            // Apply filters
                            if (!ctx.include_duplicates and tx_record.is_duplicate) continue;
                            if (!ctx.include_children and tx_record.is_child) continue;

                            try ctx.callback(&tx_record);
                        },
                        else => {
                            // Skip other item types for transaction streaming
                            continue;
                        },
                    }
                }
            }
        }{
            .allocator = self.allocator,
            .callback = callback,
            .include_duplicates = options.include_duplicates,
            .include_children = options.include_children,
        });
    }

    fn getGrpcClient(self: *MirrorClient) !*grpc_web.GrpcWebClient {
        if (self.grpc_client) |*client| {
            client.setDebugPayloadLogging(self.grpc_debug_payloads);
            return client;
        }
        return error.GrpcTransportUnavailable;
    }

    fn getBlockStreamClient(self: *MirrorClient) !*block_stream.BlockStreamClient {
        if (self.block_stream_client) |*client| {
            return client;
        }
        return error.BlockStreamTransportUnavailable;
    }

    fn parseTimestampString(raw: []const u8) !model.Timestamp {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        const dot = std.mem.indexOfScalar(u8, trimmed, '.') orelse return error.InvalidTimestampToken;
        const seconds_str = trimmed[0..dot];
        const nanos_str = trimmed[dot + 1 ..];
        const seconds = try std.fmt.parseInt(i64, seconds_str, 10);
        const nanos = try std.fmt.parseInt(i64, nanos_str, 10);
        return .{ .seconds = seconds, .nanos = nanos };
    }

    fn parseGrpcToken(token: []const u8) !model.Timestamp {
        const raw = if (std.mem.startsWith(u8, token, "grpc:")) token[5..] else token;
        return try parseTimestampString(raw);
    }

    fn formatGrpcNextToken(self: *MirrorClient, ts: model.Timestamp) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "grpc:{d}.{d}", .{ ts.seconds, ts.nanos });
    }

    fn advanceTimestamp(ts: model.Timestamp) model.Timestamp {
        var result = ts;
        result.nanos += 1;
        if (result.nanos >= 1_000_000_000) {
            result.nanos -= 1_000_000_000;
            result.seconds += 1;
        }
        return result;
    }

    fn ensureGrpcFallback(self: *MirrorClient, comptime feature: []const u8) void {
        if (self.transport != .grpc) return;
        if (!self.grpc_fallback_logged) {
            const endpoint = if (self.grpc_endpoint) |ep| ep else self.base_url;
            log.warn("mirror gRPC transport not yet available for {s}; falling back to REST via {s}", .{ feature, endpoint });
            self.grpc_fallback_logged = true;
        }
    }

    fn buildUrl(self: *MirrorClient, comptime pattern: []const u8, args: anytype) ![]u8 {
        return fmt.allocPrint(self.allocator, pattern, args);
    }

    fn buildTransactionUrl(self: *MirrorClient, tx_id: model.TransactionId) ![]u8 {
        return fmt.allocPrint(self.allocator, "{s}/transactions/{}.{}", .{
            self.base_url,
            tx_id.valid_start.seconds,
            tx_id.valid_start.nanos,
        });
    }

    fn buildTransactionsUrl(
        self: *MirrorClient,
        limit: usize,
        start: ?model.Timestamp,
    ) ![]u8 {
        return self.buildTransactionsUrlWithOptions(limit, start, false, false);
    }

    fn buildTransactionsUrlWithOptions(
        self: *MirrorClient,
        limit: usize,
        start: ?model.Timestamp,
        include_duplicates: bool,
        include_children: bool,
    ) ![]u8 {
        const dup_param = if (include_duplicates) "&nonce=ne:0" else "";
        const child_param = if (include_children) "&scheduled=true" else "";

        if (start) |ts| {
            return fmt.allocPrint(self.allocator, "{s}/transactions?limit={d}&order=asc&timestamp=gt:{d}.{d}{s}{s}", .{
                self.base_url,
                limit,
                ts.seconds,
                ts.nanos,
                dup_param,
                child_param,
            });
        }
        return fmt.allocPrint(self.allocator, "{s}/transactions?limit={d}&order=asc{s}{s}", .{
            self.base_url,
            limit,
            dup_param,
            child_param,
        });
    }

    fn buildTopicUrl(self: *MirrorClient, topic_id: model.TopicId, limit: usize, next: ?[]const u8) ![]u8 {
        if (next) |token| {
            return fmt.allocPrint(self.allocator, "{s}/topics/{d}.{d}.{d}/messages?limit={d}&timestamp={s}", .{
                self.base_url,
                topic_id.shard,
                topic_id.realm,
                topic_id.num,
                limit,
                token,
            });
        }
        return fmt.allocPrint(self.allocator, "{s}/topics/{d}.{d}.{d}/messages?limit={d}", .{
            self.base_url,
            topic_id.shard,
            topic_id.realm,
            topic_id.num,
            limit,
        });
    }

    fn buildTokenAllowanceUrl(
        self: *MirrorClient,
        account_id: model.AccountId,
        options: TokenAllowanceQueryOptions,
    ) ![]u8 {
        if (options.next) |next| {
            return try self.resolveNextUrl(next);
        }

        var builder: std.ArrayList(u8) = .{};
        errdefer builder.deinit(self.allocator);

        try builder.print(self.allocator, "{s}/accounts/{d}.{d}.{d}/allowances/tokens", .{
            self.base_url,
            account_id.shard,
            account_id.realm,
            account_id.num,
        });

        var has_query = false;
        if (options.limit) |limit| try appendQueryParam(&builder, self.allocator, &has_query, "limit", "{d}", .{limit});
        if (options.token_id) |token_id| try appendQueryParam(&builder, self.allocator, &has_query, "token.id", "{d}.{d}.{d}", .{ token_id.shard, token_id.realm, token_id.num });
        if (options.spender) |spender| try appendQueryParam(&builder, self.allocator, &has_query, "spender.id", "{d}.{d}.{d}", .{ spender.shard, spender.realm, spender.num });

        return try builder.toOwnedSlice(self.allocator);
    }

    fn buildTokenNftAllowanceUrl(
        self: *MirrorClient,
        account_id: model.AccountId,
        options: TokenNftAllowanceQueryOptions,
    ) ![]u8 {
        if (options.next) |next| {
            return try self.resolveNextUrl(next);
        }

        var builder: std.ArrayList(u8) = .{};
        errdefer builder.deinit(self.allocator);

        try builder.print(self.allocator, "{s}/accounts/{d}.{d}.{d}/allowances/nfts", .{
            self.base_url,
            account_id.shard,
            account_id.realm,
            account_id.num,
        });

        var has_query = false;
        if (options.limit) |limit| try appendQueryParam(&builder, self.allocator, &has_query, "limit", "{d}", .{limit});
        if (options.token_id) |token_id| try appendQueryParam(&builder, self.allocator, &has_query, "token.id", "{d}.{d}.{d}", .{ token_id.shard, token_id.realm, token_id.num });
        if (options.spender) |spender| try appendQueryParam(&builder, self.allocator, &has_query, "spender.id", "{d}.{d}.{d}", .{ spender.shard, spender.realm, spender.num });
        if (options.approved_for_all) |flag| try appendQueryParam(&builder, self.allocator, &has_query, "approvedForAll", "{s}", .{if (flag) "true" else "false"});
        if (options.serial_number) |serial| try appendQueryParam(&builder, self.allocator, &has_query, "serialNumber", "{d}", .{serial});

        return try builder.toOwnedSlice(self.allocator);
    }

    fn resolveNextUrl(self: *MirrorClient, next: []const u8) ![]u8 {
        if (next.len == 0) {
            return try self.allocator.dupe(u8, self.base_url);
        }

        if (mem.startsWith(u8, next, "http://") or mem.startsWith(u8, next, "https://")) {
            return try self.allocator.dupe(u8, next);
        }

        const api_prefix = "/api/v1";
        if (mem.startsWith(u8, next, api_prefix)) {
            const suffix = next[api_prefix.len..];
            if (suffix.len == 0) {
                return try self.allocator.dupe(u8, self.base_url);
            }
            if (suffix[0] == '?') {
                return try fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, suffix });
            }
            if (suffix[0] == '/') {
                return try fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, suffix });
            }
            return try fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.base_url, suffix });
        }

        if (next[0] == '?') {
            return try fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, next });
        }

        if (next[0] == '/') {
            return try fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, next });
        }

        return try fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.base_url, next });
    }

    fn fetchJson(self: *MirrorClient, url: []const u8) ![]u8 {
        return try self.fetch(url, "application/json");
    }

    fn fetch(self: *MirrorClient, url: []const u8, accept: ?[]const u8) ![]u8 {
        const uri = try std.Uri.parse(url);

        const extra_headers: []const std.http.Header = if (accept) |value|
            &[_]std.http.Header{.{ .name = "accept", .value = value }}
        else
            &[_]std.http.Header{};

        var request = try self.http_client.request(.GET, uri, .{ .extra_headers = extra_headers });
        defer request.deinit();

        try request.sendBodiless();
        var buf: [4096]u8 = undefined;
        var response = try request.receiveHead(&buf);

        if (response.head.status != .ok) {
            return error.HttpError;
        }

        var transfer_buf: [4096]u8 = undefined;
        var reader = response.reader(&transfer_buf);

        return reader.allocRemaining(self.allocator, std.Io.Limit.limited(4 * 1024 * 1024)) catch return error.ReadError;
    }
};

fn appendQueryParam(
    builder: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    has_query: *bool,
    comptime name: []const u8,
    comptime value_fmt: []const u8,
    args: anytype,
) !void {
    if (!has_query.*) {
        try builder.append(allocator, '?');
        has_query.* = true;
    } else {
        try builder.append(allocator, '&');
    }
    try builder.print(allocator, "{s}=", .{name});
    try builder.print(allocator, value_fmt, args);
}

fn expectObject(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |obj| obj,
        else => error.ParseError,
    };
}

fn getField(obj: std.json.ObjectMap, name: []const u8) !std.json.Value {
    return obj.get(name) orelse error.ParseError;
}

pub const AccountInfo = struct {
    account_id: model.AccountId,
    balance: model.Hbar,
};

pub const TransactionInfo = struct {
    transaction_id: model.TransactionId,
    successful: bool,
};

pub const TopicMessage = struct {
    sequence_number: u64,
    message: []u8,
    consensus_timestamp: ?model.Timestamp = null,

    pub fn deinit(self: *TopicMessage, allocator: std.mem.Allocator) void {
        if (self.message.len > 0) allocator.free(self.message);
        self.message = @constCast((&[_]u8{})[0..]);
        self.consensus_timestamp = null;
    }
};


// Helper function to extract TransactionRecord from block stream data
fn extractTransactionRecord(allocator: std.mem.Allocator, data: []const u8) !model.TransactionRecord {
    // TODO: Implement full protobuf parsing of event_transaction BlockItem
    // For now, return a stub record
    _ = data;
    return model.TransactionRecord{
        .transaction_id = model.TransactionId{
            .account_id = model.AccountId{ .shard = 0, .realm = 0, .num = 0 },
            .valid_start = model.Timestamp{ .seconds = 0, .nanos = 0 },
            .scheduled = false,
            .nonce = null,
        },
        .consensus_timestamp = model.Timestamp{ .seconds = 0, .nanos = 0 },
        .transfers = &[_]model.Transfer{},
        .memo = try allocator.dupe(u8, ""),
        .fee = model.Hbar.ZERO,
        .result = .SUCCESS,
        .is_duplicate = false,
        .is_child = false,
    };
}

