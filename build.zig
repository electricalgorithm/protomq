const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const admin_server = b.option(bool, "admin_server", "Enable the HTTP Admin Server") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "admin_server", admin_server);
    const options_module = options.createModule();

    // Server executable
    const server_exe = b.addExecutable(.{
        .name = "protomq-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "build_options", .module = options_module },
            },
        }),
    });
    b.installArtifact(server_exe);

    // Client executable
    const client_exe = b.addExecutable(.{
        .name = "protomq-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mqtt_cli.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(client_exe);

    // Install systemd service if building for Linux
    if (target.result.os.tag == .linux) {
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(
            b.path("deploy/systemd/protomq.service"),
            .prefix,
            "etc/systemd/system/protomq.service",
        ).step);
    }

    // Run command for server
    const run_server_cmd = b.addRunArtifact(server_exe);
    run_server_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_server_cmd.addArgs(args);
    }
    const run_server_step = b.step("run-server", "Run the ProtoMQ server");
    run_server_step.dependOn(&run_server_cmd.step);

    // Run command for client
    const run_client_cmd = b.addRunArtifact(client_exe);
    run_client_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_client_cmd.addArgs(args);
    }
    const run_client_step = b.step("run-client", "Run the ProtoMQ client");
    run_client_step.dependOn(&run_client_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "build_options", .module = options_module },
            },
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
