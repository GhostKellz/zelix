//! Crypto utilities for Zelix

const std = @import("std");

const base64 = std.base64;
const fmt = std.fmt;
const mem = std.mem;

pub const Ed25519 = std.crypto.sign.Ed25519;

// Private Key
pub const PrivateKey = union(enum) {
    ed25519: Ed25519.KeyPair,

    pub fn generateEd25519() PrivateKey {
        var seed: [32]u8 = undefined;
        std.crypto.random.bytes(&seed);
        const secret_key = Ed25519.SecretKey.fromBytes(seed);
        const key_pair = Ed25519.KeyPair.fromSecretKey(secret_key) catch unreachable;
        return .{ .ed25519 = key_pair };
    }

    pub fn publicKey(self: PrivateKey) PublicKey {
        switch (self) {
            .ed25519 => |kp| return .{ .ed25519 = kp.public_key },
        }
    }

    pub fn sign(self: PrivateKey, msg: []const u8) ![64]u8 {
        switch (self) {
            .ed25519 => |kp| return (kp.sign(msg, null) catch unreachable).toBytes(),
        }
    }

    pub fn toBytes(self: PrivateKey) [32]u8 {
        switch (self) {
            .ed25519 => |kp| return kp.secret_key,
        }
    }

    pub fn toHex(self: PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        const bytes = self.toBytes();
        return fmt.allocPrint(allocator, "{s}", .{fmt.fmtSliceHexLower(&bytes)});
    }

    pub fn fromHex(hex: []const u8) !PrivateKey {
        const trimmed = mem.trim(u8, hex, " \t\r\n");
        if (trimmed.len != 64) return error.InvalidHexLength;
        var out: [32]u8 = undefined;
        _ = fmt.hexToBytes(&out, trimmed) catch return error.InvalidHexEncoding;
        return fromBytes(out);
    }

    pub fn toDer(self: PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        const secret = self.toBytes();
        var buf = try allocator.alloc(u8, ed25519_pkcs8_prefix.len + secret.len);
        errdefer allocator.free(buf);
        @memcpy(buf[0..ed25519_pkcs8_prefix.len], &ed25519_pkcs8_prefix);
        @memcpy(buf[ed25519_pkcs8_prefix.len..], secret[0..]);
        return buf;
    }

    pub fn toPem(self: PrivateKey, allocator: std.mem.Allocator) ![]u8 {
        const der = try self.toDer(allocator);
        defer allocator.free(der);

        const encoded_len = base64.standard.Encoder.calcSize(der.len);
        const encoded = try allocator.alloc(u8, encoded_len);
        defer allocator.free(encoded);
        _ = base64.standard.Encoder.encode(encoded, der);

        const pem = try fmt.allocPrint(
            allocator,
            "-----BEGIN PRIVATE KEY-----\n{s}\n-----END PRIVATE KEY-----\n",
            .{encoded},
        );
        return pem;
    }

    pub fn fromDer(bytes: []const u8) !PrivateKey {
        if (bytes.len != ed25519_pkcs8_prefix.len + 32) return error.InvalidDer;
        if (!mem.startsWith(u8, bytes, &ed25519_pkcs8_prefix)) return error.InvalidDer;
        var secret: [32]u8 = undefined;
        @memcpy(secret[0..], bytes[bytes.len - 32 .. bytes.len]);
        return fromBytes(secret);
    }

    pub fn fromPem(allocator: std.mem.Allocator, pem: []const u8) !PrivateKey {
        const der = try decodePemBlock(allocator, pem, pem_private_key_begin, pem_private_key_end);
        defer allocator.free(der);
        return fromDer(der);
    }

    pub fn fromBytes(bytes: [32]u8) PrivateKey {
        const key_pair = Ed25519.KeyPair.generateDeterministic(bytes) catch unreachable;
        return .{ .ed25519 = key_pair };
    }
};

// Public Key
pub const PublicKey = union(enum) {
    ed25519: Ed25519.PublicKey,

    pub fn verify(self: PublicKey, msg: []const u8, sig: [64]u8) !void {
        switch (self) {
            .ed25519 => |pk| {
                const signature = try Ed25519.Signature.fromBytes(sig);
                try Ed25519.verify(signature, msg, pk, null);
            },
        }
    }

    pub fn toBytes(self: PublicKey) [32]u8 {
        switch (self) {
            .ed25519 => |pk| return pk.toBytes(),
        }
    }

    pub fn toHex(self: PublicKey, allocator: std.mem.Allocator) ![]u8 {
        const bytes = self.toBytes();
        return fmt.allocPrint(allocator, "{s}", .{fmt.fmtSliceHexLower(&bytes)});
    }

    pub fn fromHex(hex: []const u8) !PublicKey {
        const trimmed = mem.trim(u8, hex, " \t\r\n");
        if (trimmed.len != 64) return error.InvalidHexLength;
        var out: [32]u8 = undefined;
        _ = fmt.hexToBytes(&out, trimmed) catch return error.InvalidHexEncoding;
        return fromBytes(out);
    }

    pub fn toDer(self: PublicKey, allocator: std.mem.Allocator) ![]u8 {
        const raw = self.toBytes();
        var buf = try allocator.alloc(u8, ed25519_spki_prefix.len + raw.len);
        errdefer allocator.free(buf);
        @memcpy(buf[0..ed25519_spki_prefix.len], &ed25519_spki_prefix);
        @memcpy(buf[ed25519_spki_prefix.len..], raw[0..]);
        return buf;
    }

    pub fn toPem(self: PublicKey, allocator: std.mem.Allocator) ![]u8 {
        const der = try self.toDer(allocator);
        defer allocator.free(der);
        const encoded_len = base64.standard.Encoder.calcSize(der.len);
        const encoded = try allocator.alloc(u8, encoded_len);
        defer allocator.free(encoded);
        _ = base64.standard.Encoder.encode(encoded, der);
        const pem = try fmt.allocPrint(
            allocator,
            "-----BEGIN PUBLIC KEY-----\n{s}\n-----END PUBLIC KEY-----\n",
            .{encoded},
        );
        return pem;
    }

    pub fn fromDer(bytes: []const u8) !PublicKey {
        if (bytes.len != ed25519_spki_prefix.len + 32) return error.InvalidDer;
        if (!mem.startsWith(u8, bytes, &ed25519_spki_prefix)) return error.InvalidDer;
        var raw: [32]u8 = undefined;
        @memcpy(raw[0..], bytes[bytes.len - 32 .. bytes.len]);
        return fromBytes(raw);
    }

    pub fn fromPem(allocator: std.mem.Allocator, pem: []const u8) !PublicKey {
        const der = try decodePemBlock(allocator, pem, pem_public_key_begin, pem_public_key_end);
        defer allocator.free(der);
        return fromDer(der);
    }

    pub fn fromBytes(bytes: [32]u8) !PublicKey {
        const pk = try Ed25519.PublicKey.fromBytes(bytes);
        return .{ .ed25519 = pk };
    }
};

// Placeholder for crypto namespace
pub const crypto = struct {};

test "ED25519 key generation and signing" {
    var private_key = PrivateKey.generateEd25519();
    const public_key = private_key.publicKey();

    const message = "hello world";
    const sig = try private_key.sign(message);
    try public_key.verify(message, sig);
}

test "PrivateKey hex round-trip" {
    const allocator = std.testing.allocator;
    var key = PrivateKey.generateEd25519();
    const hex = try key.toHex(allocator);
    defer allocator.free(hex);
    const parsed = try PrivateKey.fromHex(hex);
    try std.testing.expectEqualSlices(u8, &key.toBytes(), &parsed.toBytes());
}

test "PrivateKey PEM round-trip" {
    const allocator = std.testing.allocator;
    var key = PrivateKey.generateEd25519();
    const pem = try key.toPem(allocator);
    defer allocator.free(pem);
    const parsed = try PrivateKey.fromPem(allocator, pem);
    try std.testing.expectEqualSlices(u8, &key.toBytes(), &parsed.toBytes());
}

test "PublicKey PEM round-trip" {
    const allocator = std.testing.allocator;
    var key = PrivateKey.generateEd25519();
    const public_key = key.publicKey();
    const pem = try public_key.toPem(allocator);
    defer allocator.free(pem);
    const parsed = try PublicKey.fromPem(allocator, pem);
    try std.testing.expectEqualSlices(u8, &public_key.toBytes(), &parsed.toBytes());
}

const pem_private_key_begin = "-----BEGIN PRIVATE KEY-----";
const pem_private_key_end = "-----END PRIVATE KEY-----";
const pem_public_key_begin = "-----BEGIN PUBLIC KEY-----";
const pem_public_key_end = "-----END PUBLIC KEY-----";

const ed25519_pkcs8_prefix = [_]u8{
    0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06,
    0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
};

const ed25519_spki_prefix = [_]u8{
    0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65,
    0x70, 0x03, 0x21, 0x00,
};

fn decodePemBlock(allocator: std.mem.Allocator, pem: []const u8, begin: []const u8, end: []const u8) ![]u8 {
    const start = mem.indexOf(u8, pem, begin) orelse return error.InvalidPem;
    const tail = pem[start + begin.len ..];
    const end_index = mem.indexOf(u8, tail, end) orelse return error.InvalidPem;
    const raw_body = tail[0..end_index];

    var cleaned: std.ArrayList(u8) = .{};
    defer cleaned.deinit(allocator);
    for (raw_body) |c| switch (c) {
        ' ', '\n', '\r', '\t' => {},
        else => try cleaned.append(allocator, c),
    };

    const decoded_size = base64.standard.Decoder.calcSizeForSlice(cleaned.items) catch return error.InvalidPem;
    const decoded = try allocator.alloc(u8, decoded_size);
    errdefer allocator.free(decoded);
    base64.standard.Decoder.decode(decoded, cleaned.items) catch return error.InvalidPem;
    return decoded;
}

pub const Error = error{
    InvalidHexLength,
    InvalidHexEncoding,
    InvalidPem,
    InvalidDer,
};
