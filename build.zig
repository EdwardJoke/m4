const std = @import("std");
const zon = @import("build.zig.zon");

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
    const serde_dep = b.dependency("serde", .{
        .target = target,
        .optimize = optimize,
    });
    const serde_mod = serde_dep.module("serde");

    const mod = b.addModule("m4", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "serde", .module = serde_mod },
        },
    });

    // QBE compiler backend — compiled as a static C library
    // Uses the Zig build system Module API to compile QBE C sources
    // Compile ALL arch targets so qbe_wrap.c can select at runtime
    const qbe_common_srcs: []const []const u8 = &.{
        "util.c", "parse.c", "abi.c", "cfg.c", "mem.c", "ssa.c",
        "alias.c", "load.c", "copy.c", "fold.c", "gvn.c", "gcm.c",
        "simpl.c", "ifopt.c", "live.c", "spill.c", "rega.c", "emit.c",
    };
    const qbe_all_arch_srcs: []const []const u8 = &.{
        "amd64/targ.c", "amd64/sysv.c", "amd64/isel.c", "amd64/emit.c", "amd64/winabi.c",
        "arm64/targ.c",  "arm64/abi.c",  "arm64/isel.c",  "arm64/emit.c",
        "rv64/targ.c",   "rv64/abi.c",   "rv64/isel.c",   "rv64/emit.c",
    };

    const qbe_mod = b.createModule(.{
        .root_source_file = null,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    qbe_mod.addIncludePath(b.path("qbe"));
    // Add all arch include paths
    qbe_mod.addIncludePath(b.path("qbe/amd64"));
    qbe_mod.addIncludePath(b.path("qbe/arm64"));
    qbe_mod.addIncludePath(b.path("qbe/rv64"));
    for (qbe_common_srcs) |src| {
        qbe_mod.addCSourceFile(.{ .file = b.path(b.fmt("qbe/{s}", .{src})), .flags = &.{"-std=c99"} });
    }
    for (qbe_all_arch_srcs) |src| {
        qbe_mod.addCSourceFile(.{ .file = b.path(b.fmt("qbe/{s}", .{src})), .flags = &.{"-std=c99"} });
    }

    const qbe_lib = b.addLibrary(.{
        .name = "qbe",
        .root_module = qbe_mod,
    });

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "m4", .module = mod },
            .{ .name = "serde", .module = serde_mod },
        },
    });
    // Link the QBE backend for native code compilation
    exe_mod.linkLibrary(qbe_lib);

    // QBE compilation wrapper — exposes qbe_compile_ssa() for end-to-end build
    qbe_mod.addCSourceFile(.{ .file = b.path("src/runtime/qbe_wrap.c"), .flags = &.{"-std=c99"} });

    // m4 runtime stubs for QBE backend — C source compiled and linked
    const rt_mod = b.createModule(.{
        .root_source_file = null,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    rt_mod.addIncludePath(b.path("src/runtime"));
    rt_mod.addCSourceFile(.{ .file = b.path("src/runtime/m4rt.c"), .flags = &.{"-std=c99"} });
    const rt_lib = b.addLibrary(.{ .name = "m4rt", .root_module = rt_mod });
    exe_mod.linkLibrary(rt_lib);

    const exe = b.addExecutable(.{
        .name = "m4",
        .root_module = exe_mod,
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // Pass version from build.zig.zon to the executable
    const version_opts = b.addOptions();
    version_opts.addOption([]const u8, "version", zon.version);
    exe.root_module.addImport("build_options", version_opts.createModule());

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
}
