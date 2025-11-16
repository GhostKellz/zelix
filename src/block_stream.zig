//! Hedera Block Stream client for streaming and querying blocks.
//! Implements HIP-1056 (Block Streams) and HIP-1081 (Block Nodes).

const std = @import("std");
const model = @import("model.zig");
const grpc_web = @import("grpc_web.zig");
const proto = @import("ser/proto.zig");
const block_parser = @import("block_parser.zig");

const log = std.log.scoped(.block_stream);

pub const BlockStreamClient = struct {
    allocator: std.mem.Allocator,
    grpc_client: grpc_web.GrpcWebClient,
    block_node_endpoint: []u8,

    pub const InitOptions = struct {
        allocator: std.mem.Allocator,
        block_node_endpoint: []const u8,
    };

    pub fn init(options: InitOptions) !BlockStreamClient {
        const endpoint_copy = try options.allocator.dupe(u8, options.block_node_endpoint);
        errdefer options.allocator.free(endpoint_copy);

        const grpc_client = try grpc_web.GrpcWebClient.init(options.allocator, options.block_node_endpoint);

        return .{
            .allocator = options.allocator,
            .grpc_client = grpc_client,
            .block_node_endpoint = endpoint_copy,
        };
    }

    pub fn deinit(self: *BlockStreamClient) void {
        self.grpc_client.deinit();
        if (self.block_node_endpoint.len > 0) self.allocator.free(self.block_node_endpoint);
        self.block_node_endpoint = "";
    }

    /// Query a single block by number.
    /// BlockAccessService.singleBlock RPC.
    pub fn getBlock(self: *BlockStreamClient, block_number: u64) !Block {
        const request = try encodeSingleBlockRequest(self.allocator, block_number, false, false);
        defer self.allocator.free(request);

        const response = try self.grpc_client.unary(
            "/com.hedera.hapi.block.BlockAccessService/singleBlock",
            request,
            self.allocator,
        );
        defer self.allocator.free(response);

        return try parseSingleBlockResponse(self.allocator, response);
    }

    /// Subscribe to a stream of blocks.
    /// BlockStreamService.subscribeBlockStream RPC.
    pub fn subscribeBlocks(
        self: *BlockStreamClient,
        start_block: u64,
        end_block: u64,
        handler: anytype,
    ) !void {
        const request = try encodeSubscribeStreamRequest(self.allocator, start_block, end_block, false);
        defer self.allocator.free(request);

        try self.grpc_client.serverStreaming(
            "/com.hedera.hapi.block.BlockStreamService/subscribeBlockStream",
            request,
            struct {
                allocator: std.mem.Allocator,
                callback: @TypeOf(handler),
                fn handle(ctx: *@This(), message: []const u8) !void {
                    const block_items = try parseSubscribeStreamResponse(ctx.allocator, message);
                    defer if (block_items) |items| ctx.allocator.free(items);

                    if (block_items) |items| {
                        try ctx.callback.handle(items);
                    }
                }
            }{ .allocator = self.allocator, .callback = handler },
        );
    }

    /// Query a range of blocks from start_block to end_block (inclusive).
    pub fn getBlockRange(
        self: *BlockStreamClient,
        start_block: u64,
        end_block: u64,
    ) !std.ArrayList(Block) {
        var blocks = std.ArrayList(Block).init(self.allocator);
        errdefer {
            for (blocks.items) |*block| {
                block.deinit(self.allocator);
            }
            blocks.deinit();
        }

        var current = start_block;
        while (current <= end_block) : (current += 1) {
            const block = try self.getBlock(current);
            try blocks.append(block);
        }

        return blocks;
    }

    /// Convert block number to approximate consensus timestamp.
    /// Hedera blocks are created approximately every 2 seconds.
    pub fn blockNumberToTimestamp(block_number: u64, network_start_timestamp: model.Timestamp) model.Timestamp {
        const seconds_per_block: u64 = 2; // Approximate block time
        const additional_seconds = block_number * seconds_per_block;

        return model.Timestamp{
            .seconds = network_start_timestamp.seconds + @as(i64, @intCast(additional_seconds)),
            .nanos = network_start_timestamp.nanos,
        };
    }

    /// Convert consensus timestamp to approximate block number.
    pub fn timestampToBlockNumber(timestamp: model.Timestamp, network_start_timestamp: model.Timestamp) u64 {
        const seconds_per_block: i64 = 2; // Approximate block time
        const elapsed_seconds = timestamp.seconds - network_start_timestamp.seconds;

        if (elapsed_seconds < 0) return 0;

        return @intCast(@divFloor(elapsed_seconds, seconds_per_block));
    }
};

/// A parsed block from the Block Node.
pub const Block = struct {
    block_number: u64,
    items: []BlockItem,

    pub fn deinit(self: *Block, allocator: std.mem.Allocator) void {
        for (self.items) |*item| {
            item.deinit(allocator);
        }
        if (self.items.len > 0) allocator.free(self.items);
        self.* = undefined;
    }
};

/// A single item within a block stream.
pub const BlockItem = struct {
    item_type: ItemType,
    data: []u8,

    pub const ItemType = enum {
        header,
        start_event,
        event_transaction,
        transaction_result,
        transaction_output,
        state_changes,
        state_proof,
        unknown,
    };

    pub fn deinit(self: *BlockItem, allocator: std.mem.Allocator) void {
        if (self.data.len > 0) allocator.free(self.data);
        self.* = undefined;
    }

    /// Parse event_transaction into ParsedTransaction
    pub fn parseEventTransaction(self: *const BlockItem, allocator: std.mem.Allocator) !block_parser.ParsedTransaction {
        if (self.item_type != .event_transaction) return error.WrongItemType;
        return try block_parser.parseEventTransaction(allocator, self.data);
    }

    /// Parse transaction_result into ParsedTransactionResult
    pub fn parseTransactionResult(self: *const BlockItem) !block_parser.ParsedTransactionResult {
        if (self.item_type != .transaction_result) return error.WrongItemType;
        return try block_parser.parseTransactionResult(self.data);
    }

    /// Parse transaction_output into ParsedTransactionOutput
    pub fn parseTransactionOutput(self: *const BlockItem) !block_parser.ParsedTransactionOutput {
        if (self.item_type != .transaction_output) return error.WrongItemType;
        return try block_parser.parseTransactionOutput(self.data);
    }

    /// Parse state_changes into list of StateChange entries
    pub fn parseStateChanges(self: *const BlockItem, allocator: std.mem.Allocator) !std.ArrayList(block_parser.StateChange) {
        if (self.item_type != .state_changes) return error.WrongItemType;
        return try block_parser.parseStateChanges(allocator, self.data);
    }
};

// Protobuf encoding functions

fn encodeSingleBlockRequest(
    allocator: std.mem.Allocator,
    block_number: u64,
    retrieve_latest: bool,
    allow_unverified: bool,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    if (!retrieve_latest) {
        try writer.writeFieldUint64(1, block_number);
    }
    if (allow_unverified) {
        try writer.writeFieldBool(2, true);
    }
    if (retrieve_latest) {
        try writer.writeFieldBool(3, true);
    }

    return writer.toOwnedSlice();
}

fn encodeSubscribeStreamRequest(
    allocator: std.mem.Allocator,
    start_block: u64,
    end_block: u64,
    allow_unverified: bool,
) ![]u8 {
    var writer = proto.Writer.init(allocator);
    defer writer.deinit();

    try writer.writeFieldUint64(1, start_block);
    if (end_block > 0) {
        try writer.writeFieldUint64(2, end_block);
    }
    if (allow_unverified) {
        try writer.writeFieldBool(3, true);
    }

    return writer.toOwnedSlice();
}

// Protobuf parsing functions

fn parseSingleBlockResponse(allocator: std.mem.Allocator, data: []const u8) !Block {
    // TODO: Implement full protobuf parsing
    // For now, return a stub
    _ = allocator;
    _ = data;
    return Block{
        .block_number = 0,
        .items = &[_]BlockItem{},
    };
}

fn parseSubscribeStreamResponse(allocator: std.mem.Allocator, data: []const u8) !?[]BlockItem {
    // TODO: Implement full protobuf parsing
    // For now, return null to indicate no items
    _ = allocator;
    _ = data;
    return null;
}
