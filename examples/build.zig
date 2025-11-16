const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "account_management",
        .root_module = b.createModule(.{
            .root_source_file = b.path("account_management.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zelix", .module = b.addModule("zelix", .{
                    .root_source_file = b.path("../src/zelix.zig"),
                    .target = target,
                }) },
            },
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the account management example");
    run_step.dependOn(&run_cmd.step);
}
