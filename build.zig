const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the root module
    const root_module = std.Build.Module.create(b, .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "quotez",
        .root_module = root_module,
    });

    exe.linkLibC();
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Create the test module for unit tests
    const test_module = std.Build.Module.create(b, .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit tests (embedded in source files)
    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // =========================================================================
    // Integration Tests - Use single src module to avoid file ownership issues
    // =========================================================================

    // Create a single source module that covers all of src/
    // This module uses relative imports internally (as the source does)
    const src_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Integration test module imports the src module
    const integration_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/protocol_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_module.addImport("src", src_module);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_module = integration_module,
    });
    integration_tests.linkLibC();

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // End-to-end test module
    const e2e_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/end_to_end_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    e2e_module.addImport("src", src_module);

    // End-to-end tests
    const e2e_tests = b.addTest(.{
        .root_module = e2e_module,
    });
    e2e_tests.linkLibC();

    const run_e2e_tests = b.addRunArtifact(e2e_tests);

    // Performance test module
    const perf_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/perf_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    perf_module.addImport("src", src_module);

    // Performance tests
    const perf_tests = b.addTest(.{
        .root_module = perf_module,
    });
    perf_tests.linkLibC();

    const run_perf_tests = b.addRunArtifact(perf_tests);

    // Test step (unit tests)
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration test step
    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&run_integration_tests.step);

    // End-to-end test step
    const e2e_step = b.step("test-e2e", "Run end-to-end tests");
    e2e_step.dependOn(&run_e2e_tests.step);

    // Performance test step
    const perf_step = b.step("test-perf", "Run performance tests");
    perf_step.dependOn(&run_perf_tests.step);

    // All tests step
    const all_tests_step = b.step("test-all", "Run all tests");
    all_tests_step.dependOn(&run_unit_tests.step);
    all_tests_step.dependOn(&run_integration_tests.step);
    all_tests_step.dependOn(&run_e2e_tests.step);
    all_tests_step.dependOn(&run_perf_tests.step);
}
