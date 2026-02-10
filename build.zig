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
            .imports = &.{},
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
            .imports = &.{},
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
            .imports = &.{},
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
            .imports = &.{},
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
            .imports = &.{},
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
            .imports = &.{},
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

    const pcrez_dep = b.dependency("pcrez", .{
        .target = target,
        .optimize = optimize,
    });
    const pcrez_mod = pcrez_dep.module("pcrez");

    const datetime_dep = b.dependency("datetime", .{
        .target = target,
        .optimize = optimize,
    });
    const datetime_mod = datetime_dep.module("datetime");

    // Chapter 8 executable
    const ch08_exe = b.addExecutable(.{
        .name = "ch08",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch08-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
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

    // Chapter 9 executable
    const ch09_exe = b.addExecutable(.{
        .name = "ch09",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch09-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
            },
        }),
    });

    b.installArtifact(ch09_exe);

    const run_ch09 = b.addRunArtifact(ch09_exe);
    const run_ch09_step = b.step("ch09", "Run chapter 9 application");
    run_ch09_step.dependOn(&run_ch09.step);

    // Make sure ch09 step also installs the executable
    run_ch09_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch09.addArgs(args);
    }

    // Chapter 10 executable
    const ch10_exe = b.addExecutable(.{
        .name = "ch10",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch10-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
            },
        }),
    });

    b.installArtifact(ch10_exe);

    const run_ch10 = b.addRunArtifact(ch10_exe);
    const run_ch10_step = b.step("ch10", "Run chapter 10 application");
    run_ch10_step.dependOn(&run_ch10.step);

    // Make sure ch10 step also installs the executable
    run_ch10_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch10.addArgs(args);
    }

    // Chapter 11 executable
    const ch11_exe = b.addExecutable(.{
        .name = "ch11",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch11-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
            },
        }),
    });

    b.installArtifact(ch11_exe);

    const run_ch11 = b.addRunArtifact(ch11_exe);
    const run_ch11_step = b.step("ch11", "Run chapter 11 application");
    run_ch11_step.dependOn(&run_ch11.step);

    // Make sure ch11 step also installs the executable
    run_ch11_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch11.addArgs(args);
    }

    // Chapter 12 executable
    const ch12_exe = b.addExecutable(.{
        .name = "ch12",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch12-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
            },
        }),
    });

    b.installArtifact(ch12_exe);

    const run_ch12 = b.addRunArtifact(ch12_exe);
    const run_ch12_step = b.step("ch12", "Run chapter 12 application");
    run_ch12_step.dependOn(&run_ch12.step);

    // Make sure ch12 step also installs the executable
    run_ch12_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch12.addArgs(args);
    }

    // Chapter 13 executable
    const ch13_exe = b.addExecutable(.{
        .name = "ch13",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch13-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
            },
        }),
    });

    b.installArtifact(ch13_exe);

    const run_ch13 = b.addRunArtifact(ch13_exe);
    const run_ch13_step = b.step("ch13", "Run chapter 13 application");
    run_ch13_step.dependOn(&run_ch13.step);

    // Make sure ch13 step also installs the executable
    run_ch13_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch13.addArgs(args);
    }

    // Chapter 14 executable
    const ch14_exe = b.addExecutable(.{
        .name = "ch14",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch14-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
            },
        }),
    });

    b.installArtifact(ch14_exe);

    const run_ch14 = b.addRunArtifact(ch14_exe);
    const run_ch14_step = b.step("ch14", "Run chapter 14 application");
    run_ch14_step.dependOn(&run_ch14.step);

    // Make sure ch14 step also installs the executable
    run_ch14_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch14.addArgs(args);
    }
    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const ch14_tests = b.addTest(.{
        .root_module = ch14_exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_ch14_tests = b.addRunArtifact(ch14_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const ch14_test_step = b.step("ch14-test", "Run tests");
    ch14_test_step.dependOn(&run_ch14_tests.step);

    // Chapter 16 executable
    const ch16_exe = b.addExecutable(.{
        .name = "ch16",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch16-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
            },
        }),
    });

    b.installArtifact(ch16_exe);

    const run_ch16 = b.addRunArtifact(ch16_exe);
    const run_ch16_step = b.step("ch16", "Run chapter 16 application");
    run_ch16_step.dependOn(&run_ch16.step);

    // Make sure ch16 step also installs the executable
    run_ch16_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch16.addArgs(args);
    }
    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const ch16_tests = b.addTest(.{
        .root_module = ch16_exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_ch16_tests = b.addRunArtifact(ch16_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const ch16_test_step = b.step("ch16-test", "Run tests");
    ch16_test_step.dependOn(&run_ch16_tests.step);

    // Chapter 17 executable
    const ch17_exe = b.addExecutable(.{
        .name = "ch17",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch17-main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
            },
        }),
    });

    b.installArtifact(ch17_exe);

    const run_ch17 = b.addRunArtifact(ch17_exe);
    const run_ch17_step = b.step("ch17", "Run chapter 17 application");
    run_ch17_step.dependOn(&run_ch17.step);

    // Make sure ch17 step also installs the executable
    run_ch17_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch17.addArgs(args);
    }
    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const ch17_tests = b.addTest(.{
        .root_module = ch17_exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_ch17_tests = b.addRunArtifact(ch17_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const ch17_test_step = b.step("ch17-test", "Run tests");
    ch17_test_step.dependOn(&run_ch17_tests.step);

    // Chapter 18 executable
    const ch18_exe = b.addExecutable(.{
        .name = "ch18",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch18-main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
                .{ .name = "datetime", .module = datetime_mod },
            },
        }),
    });

    b.installArtifact(ch18_exe);

    const run_ch18 = b.addRunArtifact(ch18_exe);
    const run_ch18_step = b.step("ch18", "Run chapter 18 application");
    run_ch18_step.dependOn(&run_ch18.step);

    // Make sure ch18 step also installs the executable
    run_ch18_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch18.addArgs(args);
    }
    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const ch18_tests = b.addTest(.{
        .root_module = ch18_exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_ch18_tests = b.addRunArtifact(ch18_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const ch18_test_step = b.step("ch18-test", "Run tests");
    ch18_test_step.dependOn(&run_ch18_tests.step);

    // Chapter 19 executable
    const ch19_exe = b.addExecutable(.{
        .name = "ch19",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ch19-main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "pcrez", .module = pcrez_mod },
                .{ .name = "datetime", .module = datetime_mod },
            },
        }),
    });

    b.installArtifact(ch19_exe);

    const run_ch19 = b.addRunArtifact(ch19_exe);
    const run_ch19_step = b.step("ch19", "Run chapter 19 application");
    run_ch19_step.dependOn(&run_ch19.step);

    // Make sure ch19 step also installs the executable
    run_ch19_step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_ch19.addArgs(args);
    }
    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const ch19_tests = b.addTest(.{
        .root_module = ch19_exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_ch19_tests = b.addRunArtifact(ch19_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const ch19_test_step = b.step("ch19-test", "Run tests");
    ch19_test_step.dependOn(&run_ch19_tests.step);
}
