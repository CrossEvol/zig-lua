const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("zig_lua", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // Create modules for different components
    const number_mod = b.addModule("number", .{
        .root_source_file = b.path("src/number/root.zig"),
        .target = target,
        .imports = &.{},
    });
    const api_mod = b.addModule("api", .{
        .root_source_file = b.path("src/api/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "number", .module = number_mod },
        },
    });
    const binchunk_mod = b.addModule("binchunk", .{
        .root_source_file = b.path("src/binchunk/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "api", .module = api_mod },
            .{ .name = "number", .module = number_mod },
        },
    });
    const state_mod = b.addModule("state", .{
        .root_source_file = b.path("src/state/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "api", .module = api_mod },
            .{ .name = "number", .module = number_mod },
            .{ .name = "binchunk", .module = binchunk_mod },
        },
    });
    const vm_mod = b.addModule("vm", .{
        .root_source_file = b.path("src/vm/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "state", .module = state_mod },
            .{ .name = "api", .module = api_mod },
            .{ .name = "binchunk", .module = binchunk_mod },
        },
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zig_lua",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_lua", .module = mod },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.

    // Chapter 2 executable
    const ch02_exe = b.addExecutable(.{
        .name = "ch02",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch02-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "api", .module = api_mod },
                .{ .name = "binchunk", .module = binchunk_mod },
                .{ .name = "state", .module = state_mod },
            },
        }),
    });

    b.installArtifact(ch02_exe);

    const run_ch02 = b.addRunArtifact(ch02_exe);
    const run_ch02_step = b.step("ch02", "Run chapter 2 application");
    run_ch02_step.dependOn(&run_ch02.step);

    // Make sure ch02 step also installs the executable
    run_ch02_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch02.addArgs(args);
    }

    // Chapter 3 executable
    const ch03_exe = b.addExecutable(.{
        .name = "ch03",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch03-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "api", .module = api_mod },
                .{ .name = "binchunk", .module = binchunk_mod },
                .{ .name = "state", .module = state_mod },
                .{ .name = "vm", .module = vm_mod },
            },
        }),
    });

    b.installArtifact(ch03_exe);

    const run_ch03 = b.addRunArtifact(ch03_exe);
    const run_ch03_step = b.step("ch03", "Run chapter 3 application");
    run_ch03_step.dependOn(&run_ch03.step);

    // Make sure ch03 step also installs the executable
    run_ch03_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch03.addArgs(args);
    }

    // Chapter 4 executable
    const ch04_exe = b.addExecutable(.{
        .name = "ch04",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch04-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "binchunk", .module = binchunk_mod },
                .{ .name = "state", .module = state_mod },
                .{ .name = "vm", .module = vm_mod },
                .{ .name = "api", .module = api_mod },
            },
        }),
    });

    b.installArtifact(ch04_exe);

    const run_ch04 = b.addRunArtifact(ch04_exe);
    const run_ch04_step = b.step("ch04", "Run chapter 4 application");
    run_ch04_step.dependOn(&run_ch04.step);

    // Make sure ch04 step also installs the executable
    run_ch04_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch04.addArgs(args);
    }

    // Chapter 5 executable
    const ch05_exe = b.addExecutable(.{
        .name = "ch05",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch05-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "binchunk", .module = binchunk_mod },
                .{ .name = "state", .module = state_mod },
                .{ .name = "vm", .module = vm_mod },
                .{ .name = "api", .module = api_mod },
            },
        }),
    });

    b.installArtifact(ch05_exe);

    const run_ch05 = b.addRunArtifact(ch05_exe);
    const run_ch05_step = b.step("ch05", "Run chapter 5 application");
    run_ch05_step.dependOn(&run_ch05.step);

    // Make sure ch05 step also installs the executable
    run_ch05_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch05.addArgs(args);
    }

    // Chapter 6 executable
    const ch06_exe = b.addExecutable(.{
        .name = "ch06",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch06-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "binchunk", .module = binchunk_mod },
                .{ .name = "state", .module = state_mod },
                .{ .name = "vm", .module = vm_mod },
                .{ .name = "api", .module = api_mod },
            },
        }),
    });

    b.installArtifact(ch06_exe);

    const run_ch06 = b.addRunArtifact(ch06_exe);
    const run_ch06_step = b.step("ch06", "Run chapter 6 application");
    run_ch06_step.dependOn(&run_ch06.step);

    // Make sure ch06 step also installs the executable
    run_ch06_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch06.addArgs(args);
    }

    // Chapter 7 executable
    const ch07_exe = b.addExecutable(.{
        .name = "ch07",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch07-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "binchunk", .module = binchunk_mod },
                .{ .name = "state", .module = state_mod },
                .{ .name = "vm", .module = vm_mod },
                .{ .name = "api", .module = api_mod },
            },
        }),
    });

    b.installArtifact(ch07_exe);

    const run_ch07 = b.addRunArtifact(ch07_exe);
    const run_ch07_step = b.step("ch07", "Run chapter 7 application");
    run_ch07_step.dependOn(&run_ch07.step);

    // Make sure ch07 step also installs the executable
    run_ch07_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch07.addArgs(args);
    }

    // Chapter 8 executable
    const ch08_exe = b.addExecutable(.{
        .name = "ch08",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch08-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "binchunk", .module = binchunk_mod },
                .{ .name = "state", .module = state_mod },
                .{ .name = "vm", .module = vm_mod },
                .{ .name = "api", .module = api_mod },
            },
        }),
    });

    b.installArtifact(ch08_exe);

    const run_ch08 = b.addRunArtifact(ch08_exe);
    const run_ch08_step = b.step("ch08", "Run chapter 8 application");
    run_ch08_step.dependOn(&run_ch08.step);

    // Make sure ch08 step also installs the executable
    run_ch08_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch08.addArgs(args);
    }
}
