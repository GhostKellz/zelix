//! Configuration helpers for Zelix clients.

const std = @import("std");
const model = @import("model.zig");
const crypto = @import("crypto.zig");

const mem = std.mem;
const ascii = std.ascii;
const fmt = std.fmt;
const json = std.json;

pub const Error = error{
    InvalidConfig,
    InvalidNetwork,
    InvalidKey,
    MissingField,
};

pub const Node = struct {
    account_id: model.AccountId,
    address: []u8,

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        if (self.address.len > 0) allocator.free(self.address);
        self.address = "";
    }
};

pub const Operator = struct {
    account_id: model.AccountId,
    private_key: crypto.PrivateKey,
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    network: model.Network,
    nodes: std.ArrayList(Node),
    mirror_url: []u8,
    operator: ?Operator,
    grpc_debug_payloads: bool,

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .allocator = allocator,
            .network = .testnet,
            .nodes = std.ArrayList(Node).empty,
            .mirror_url = "",
            .operator = null,
            .grpc_debug_payloads = false,
        };
    }

    pub fn deinit(self: *Config) void {
        clearNodes(self);
        self.nodes.deinit(self.allocator);
        if (self.mirror_url.len > 0) self.allocator.free(self.mirror_url);
        self.mirror_url = "";
        self.operator = null;
        self.grpc_debug_payloads = false;
    }

    pub fn setMirrorUrl(self: *Config, url: []const u8) !void {
        const copy = try self.allocator.dupe(u8, url);
        setMirrorUrlOwned(self, copy);
    }

    pub fn loadFromEnv(allocator: std.mem.Allocator) !Config {
        var cfg = Config.init(allocator);
        errdefer cfg.deinit();

        const network_name = mem.trim(u8, std.posix.getenv("HEDERA_NETWORK") orelse "testnet", " \t\r\n");
        cfg.network = try parseNetworkName(network_name);
        try appendDefaultNodes(&cfg, cfg.network);

        if (std.posix.getenv("HEDERA_MIRROR_URL")) |mirror_url_raw| {
            const trimmed = mem.trim(u8, mirror_url_raw, " \t\r\n");
            const resolved = try buildMirrorUrl(cfg.allocator, trimmed, cfg.network);
            setMirrorUrlOwned(&cfg, resolved);
        } else if (std.posix.getenv("HEDERA_MIRROR_NETWORK")) |mirror_network| {
            const trimmed = mem.trim(u8, mirror_network, " \t\r\n");
            const resolved = try buildMirrorUrl(cfg.allocator, trimmed, cfg.network);
            setMirrorUrlOwned(&cfg, resolved);
        } else {
            try cfg.setMirrorUrl(defaultMirrorUrl(cfg.network));
        }

        const operator_id = std.posix.getenv("HEDERA_OPERATOR_ID");
        const operator_key = std.posix.getenv("HEDERA_OPERATOR_KEY");
        if ((operator_id != null) != (operator_key != null)) return Error.MissingField;
        if (operator_id) |id_raw| {
            cfg.operator = try parseOperator(allocator, id_raw, operator_key.?);
        }

        if (std.posix.getenv("ZELIX_GRPC_DEBUG_PAYLOADS")) |debug_raw| {
            cfg.grpc_debug_payloads = parseBool(debug_raw);
        }

        return cfg;
    }

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        var cfg = Config.init(allocator);
        errdefer cfg.deinit();

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const data = try file.readToEndAlloc(allocator, 4 * 1024 * 1024);
        defer allocator.free(data);

        var parsed = try json.parseFromSlice(json.Value, allocator, data, .{});
        defer parsed.deinit();

        const root = parsed.value;
        const obj = switch (root) {
            .object => |o| o,
            else => return Error.InvalidConfig,
        };

        if (obj.get("network")) |network_value| {
            try parseNetworkField(&cfg, network_value);
        } else {
            try appendDefaultNodes(&cfg, cfg.network);
        }

        if (obj.get("mirrorNetwork")) |mirror_value| {
            const resolved = try parseMirrorField(&cfg, mirror_value);
            setMirrorUrlOwned(&cfg, resolved);
        } else {
            try cfg.setMirrorUrl(defaultMirrorUrl(cfg.network));
        }

        if (obj.get("operator")) |operator_value| {
            cfg.operator = try parseOperatorObject(allocator, operator_value);
        }

        if (obj.get("grpcDebugPayloads")) |debug_value| {
            cfg.grpc_debug_payloads = try parseDebugField(debug_value);
        }

        return cfg;
    }

    pub fn forNetwork(allocator: std.mem.Allocator, network: model.Network) !Config {
        var cfg = Config.init(allocator);
        errdefer cfg.deinit();
        cfg.network = network;
        try appendDefaultNodes(&cfg, network);
        try cfg.setMirrorUrl(defaultMirrorUrl(network));
        cfg.grpc_debug_payloads = false;
        return cfg;
    }
};

fn setMirrorUrlOwned(cfg: *Config, url: []u8) void {
    if (cfg.mirror_url.len > 0) cfg.allocator.free(cfg.mirror_url);
    cfg.mirror_url = url;
}

fn clearNodes(cfg: *Config) void {
    for (cfg.nodes.items) |*node| node.deinit(cfg.allocator);
    cfg.nodes.clearRetainingCapacity();
}

fn appendDefaultNodes(cfg: *Config, network: model.Network) !void {
    clearNodes(cfg);
    const seeds = switch (network) {
        .mainnet => &mainnet_seeds,
        .testnet => &testnet_seeds,
        .previewnet => &previewnet_seeds,
        .custom => return,
    };

    for (seeds.*) |seed| {
        const account_id = try model.AccountId.fromString(seed.account);
        try appendNode(cfg, account_id, seed.address);
    }
}

fn appendNode(cfg: *Config, account_id: model.AccountId, address: []const u8) !void {
    const copy = try cfg.allocator.dupe(u8, address);
    errdefer cfg.allocator.free(copy);
    try cfg.nodes.append(cfg.allocator, .{ .account_id = account_id, .address = copy });
}

fn parseNetworkField(cfg: *Config, value: json.Value) !void {
    clearNodes(cfg);
    switch (value) {
        .string => |name| {
            cfg.network = try parseNetworkName(mem.trim(u8, name, " \t\r\n"));
            try appendDefaultNodes(cfg, cfg.network);
        },
        .object => |map| {
            cfg.network = .custom;
            var it = map.iterator();
            while (it.next()) |entry| {
                const address_value = entry.value_ptr.*;
                const address_str = switch (address_value) {
                    .string => |s| s,
                    else => return Error.InvalidConfig,
                };
                const account_id = try model.AccountId.fromString(entry.key_ptr.*);
                try appendNode(cfg, account_id, mem.trim(u8, address_str, " \t\r\n"));
            }
            if (cfg.nodes.items.len == 0) return Error.InvalidConfig;
        },
        else => return Error.InvalidConfig,
    }
}

fn parseMirrorField(cfg: *Config, value: json.Value) ![]u8 {
    switch (value) {
        .string => |s| {
            return try buildMirrorUrl(cfg.allocator, mem.trim(u8, s, " \t\r\n"), cfg.network);
        },
        .array => |arr| {
            for (arr.items) |item| {
                if (item == .string) {
                    return try buildMirrorUrl(cfg.allocator, mem.trim(u8, item.string, " \t\r\n"), cfg.network);
                }
            }
            return Error.InvalidConfig;
        },
        else => return Error.InvalidConfig,
    }
}

fn parseOperatorObject(allocator: std.mem.Allocator, value: json.Value) !Operator {
    const obj = switch (value) {
        .object => |o| o,
        else => return Error.InvalidConfig,
    };
    const account_value = obj.get("accountId") orelse return Error.MissingField;
    const key_value = obj.get("privateKey") orelse return Error.MissingField;
    const account_str = switch (account_value) {
        .string => |s| s,
        else => return Error.InvalidConfig,
    };
    const key_str = switch (key_value) {
        .string => |s| s,
        else => return Error.InvalidConfig,
    };
    return parseOperator(allocator, account_str, key_str);
}

fn parseOperator(allocator: std.mem.Allocator, account_raw: []const u8, key_raw: []const u8) !Operator {
    const account_id = try model.AccountId.fromString(mem.trim(u8, account_raw, " \t\r\n"));
    const private_key = try parsePrivateKey(allocator, key_raw);
    return Operator{ .account_id = account_id, .private_key = private_key };
}

fn parseDebugField(value: json.Value) !bool {
    return switch (value) {
        .bool => |flag| flag,
        .string => |raw| parseBool(raw),
        .integer => |num| num != 0,
        .float => |num| num != 0,
        else => Error.InvalidConfig,
    };
}

fn parseBool(raw: []const u8) bool {
    const trimmed = mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return false;
    if (ascii.eqlIgnoreCase(trimmed, "1")) return true;
    if (ascii.eqlIgnoreCase(trimmed, "true")) return true;
    if (ascii.eqlIgnoreCase(trimmed, "yes")) return true;
    if (ascii.eqlIgnoreCase(trimmed, "on")) return true;
    if (ascii.eqlIgnoreCase(trimmed, "enable")) return true;
    if (ascii.eqlIgnoreCase(trimmed, "0")) return false;
    if (ascii.eqlIgnoreCase(trimmed, "false")) return false;
    if (ascii.eqlIgnoreCase(trimmed, "no")) return false;
    if (ascii.eqlIgnoreCase(trimmed, "off")) return false;
    return false;
}

fn parsePrivateKey(allocator: std.mem.Allocator, raw_key: []const u8) !crypto.PrivateKey {
    var key = mem.trim(u8, raw_key, " \t\r\n");
    if (key.len == 0) return Error.InvalidKey;

    if (mem.startsWith(u8, key, "-----BEGIN")) {
        return crypto.PrivateKey.fromPem(allocator, key) catch Error.InvalidKey;
    }

    if (key.len >= 2 and key[0] == '0' and (key[1] == 'x' or key[1] == 'X')) {
        key = key[2..];
    }

    if (key.len == 64) {
        return crypto.PrivateKey.fromHex(key) catch Error.InvalidKey;
    }

    if (key.len % 2 != 0) return Error.InvalidKey;

    const buffer = try allocator.alloc(u8, key.len / 2);
    defer allocator.free(buffer);
    _ = fmt.hexToBytes(buffer, key) catch return Error.InvalidKey;

    return crypto.PrivateKey.fromDer(buffer) catch Error.InvalidKey;
}

fn buildMirrorUrl(allocator: std.mem.Allocator, raw: []const u8, fallback: model.Network) ![]u8 {
    if (raw.len == 0) return allocator.dupe(u8, defaultMirrorUrl(fallback));

    if (ascii.eqlIgnoreCase(raw, "mainnet")) return allocator.dupe(u8, defaultMirrorUrl(.mainnet));
    if (ascii.eqlIgnoreCase(raw, "testnet")) return allocator.dupe(u8, defaultMirrorUrl(.testnet));
    if (ascii.eqlIgnoreCase(raw, "previewnet")) return allocator.dupe(u8, defaultMirrorUrl(.previewnet));

    if (mem.startsWith(u8, raw, "http://") or mem.startsWith(u8, raw, "https://")) {
        return allocator.dupe(u8, raw);
    }

    if (mem.endsWith(u8, raw, "/api/v1")) {
        return fmt.allocPrint(allocator, "https://{s}", .{raw});
    }

    return fmt.allocPrint(allocator, "https://{s}/api/v1", .{raw});
}

fn parseNetworkName(name: []const u8) !model.Network {
    if (ascii.eqlIgnoreCase(name, "mainnet")) return .mainnet;
    if (ascii.eqlIgnoreCase(name, "testnet")) return .testnet;
    if (ascii.eqlIgnoreCase(name, "previewnet")) return .previewnet;
    if (ascii.eqlIgnoreCase(name, "custom")) return .custom;
    return Error.InvalidNetwork;
}

pub fn defaultMirrorUrl(network: model.Network) []const u8 {
    return switch (network) {
        .mainnet => "https://mainnet.mirrornode.hedera.com/api/v1",
        .testnet => "https://testnet.mirrornode.hedera.com/api/v1",
        .previewnet => "https://previewnet.mirrornode.hedera.com/api/v1",
        .custom => "https://localhost:443/api/v1",
    };
}

pub fn defaultMirrorGrpcEndpoint(network: model.Network) []const u8 {
    return switch (network) {
        .mainnet => "https://grpc.mainnet.mirrornode.hedera.com",
        .testnet => "https://grpc.testnet.mirrornode.hedera.com",
        .previewnet => "https://grpc.previewnet.mirrornode.hedera.com",
        .custom => "https://localhost:5600",
    };
}

const NodeSeed = struct {
    account: []const u8,
    address: []const u8,
};

const testnet_seeds = [_]NodeSeed{
    .{ .account = "0.0.3", .address = "0.testnet.hedera.com:50211" },
    .{ .account = "0.0.4", .address = "1.testnet.hedera.com:50211" },
    .{ .account = "0.0.5", .address = "2.testnet.hedera.com:50211" },
    .{ .account = "0.0.6", .address = "3.testnet.hedera.com:50211" },
};

const previewnet_seeds = [_]NodeSeed{
    .{ .account = "0.0.3", .address = "0.previewnet.hedera.com:50211" },
    .{ .account = "0.0.4", .address = "1.previewnet.hedera.com:50211" },
    .{ .account = "0.0.5", .address = "2.previewnet.hedera.com:50211" },
    .{ .account = "0.0.6", .address = "3.previewnet.hedera.com:50211" },
};

const mainnet_seeds = [_]NodeSeed{
    .{ .account = "0.0.3", .address = "0.mainnet.hedera.com:50211" },
    .{ .account = "0.0.4", .address = "1.mainnet.hedera.com:50211" },
    .{ .account = "0.0.5", .address = "2.mainnet.hedera.com:50211" },
    .{ .account = "0.0.6", .address = "3.mainnet.hedera.com:50211" },
};

test "parseBool handles common truthy and falsy values" {
    try std.testing.expect(parseBool("1"));
    try std.testing.expect(parseBool("true"));
    try std.testing.expect(parseBool("YES"));
    try std.testing.expect(parseBool("enable"));
    try std.testing.expect(!parseBool("0"));
    try std.testing.expect(!parseBool("false"));
    try std.testing.expect(!parseBool("no"));
    try std.testing.expect(!parseBool(""));
}
