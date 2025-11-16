///! Async I/O utilities for non-blocking network operations.
///! Provides async wrappers around synchronous operations.

const std = @import("std");
const mem = std.mem;

/// Async task result
pub fn AsyncResult(comptime T: type) type {
    return union(enum) {
        pending,
        ready: T,
        err: anyerror,

        pub fn isReady(self: *const @This()) bool {
            return self.* == .ready or self.* == .err;
        }

        pub fn get(self: *const @This()) !T {
            return switch (self.*) {
                .ready => |val| val,
                .err => |e| e,
                .pending => error.TaskNotReady,
            };
        }
    };
}

/// Async task handle
pub fn AsyncTask(comptime T: type) type {
    return struct {
        const Self = @This();

        result: AsyncResult(T),
        thread: ?std.Thread,
        allocator: mem.Allocator,

        pub fn init(allocator: mem.Allocator) Self {
            return .{
                .result = .pending,
                .thread = null,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.thread) |thread| {
                thread.join();
            }
        }

        /// Spawn async task
        pub fn spawn(self: *Self, comptime func: anytype, args: anytype) !void {
            const Context = struct {
                task: *Self,
                args: @TypeOf(args),
                func: @TypeOf(func),

                fn run(ctx: *@This()) void {
                    const result = ctx.func(ctx.args) catch |err| {
                        ctx.task.result = .{ .err = err };
                        return;
                    };
                    ctx.task.result = .{ .ready = result };
                }
            };

            const ctx = try self.allocator.create(Context);
            ctx.* = .{
                .task = self,
                .args = args,
                .func = func,
            };

            self.thread = try std.Thread.spawn(.{}, Context.run, .{ctx});
        }

        /// Poll for completion
        pub fn poll(self: *Self) AsyncResult(T) {
            return self.result;
        }

        /// Wait for completion (blocking)
        pub fn wait(self: *Self) !T {
            if (self.thread) |thread| {
                thread.join();
                self.thread = null;
            }
            return self.result.get();
        }
    };
}

/// Async executor for running multiple tasks
pub const Executor = struct {
    allocator: mem.Allocator,
    thread_pool: std.Thread.Pool,

    pub fn init(allocator: mem.Allocator, num_threads: u32) !Executor {
        var pool: std.Thread.Pool = undefined;
        try pool.init(.{
            .allocator = allocator,
            .n_jobs = num_threads,
        });

        return .{
            .allocator = allocator,
            .thread_pool = pool,
        };
    }

    pub fn deinit(self: *Executor) void {
        self.thread_pool.deinit();
    }

    /// Submit task to executor
    pub fn submit(self: *Executor, comptime func: anytype, args: anytype) !void {
        try self.thread_pool.spawn(func, args);
    }
};

/// Async channel for communication between tasks
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        queue: std.ArrayList(T),
        mutex: std.Thread.Mutex,
        condition: std.Thread.Condition,
        allocator: mem.Allocator,
        closed: bool,

        pub fn init(allocator: mem.Allocator) Self {
            return .{
                .queue = .{},
                .mutex = .{},
                .condition = .{},
                .allocator = allocator,
                .closed = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit(self.allocator);
        }

        /// Send value to channel
        pub fn send(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed) return error.ChannelClosed;

            try self.queue.append(self.allocator, value);
            self.condition.signal();
        }

        /// Receive value from channel (blocking)
        pub fn recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.queue.items.len == 0 and !self.closed) {
                self.condition.wait(&self.mutex);
            }

            if (self.queue.items.len == 0 and self.closed) {
                return error.ChannelClosed;
            }

            return self.queue.orderedRemove(0);
        }

        /// Try to receive without blocking
        pub fn tryRecv(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.queue.items.len == 0) return null;
            return self.queue.orderedRemove(0);
        }

        /// Close the channel
        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.closed = true;
            self.condition.broadcast();
        }
    };
}
