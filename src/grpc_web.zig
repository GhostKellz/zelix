//! Minimal gRPC-Web client helper for Zelix. Uses HTTP/1.1 transport with binary framing.

const std = @import("std");

const log = std.log.scoped(.grpc_web);
const math = std.math;
const time = std.time;

pub const Error = error{
    InvalidEndpoint,
    MissingAuthority,
    GrpcError,
    HttpError,
    DeadlineExceeded,
    GrpcStatus,
};

pub const Options = struct {
    max_retries: usize = 2,
    base_backoff_ns: u64 = 200 * time.ns_per_ms,
    max_backoff_ns: u64 = 4 * time.ns_per_s,
    deadline_ns: ?u64 = null,
};

pub const Stats = struct {
    total_requests: usize = 0,
    total_retries: usize = 0,
    total_failures: usize = 0,
    last_latency_ns: u64 = 0,
    last_status_code: u32 = 0,
    last_http_status: u16 = 0,
};

pub const GrpcWebClient = struct {
    allocator: std.mem.Allocator,
    http_client: std.http.Client,
    base_uri: std.Uri,
    authority: []u8,
    path_prefix: []u8,
    options: Options = .{},
    stats: Stats = .{},
    debug_payloads: bool = false,

    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8) !GrpcWebClient {
        return try initWithOptions(allocator, endpoint, .{});
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, endpoint: []const u8, options: Options) !GrpcWebClient {
        const parsed = try std.Uri.parse(endpoint);
        if (parsed.scheme.len == 0) return Error.InvalidEndpoint;
        const host_component = parsed.host orelse return Error.MissingAuthority;
        const host_str = host_component.percent_encoded;

        const authority = try buildAuthority(allocator, host_str, parsed.port);
        errdefer allocator.free(authority);

        const prefix = try allocator.dupe(u8, parsed.path.percent_encoded);
        errdefer allocator.free(prefix);

        // Initialize threaded IO for HTTP client
        var threaded_io = std.Io.Threaded.init(allocator);

        return .{
            .allocator = allocator,
            .http_client = std.http.Client{ .allocator = allocator, .io = threaded_io.io() },
            .base_uri = parsed,
            .authority = authority,
            .path_prefix = prefix,
            .options = options,
            .stats = .{},
        };
    }

    pub fn deinit(self: *GrpcWebClient) void {
        self.http_client.deinit();
        if (self.authority.len > 0) self.allocator.free(self.authority);
        self.authority = "";
        if (self.path_prefix.len > 0) self.allocator.free(self.path_prefix);
        self.path_prefix = "";
    }

    pub fn setOptions(self: *GrpcWebClient, options: Options) void {
        self.options = options;
    }

    pub fn configureDeadline(self: *GrpcWebClient, deadline_ns: ?u64) void {
        self.options.deadline_ns = deadline_ns;
    }

    pub fn getStats(self: *const GrpcWebClient) Stats {
        return self.stats;
    }

    pub fn resetStats(self: *GrpcWebClient) void {
        self.stats = .{};
    }

    pub fn setDebugPayloadLogging(self: *GrpcWebClient, enable: bool) void {
        self.debug_payloads = enable;
    }

    pub fn unary(self: *GrpcWebClient, method_path: []const u8, request_payload: []const u8, response_allocator: std.mem.Allocator) ![]u8 {
        var frames: std.ArrayList(u8) = .{};
        errdefer frames.deinit(response_allocator);

        try self.serverStreaming(method_path, request_payload, struct {
            allocator: std.mem.Allocator,
            list: *std.ArrayList(u8),
            fn handle(ctx: *@This(), message: []const u8) !void {
                try ctx.list.appendSlice(ctx.allocator, message);
            }
        }{ .allocator = response_allocator, .list = &frames });

        return frames.toOwnedSlice(response_allocator);
    }

    pub fn serverStreaming(self: *GrpcWebClient, method_path: []const u8, request_payload: []const u8, handler: anytype) !void {
        var handler_instance = handler;
        const full_path = try self.joinPath(method_path);
        defer self.allocator.free(full_path);

        const start_ns = time.nanoTimestamp();
        if (self.debug_payloads) {
            log.debug("grpc-web request {s} ({d} bytes)", .{ full_path, request_payload.len });
        }
        var attempt: usize = 0;
        var last_err: ?anyerror = null;

        while (attempt <= self.options.max_retries) : (attempt += 1) {
            if (self.options.deadline_ns) |deadline| {
                if (elapsedSince(start_ns) >= deadline) {
                    self.stats.total_failures += 1;
                    return Error.DeadlineExceeded;
                }
            }

            const attempt_start = time.nanoTimestamp();
            const outcome = self.attemptStreaming(full_path, request_payload, &handler_instance) catch |err| {
                self.stats.total_failures += 1;
                last_err = err;
                log.warn("gRPC-web attempt {d} failed: {s}", .{ attempt + 1, @errorName(err) });
                if (attempt == self.options.max_retries) return err;
                self.stats.total_retries += 1;
                self.sleepBackoff(attempt);
                continue;
            };

            self.stats.total_requests += 1;
            self.stats.last_latency_ns = elapsedBetween(attempt_start, time.nanoTimestamp());
            self.stats.last_status_code = outcome.grpc_status;
            self.stats.last_http_status = outcome.http_status_code;
            if (self.debug_payloads) {
                log.debug(
                    "grpc-web response {s} attempt {d}: grpc={d} http={d} bytes={d}",
                    .{ full_path, attempt + 1, outcome.grpc_status, outcome.http_status_code, outcome.bytes_received },
                );
            }

            if (outcome.grpc_status == 0 and outcome.http_status_code < 400) {
                log.info("gRPC-web attempt {d} succeeded (grpc={d} http={d})", .{
                    attempt + 1,
                    outcome.grpc_status,
                    outcome.http_status_code,
                });
                return;
            }

            last_err = if (outcome.grpc_status != 0) Error.GrpcStatus else Error.HttpError;
            self.stats.total_failures += 1;
            log.warn("gRPC-web attempt {d} returned grpc={d} http={d}", .{
                attempt + 1,
                outcome.grpc_status,
                outcome.http_status_code,
            });

            if (attempt == self.options.max_retries) {
                return last_err.?;
            }

            self.stats.total_retries += 1;
            self.sleepBackoff(attempt);
        }

        return last_err orelse Error.GrpcError;
    }

    fn attemptStreaming(self: *GrpcWebClient, full_path: []const u8, request_payload: []const u8, handler: anytype) !AttemptOutcome {
        const extra_headers = [_]std.http.Header{
            .{ .name = "content-type", .value = "application/grpc-web+proto" },
            .{ .name = "x-grpc-web", .value = "1" },
            .{ .name = "x-user-agent", .value = "zelix-grpc-web/0.1" },
            .{ .name = "te", .value = "trailers" },
            .{ .name = "grpc-accept-encoding", .value = "identity" },
            .{ .name = "accept", .value = "application/grpc-web+proto" },
            .{ .name = "host", .value = self.authority },
        };

        var uri = self.base_uri;
        uri.path = full_path;
        uri.query = "";
        uri.fragment = "";

        const framed = try frameRequest(self.allocator, request_payload);
        defer self.allocator.free(framed);

        var request = try self.http_client.request(.POST, uri, .{ .extra_headers = &extra_headers });
        defer request.deinit();

        try request.start();
        try request.writeAll(framed);
        try request.finish();

        const http_status_code: u16 = @intFromEnum(request.response.status);

        var parser = FrameParser.init(self.allocator);
        defer parser.deinit();

        var reader = request.reader();
        while (true) {
            var buf: [8 * 1024]u8 = undefined;
            const read_bytes = try reader.read(&buf);
            if (read_bytes == 0) break;
            try parser.feed(buf[0..read_bytes], handler);
        }

        if (request.response.headers.getFirstValue("grpc-status")) |status_str| {
            parser.setStatusFromHeader(status_str);
        }
        if (parser.grpc_message == null) {
            if (request.response.headers.getFirstValue("grpc-message")) |msg_str| {
                parser.setMessageFromHeader(self.allocator, msg_str) catch {};
            }
        }

        const status_code = parser.grpc_status orelse 0;
        if (status_code != 0) {
            if (parser.grpc_message) |msg| {
                log.warn("gRPC status {d}: {s}", .{ status_code, msg });
            } else {
                log.warn("gRPC status {d}", .{status_code});
            }
        }

        return AttemptOutcome{
            .grpc_status = status_code,
            .http_status_code = http_status_code,
            .bytes_received = parser.bytesConsumed(),
        };
    }

    fn sleepBackoff(self: *GrpcWebClient, attempt: usize) void {
        const backoff = self.computeBackoff(attempt);
        if (backoff == 0) return;
        time.sleep(backoff);
    }

    fn computeBackoff(self: *const GrpcWebClient, attempt: usize) u64 {
        if (self.options.base_backoff_ns == 0) return 0;
        const attempt_limit: usize = 20;
        const bounded = if (attempt > attempt_limit) attempt_limit else attempt;
        const shift_amt: u6 = @intCast(bounded);
        const scale = (@as(u64, 1) << shift_amt);
        const raw = self.options.base_backoff_ns * scale;
        return if (raw > self.options.max_backoff_ns) self.options.max_backoff_ns else raw;
    }

    fn joinPath(self: *GrpcWebClient, method_path: []const u8) ![]u8 {
        if (self.path_prefix.len == 0 or std.mem.eql(u8, self.path_prefix, "/")) {
            return self.allocator.dupe(u8, method_path);
        }
        if (self.path_prefix[self.path_prefix.len - 1] == '/') {
            if (method_path.len > 0 and method_path[0] == '/') {
                return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.path_prefix, method_path[1..] });
            }
            return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.path_prefix, method_path });
        }
        if (method_path.len > 0 and method_path[0] == '/') {
            return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.path_prefix, method_path });
        }
        return std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.path_prefix, method_path });
    }
};

const AttemptOutcome = struct {
    grpc_status: u32,
    http_status_code: u16,
    bytes_received: usize,
};

fn elapsedSince(start: i128) u64 {
    const now = time.nanoTimestamp();
    const delta = now - start;
    if (delta <= 0) return 0;
    if (delta > math.maxInt(u64)) return math.maxInt(u64);
    return @intCast(delta);
}

fn elapsedBetween(start: i128, end: i128) u64 {
    const delta = end - start;
    if (delta <= 0) return 0;
    if (delta > math.maxInt(u64)) return math.maxInt(u64);
    return @intCast(delta);
}

fn frameRequest(allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    const total = payload.len + 5;
    var framed = try allocator.alloc(u8, total);
    framed[0] = 0;
    std.mem.writeInt(u32, framed[1..5], @intCast(payload.len), .big);
    @memcpy(framed[5..], payload);
    return framed;
}

fn buildAuthority(allocator: std.mem.Allocator, host: []const u8, port: ?u16) ![]u8 {
    if (port) |p| {
        switch (p) {
            0, 80, 443 => return allocator.dupe(u8, host),
            else => return std.fmt.allocPrint(allocator, "{s}:{d}", .{ host, p }),
        }
    }
    return allocator.dupe(u8, host);
}

const FrameParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    grpc_status: ?u32 = null,
    grpc_message: ?[]u8 = null,
    total_bytes: usize = 0,

    fn init(allocator: std.mem.Allocator) FrameParser {
        return .{
            .allocator = allocator,
            .buffer = .{},
            .grpc_status = null,
            .grpc_message = null,
        };
    }

    fn deinit(self: *FrameParser) void {
        if (self.grpc_message) |msg| self.allocator.free(msg);
        self.grpc_message = null;
        self.buffer.deinit(self.allocator);
    }

    fn feed(self: *FrameParser, chunk: []const u8, handler: anytype) !void {
        try self.buffer.appendSlice(self.allocator, chunk);
        self.total_bytes += chunk.len;
        while (true) {
            if (self.buffer.items.len < 5) break;
            const flag = self.buffer.items[0];
            const length = std.mem.readInt(u32, self.buffer.items[1..5], .big);
            if (self.buffer.items.len < 5 + length) break;

            const message = self.buffer.items[5 .. 5 + length];
            if ((flag & 0x80) != 0) {
                try self.processTrailer(message);
            } else {
                try handler.handle(message);
            }
            try self.buffer.replaceRange(self.allocator, 0, 5 + length, &.{});
        }
    }

    fn processTrailer(self: *FrameParser, data: []const u8) !void {
        const text = try self.allocator.dupe(u8, data);
        defer self.allocator.free(text);

        var it = std.mem.tokenizeAny(u8, text, "\r\n");
        while (it.next()) |line| {
            const sep = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const name = std.mem.trim(u8, line[0..sep], " \t");
            const value_slice = std.mem.trim(u8, line[sep + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(name, "grpc-status")) {
                self.grpc_status = std.fmt.parseInt(u32, value_slice, 10) catch self.grpc_status;
            } else if (std.ascii.eqlIgnoreCase(name, "grpc-message")) {
                if (self.grpc_message) |prev| self.allocator.free(prev);
                self.grpc_message = try self.allocator.dupe(u8, value_slice);
            }
        }
    }

    fn setStatusFromHeader(self: *FrameParser, value: []const u8) void {
        self.grpc_status = std.fmt.parseInt(u32, value, 10) catch self.grpc_status;
    }

    fn setMessageFromHeader(self: *FrameParser, allocator: std.mem.Allocator, value: []const u8) !void {
        if (self.grpc_message) |prev| allocator.free(prev);
        self.grpc_message = try allocator.dupe(u8, value);
    }

    fn bytesConsumed(self: *const FrameParser) usize {
        return self.total_bytes;
    }
};
