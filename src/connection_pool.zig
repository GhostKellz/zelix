///! HTTP connection pooling for efficient network operations.
///! Reuses connections to reduce latency and overhead.

const std = @import("std");
const mem = std.mem;

/// HTTP connection pool
pub const ConnectionPool = struct {
    allocator: mem.Allocator,
    connections: std.ArrayList(Connection),
    max_connections: usize,
    mutex: std.Thread.Mutex,

    pub const Connection = struct {
        endpoint: []const u8,
        in_use: bool,
        last_used: i64,
        // In production, would store actual HTTP client/socket
    };

    pub fn init(allocator: mem.Allocator, max_connections: usize) ConnectionPool {
        return .{
            .allocator = allocator,
            .connections = .{},
            .max_connections = max_connections,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *ConnectionPool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.connections.items) |conn| {
            self.allocator.free(conn.endpoint);
        }
        self.connections.deinit(self.allocator);
    }

    /// Acquire a connection from the pool
    pub fn acquire(self: *ConnectionPool, endpoint: []const u8) !*Connection {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find existing available connection
        for (self.connections.items) |*conn| {
            if (!conn.in_use and mem.eql(u8, conn.endpoint, endpoint)) {
                conn.in_use = true;
                conn.last_used = std.time.timestamp();
                return conn;
            }
        }

        // Create new connection if under limit
        if (self.connections.items.len < self.max_connections) {
            const new_conn = Connection{
                .endpoint = try self.allocator.dupe(u8, endpoint),
                .in_use = true,
                .last_used = std.time.timestamp(),
            };
            try self.connections.append(self.allocator, new_conn);
            return &self.connections.items[self.connections.items.len - 1];
        }

        // Pool exhausted
        return error.ConnectionPoolExhausted;
    }

    /// Release a connection back to the pool
    pub fn release(self: *ConnectionPool, conn: *Connection) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        conn.in_use = false;
        conn.last_used = std.time.timestamp();
    }

    /// Clean up stale connections (not used in last N seconds)
    pub fn cleanStale(self: *ConnectionPool, max_idle_seconds: i64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();
        var i: usize = 0;

        while (i < self.connections.items.len) {
            const conn = self.connections.items[i];
            if (!conn.in_use and (now - conn.last_used) > max_idle_seconds) {
                self.allocator.free(conn.endpoint);
                _ = self.connections.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Get pool statistics
    pub fn getStats(self: *ConnectionPool) PoolStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var active: usize = 0;
        var idle: usize = 0;

        for (self.connections.items) |conn| {
            if (conn.in_use) {
                active += 1;
            } else {
                idle += 1;
            }
        }

        return .{
            .total = self.connections.items.len,
            .active = active,
            .idle = idle,
            .max = self.max_connections,
        };
    }

    pub const PoolStats = struct {
        total: usize,
        active: usize,
        idle: usize,
        max: usize,
    };
};
