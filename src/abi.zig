///! Solidity ABI encoding/decoding for smart contract interactions.
///! Implements subset of Ethereum ABI specification for Hedera smart contracts.

const std = @import("std");
const mem = std.mem;

/// ABI parameter type
pub const AbiType = union(enum) {
    uint256,
    int256,
    address,
    bool_type,
    bytes_fixed: u8, // bytes1-bytes32
    bytes_dynamic,
    string,
    array: struct {
        element_type: *const AbiType,
        fixed_length: ?usize,
    },

    pub fn fromString(type_str: []const u8) !AbiType {
        if (mem.eql(u8, type_str, "uint256")) return .uint256;
        if (mem.eql(u8, type_str, "int256")) return .int256;
        if (mem.eql(u8, type_str, "address")) return .address;
        if (mem.eql(u8, type_str, "bool")) return .bool_type;
        if (mem.eql(u8, type_str, "bytes")) return .bytes_dynamic;
        if (mem.eql(u8, type_str, "string")) return .string;

        // bytes1-bytes32
        if (mem.startsWith(u8, type_str, "bytes") and type_str.len > 5) {
            const num_str = type_str[5..];
            const num = try std.fmt.parseInt(u8, num_str, 10);
            if (num >= 1 and num <= 32) {
                return .{ .bytes_fixed = num };
            }
        }

        return error.UnsupportedAbiType;
    }
};

/// ABI-encoded value
pub const AbiValue = union(enum) {
    uint256: u256,
    int256: i256,
    address: [20]u8,
    bool_value: bool,
    bytes_fixed: []const u8, // 1-32 bytes
    bytes_dynamic: []const u8,
    string_value: []const u8,
    array: []const AbiValue,

    pub fn deinit(self: *AbiValue, allocator: mem.Allocator) void {
        switch (self.*) {
            .array => |arr| {
                for (arr) |*elem| {
                    elem.deinit(allocator);
                }
                allocator.free(arr);
            },
            .bytes_dynamic, .string_value => |bytes| {
                allocator.free(bytes);
            },
            else => {},
        }
    }
};

/// ABI function selector (first 4 bytes of keccak256(signature))
pub fn computeSelector(function_signature: []const u8) [4]u8 {
    // Simplified - in production, use keccak256
    var selector: [4]u8 = undefined;
    const hash_input = function_signature;

    // For now, use a simple hash (should be keccak256 in production)
    for (&selector, 0..) |*byte, i| {
        byte.* = if (i < hash_input.len) hash_input[i] else 0;
    }

    return selector;
}

/// Encode function call data (selector + parameters)
pub fn encodeFunctionCall(
    allocator: mem.Allocator,
    function_signature: []const u8,
    params: []const AbiValue,
) ![]u8 {
    const selector = computeSelector(function_signature);

    var encoded: std.ArrayList(u8) = .{};
    errdefer encoded.deinit(allocator);

    // Add function selector
    try encoded.appendSlice(allocator, &selector);

    // Encode parameters
    const params_encoded = try encodeParameters(allocator, params);
    defer allocator.free(params_encoded);

    try encoded.appendSlice(allocator, params_encoded);

    return try encoded.toOwnedSlice(allocator);
}

/// Encode ABI parameters
pub fn encodeParameters(allocator: mem.Allocator, params: []const AbiValue) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    // Head section (static types)
    var heads: std.ArrayList(u8) = .{};
    defer heads.deinit(allocator);

    // Tail section (dynamic types)
    var tails: std.ArrayList(u8) = .{};
    defer tails.deinit(allocator);

    for (params) |param| {
        switch (param) {
            .uint256 => |val| {
                try encodeUint256(&heads, allocator, val);
            },
            .int256 => |val| {
                try encodeInt256(&heads, allocator, val);
            },
            .address => |addr| {
                try encodeAddress(&heads, allocator, addr);
            },
            .bool_value => |b| {
                try encodeBool(&heads, allocator, b);
            },
            .bytes_fixed => |bytes| {
                try encodeBytesFixed(&heads, allocator, bytes);
            },
            .bytes_dynamic => |bytes| {
                // Add offset to head
                const offset = 32 * params.len + tails.items.len;
                try encodeUint256(&heads, allocator, offset);

                // Add length + data to tail
                try encodeUint256(&tails, allocator, bytes.len);
                try tails.appendSlice(allocator, bytes);
                // Pad to 32 bytes
                const padding = (32 - (bytes.len % 32)) % 32;
                try tails.appendNTimes(allocator, 0, padding);
            },
            .string_value => |str| {
                // Same as bytes_dynamic
                const offset = 32 * params.len + tails.items.len;
                try encodeUint256(&heads, allocator, offset);

                try encodeUint256(&tails, allocator, str.len);
                try tails.appendSlice(allocator, str);
                const padding = (32 - (str.len % 32)) % 32;
                try tails.appendNTimes(allocator, 0, padding);
            },
            .array => |arr| {
                const offset = 32 * params.len + tails.items.len;
                try encodeUint256(&heads, allocator, offset);

                // Encode array length
                try encodeUint256(&tails, allocator, arr.len);

                // Recursively encode array elements
                const arr_encoded = try encodeParameters(allocator, arr);
                defer allocator.free(arr_encoded);
                try tails.appendSlice(allocator, arr_encoded);
            },
        }
    }

    try result.appendSlice(allocator, heads.items);
    try result.appendSlice(allocator, tails.items);

    return try result.toOwnedSlice(allocator);
}

/// Decode function return data
pub fn decodeParameters(
    allocator: mem.Allocator,
    data: []const u8,
    expected_types: []const AbiType,
) ![]AbiValue {
    var results: std.ArrayList(AbiValue) = .{};
    errdefer {
        for (results.items) |*item| {
            item.deinit(allocator);
        }
        results.deinit(allocator);
    }

    var offset: usize = 0;

    for (expected_types) |expected_type| {
        const value = try decodeValue(allocator, data, &offset, expected_type);
        try results.append(allocator, value);
    }

    return try results.toOwnedSlice(allocator);
}

// Helper encoding functions

fn encodeUint256(list: *std.ArrayList(u8), allocator: mem.Allocator, value: u256) !void {
    var bytes: [32]u8 = [_]u8{0} ** 32;
    mem.writeInt(u256, &bytes, value, .big);
    try list.appendSlice(allocator, &bytes);
}

fn encodeInt256(list: *std.ArrayList(u8), allocator: mem.Allocator, value: i256) !void {
    const unsigned: u256 = @bitCast(value);
    try encodeUint256(list, allocator, unsigned);
}

fn encodeAddress(list: *std.ArrayList(u8), allocator: mem.Allocator, address: [20]u8) !void {
    // Pad with 12 zeros on the left
    try list.appendNTimes(allocator, 0, 12);
    try list.appendSlice(allocator, &address);
}

fn encodeBool(list: *std.ArrayList(u8), allocator: mem.Allocator, value: bool) !void {
    try encodeUint256(list, allocator, if (value) 1 else 0);
}

fn encodeBytesFixed(list: *std.ArrayList(u8), allocator: mem.Allocator, bytes: []const u8) !void {
    if (bytes.len > 32) return error.BytesTooLong;
    try list.appendSlice(allocator, bytes);
    // Right-pad with zeros
    const padding = 32 - bytes.len;
    try list.appendNTimes(allocator, 0, padding);
}

// Helper decoding functions

fn decodeValue(
    allocator: mem.Allocator,
    data: []const u8,
    offset: *usize,
    expected_type: AbiType,
) !AbiValue {
    switch (expected_type) {
        .uint256 => {
            if (offset.* + 32 > data.len) return error.InsufficientData;
            const value = mem.readInt(u256, data[offset.*..][0..32], .big);
            offset.* += 32;
            return .{ .uint256 = value };
        },
        .int256 => {
            if (offset.* + 32 > data.len) return error.InsufficientData;
            const unsigned = mem.readInt(u256, data[offset.*..][0..32], .big);
            offset.* += 32;
            return .{ .int256 = @bitCast(unsigned) };
        },
        .address => {
            if (offset.* + 32 > data.len) return error.InsufficientData;
            var address: [20]u8 = undefined;
            @memcpy(&address, data[offset.* + 12 ..][0..20]);
            offset.* += 32;
            return .{ .address = address };
        },
        .bool_type => {
            if (offset.* + 32 > data.len) return error.InsufficientData;
            const value = mem.readInt(u256, data[offset.*..][0..32], .big);
            offset.* += 32;
            return .{ .bool_value = value != 0 };
        },
        .bytes_fixed => |size| {
            if (offset.* + 32 > data.len) return error.InsufficientData;
            const bytes = try allocator.dupe(u8, data[offset.* .. offset.* + size]);
            offset.* += 32;
            return .{ .bytes_fixed = bytes };
        },
        .bytes_dynamic, .string => {
            // Read offset pointer
            if (offset.* + 32 > data.len) return error.InsufficientData;
            const data_offset = mem.readInt(u256, data[offset.*..][0..32], .big);
            offset.* += 32;

            // Read length at offset
            if (data_offset + 32 > data.len) return error.InsufficientData;
            const length = mem.readInt(u256, data[data_offset..][0..32], .big);

            // Read actual data
            const start = data_offset + 32;
            if (start + length > data.len) return error.InsufficientData;
            const bytes = try allocator.dupe(u8, data[start .. start + length]);

            return if (expected_type == .string)
                .{ .string_value = bytes }
            else
                .{ .bytes_dynamic = bytes };
        },
        .array => return error.ArrayDecodingNotImplemented,
    }
}

/// Helper to create common ABI values
pub const helpers = struct {
    pub fn uint256(v: u256) AbiValue {
        return .{ .uint256 = v };
    }

    pub fn int256(v: i256) AbiValue {
        return .{ .int256 = v };
    }

    pub fn address(addr: [20]u8) AbiValue {
        return .{ .address = addr };
    }

    pub fn bool_value(b: bool) AbiValue {
        return .{ .bool_value = b };
    }

    pub fn string_value(allocator: mem.Allocator, s: []const u8) !AbiValue {
        const owned = try allocator.dupe(u8, s);
        return .{ .string_value = owned };
    }

    pub fn bytes(allocator: mem.Allocator, b: []const u8) !AbiValue {
        const owned = try allocator.dupe(u8, b);
        return .{ .bytes_dynamic = owned };
    }
};
