///! Streaming compression/decompression utilities for Block Streams.
///! Supports gzip decompression for efficient network transport.

const std = @import("std");
const mem = std.mem;

/// Streaming gzip decompressor for Block Stream data
pub const GzipDecompressor = struct {
    allocator: mem.Allocator,
    window: []u8,

    const window_size = 32768; // 32KB sliding window

    pub fn init(allocator: mem.Allocator) !GzipDecompressor {
        const window = try allocator.alloc(u8, window_size);
        return .{
            .allocator = allocator,
            .window = window,
        };
    }

    pub fn deinit(self: *GzipDecompressor) void {
        self.allocator.free(self.window);
    }

    /// Decompress gzip-compressed data
    pub fn decompress(self: *GzipDecompressor, compressed: []const u8) ![]u8 {
        // Use std.compress.gzip
        var stream = std.io.fixedBufferStream(compressed);
        var gzip_stream = try std.compress.gzip.decompress(self.allocator, stream.reader());
        defer gzip_stream.deinit();

        return try gzip_stream.reader().allocRemaining(self.allocator, std.Io.Limit.unlimited);
    }

    /// Decompress streaming data (incremental)
    pub fn decompressStreaming(
        self: *GzipDecompressor,
        compressed: []const u8,
        output_buffer: []u8,
    ) !usize {
        var stream = std.io.fixedBufferStream(compressed);
        var gzip_stream = try std.compress.gzip.decompress(self.allocator, stream.reader());
        defer gzip_stream.deinit();

        return try gzip_stream.reader().read(output_buffer);
    }
};

/// Check if data is gzip-compressed (magic bytes: 0x1f 0x8b)
pub fn isGzipCompressed(data: []const u8) bool {
    if (data.len < 2) return false;
    return data[0] == 0x1f and data[1] == 0x8b;
}

/// Auto-detect and decompress if needed
pub fn autoDecompress(allocator: mem.Allocator, data: []const u8) ![]u8 {
    if (isGzipCompressed(data)) {
        var decompressor = try GzipDecompressor.init(allocator);
        defer decompressor.deinit();
        return try decompressor.decompress(data);
    } else {
        // Not compressed, return copy
        return try allocator.dupe(u8, data);
    }
}
