//! Minimal protobuf writer for Zelix transactions.

const std = @import("std");

pub const Writer = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Writer {
        return .{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Writer) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn clear(self: *Writer) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn toOwnedSlice(self: *Writer) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    pub fn bytes(self: Writer) []const u8 {
        return self.buffer.items;
    }

    pub fn writeFieldVarint(self: *Writer, field_number: u32, value: u64) !void {
        try self.writeKey(field_number, wire_type_varint);
        try self.writeVarint(value);
    }

    pub fn writeFieldBool(self: *Writer, field_number: u32, value: bool) !void {
        try self.writeFieldVarint(field_number, if (value) 1 else 0);
    }

    pub fn writeFieldSint64(self: *Writer, field_number: u32, value: i64) !void {
        try self.writeFieldVarint(field_number, zigzagEncode64(value));
    }

    pub fn writeFieldInt64(self: *Writer, field_number: u32, value: i64) !void {
        const bits: u64 = @bitCast(value);
        try self.writeFieldVarint(field_number, bits);
    }

    pub fn writeFieldUint64(self: *Writer, field_number: u32, value: u64) !void {
        try self.writeFieldVarint(field_number, value);
    }

    pub fn writeFieldBytes(self: *Writer, field_number: u32, value: []const u8) !void {
        try self.writeKey(field_number, wire_type_length_delimited);
        try self.writeVarint(value.len);
        try self.buffer.appendSlice(self.allocator, value);
    }

    pub fn writeFieldString(self: *Writer, field_number: u32, value: []const u8) !void {
        try self.writeFieldBytes(field_number, value);
    }

    pub fn writeFieldMessage(self: *Writer, field_number: u32, encode_fn: fn (*Writer) anyerror!void) !void {
        var nested = Writer.init(self.allocator);
        defer nested.deinit();
        try encode_fn(&nested);
        try self.writeKey(field_number, wire_type_length_delimited);
        try self.writeVarint(nested.buffer.items.len);
        try self.buffer.appendSlice(self.allocator, nested.buffer.items);
    }

    fn writeKey(self: *Writer, field_number: u32, wire_type: u3) !void {
        const key: u64 = (@as(u64, field_number) << 3) | wire_type;
        try self.writeVarint(key);
    }

    fn writeVarint(self: *Writer, value_in: u64) !void {
        var value = value_in;
        while (value >= 0x80) : (value >>= 7) {
            const chunk = @as(u8, @intCast((value & 0x7F) | 0x80));
            try self.buffer.append(self.allocator, chunk);
        }
        const last = @as(u8, @intCast(value & 0x7F));
        try self.buffer.append(self.allocator, last);
    }
};

const wire_type_varint: u3 = 0;
const wire_type_length_delimited: u3 = 2;
const wire_type_fixed64: u3 = 1;
const wire_type_fixed32: u3 = 5;

fn zigzagEncode64(value: i64) u64 {
    const unsigned = @as(u64, @bitCast(value));
    const sign = @intFromBool(value < 0);
    return (unsigned << 1) ^ @as(u64, sign);
}

fn zigzagDecode64(value: u64) i64 {
    const result = (value >> 1) ^ (~(value & 1) +% 1);
    return @bitCast(result);
}

/// Protobuf reader for parsing wire format messages
pub const Reader = struct {
    data: []const u8,
    pos: usize = 0,

    pub fn init(data: []const u8) Reader {
        return .{ .data = data };
    }

    pub const Field = struct {
        field_number: u32,
        wire_type: u3,
        data: FieldData,

        pub const FieldData = union(enum) {
            varint: u64,
            bytes: []const u8,
            fixed64: u64,
            fixed32: u32,
        };
    };

    pub fn readField(self: *Reader) !?Field {
        if (self.pos >= self.data.len) return null;

        const key = try self.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: u3 = @intCast(key & 0x7);

        const field_data: Field.FieldData = switch (wire_type) {
            wire_type_varint => .{ .varint = try self.readVarint() },
            wire_type_length_delimited => blk: {
                const len = try self.readVarint();
                if (self.pos + len > self.data.len) return error.UnexpectedEof;
                const bytes = self.data[self.pos .. self.pos + len];
                self.pos += len;
                break :blk .{ .bytes = bytes };
            },
            wire_type_fixed64 => blk: {
                if (self.pos + 8 > self.data.len) return error.UnexpectedEof;
                const value = std.mem.readInt(u64, self.data[self.pos..][0..8], .little);
                self.pos += 8;
                break :blk .{ .fixed64 = value };
            },
            wire_type_fixed32 => blk: {
                if (self.pos + 4 > self.data.len) return error.UnexpectedEof;
                const value = std.mem.readInt(u32, self.data[self.pos..][0..4], .little);
                self.pos += 4;
                break :blk .{ .fixed32 = value };
            },
            else => return error.UnsupportedWireType,
        };

        return Field{
            .field_number = field_number,
            .wire_type = wire_type,
            .data = field_data,
        };
    }

    pub fn readVarint(self: *Reader) !u64 {
        var result: u64 = 0;
        var shift: u6 = 0;

        while (self.pos < self.data.len) {
            const byte = self.data[self.pos];
            self.pos += 1;

            result |= @as(u64, byte & 0x7F) << shift;

            if ((byte & 0x80) == 0) {
                return result;
            }

            shift += 7;
            if (shift >= 64) return error.VarintOverflow;
        }

        return error.UnexpectedEof;
    }

    pub fn readSint64(self: *Reader) !i64 {
        const value = try self.readVarint();
        return zigzagDecode64(value);
    }

    pub fn readBytes(self: *Reader) ![]const u8 {
        const len = try self.readVarint();
        if (self.pos + len > self.data.len) return error.UnexpectedEof;
        const bytes = self.data[self.pos .. self.pos + len];
        self.pos += len;
        return bytes;
    }

    pub fn skip(self: *Reader, wire_type: u3) !void {
        switch (wire_type) {
            wire_type_varint => _ = try self.readVarint(),
            wire_type_length_delimited => {
                const len = try self.readVarint();
                if (self.pos + len > self.data.len) return error.UnexpectedEof;
                self.pos += len;
            },
            wire_type_fixed64 => {
                if (self.pos + 8 > self.data.len) return error.UnexpectedEof;
                self.pos += 8;
            },
            wire_type_fixed32 => {
                if (self.pos + 4 > self.data.len) return error.UnexpectedEof;
                self.pos += 4;
            },
            else => return error.UnsupportedWireType,
        }
    }
};

