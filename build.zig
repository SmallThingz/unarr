const std = @import("std");

const unarr_version = std.SemanticVersion{
    .major = 1,
    .minor = 2,
    .patch = 0,
};

const unarr_version_string = "1.2.0";

const base_sources = [_][]const u8{
    "_7z/_7z.c",
    "common/conv.c",
    "common/crc32.c",
    "common/stream.c",
    "common/unarr.c",
    "lzmasdk/CpuArch.c",
    "lzmasdk/LzmaDec.c",
    "lzmasdk/Ppmd7.c",
    "lzmasdk/Ppmd7Dec.c",
    "lzmasdk/Ppmd7aDec.c",
    "lzmasdk/Ppmd8.c",
    "lzmasdk/Ppmd8Dec.c",
    "rar/filter-rar.c",
    "rar/huffman-rar.c",
    "rar/parse-rar.c",
    "rar/rar.c",
    "rar/rarvm.c",
    "rar/uncompress-rar.c",
    "tar/parse-tar.c",
    "tar/tar.c",
    "zip/inflate.c",
    "zip/parse-zip.c",
    "zip/uncompress-zip.c",
    "zip/zip.c",
};

const seven_zip_sources = [_][]const u8{
    "lzmasdk/7zArcIn.c",
    "lzmasdk/7zBuf.c",
    "lzmasdk/7zDec.c",
    "lzmasdk/7zStream.c",
    "lzmasdk/Bcj2.c",
    "lzmasdk/Bra.c",
    "lzmasdk/Bra86.c",
    "lzmasdk/Delta.c",
    "lzmasdk/Lzma2Dec.c",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const shared = b.option(bool, "shared", "Build libunarr as a shared library") orelse false;
    const enable_7z = b.option(bool, "enable_7z", "Enable 7z format support") orelse true;
    const static_libc = b.option(bool, "static_libc", "Link against static ziglibc instead of system libc") orelse true;

    const unarr_upstream = b.dependency("unarr_upstream", .{});

    const generated_unarr_h = b.addConfigHeader(.{
        .style = .{ .cmake = unarr_upstream.path("unarr.h.in") },
        .include_path = "unarr.h",
    }, .{
        .unarr_VERSION_MAJOR = @as(i64, @intCast(unarr_version.major)),
        .unarr_VERSION_MINOR = @as(i64, @intCast(unarr_version.minor)),
        .unarr_VERSION_PATCH = @as(i64, @intCast(unarr_version.patch)),
        .unarr_VERSION = unarr_version_string,
    });

    const lib = b.addLibrary(.{
        .name = "unarr",
        .linkage = if (shared) .dynamic else .static,
        .version = unarr_version,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = !static_libc,
            .sanitize_c = .off,
        }),
    });

    lib.root_module.addIncludePath(unarr_upstream.path(""));
    lib.root_module.addConfigHeader(generated_unarr_h);
    lib.root_module.addCMacro("_FILE_OFFSET_BITS", "64");
    lib.root_module.addCMacro("UNARR_EXPORT_SYMBOLS", "1");
    if (shared) lib.root_module.addCMacro("UNARR_IS_SHARED_LIBRARY", "1");

    lib.root_module.addCSourceFiles(.{
        .root = unarr_upstream.path(""),
        .files = &base_sources,
        .flags = &.{"-std=c99"},
    });

    if (enable_7z) {
        lib.root_module.addCMacro("HAVE_7Z", "1");
        lib.root_module.addCMacro("Z7_PPMD_SUPPORT", "1");
        lib.root_module.addCSourceFiles(.{
            .root = unarr_upstream.path(""),
            .files = &seven_zip_sources,
            .flags = &.{"-std=c99"},
        });
    }

    const static_libc_artifact = if (static_libc) blk: {
        const ziglibc_dep = b.lazyDependency("ziglibc", .{
            .target = target,
            .optimize = optimize,
            .trace = false,
        }) orelse return;

        configureStaticLibc(lib.root_module, ziglibc_dep);
        break :blk ziglibc_dep.artifact("cguana");
    } else null;

    lib.installConfigHeader(generated_unarr_h);
    b.installArtifact(lib);

    var lib_for_tests = lib;
    if (static_libc) {
        const test_lib = b.addLibrary(.{
            .name = "unarr_test",
            .linkage = .static,
            .version = unarr_version,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = false,
                .sanitize_c = .off,
            }),
        });
        test_lib.root_module.addIncludePath(unarr_upstream.path(""));
        test_lib.root_module.addConfigHeader(generated_unarr_h);
        test_lib.root_module.addCMacro("_FILE_OFFSET_BITS", "64");
        test_lib.root_module.addCMacro("UNARR_EXPORT_SYMBOLS", "1");
        test_lib.root_module.addCSourceFiles(.{
            .root = unarr_upstream.path(""),
            .files = &base_sources,
            .flags = &.{"-std=c99"},
        });

        if (enable_7z) {
            test_lib.root_module.addCMacro("HAVE_7Z", "1");
            test_lib.root_module.addCMacro("Z7_PPMD_SUPPORT", "1");
            test_lib.root_module.addCSourceFiles(.{
                .root = unarr_upstream.path(""),
                .files = &seven_zip_sources,
                .flags = &.{"-std=c99"},
            });
        }

        if (static_libc_artifact) |_| {
            const ziglibc_dep = b.lazyDependency("ziglibc", .{
                .target = target,
                .optimize = optimize,
                .trace = false,
            }) orelse return;
            configureStaticLibc(test_lib.root_module, ziglibc_dep);
        }

        lib_for_tests = test_lib;
    }

    const zig_api = b.addModule("unarr", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = !static_libc,
    });
    zig_api.addConfigHeader(generated_unarr_h);
    if (static_libc_artifact) |artifact| {
        const ziglibc_dep = b.lazyDependency("ziglibc", .{
            .target = target,
            .optimize = optimize,
            .trace = false,
        }) orelse return;
        configureStaticLibc(zig_api, ziglibc_dep);
        zig_api.linkLibrary(artifact);
    }
    zig_api.linkLibrary(lib_for_tests);

    const tests = b.addTest(.{
        .root_module = zig_api,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run Zig API tests");
    test_step.dependOn(&run_tests.step);

    const check = b.step("check", "Compile libunarr without installing");
    check.dependOn(&lib.step);
}

fn configureStaticLibc(module: *std.Build.Module, dep: *std.Build.Dependency) void {
    module.addIncludePath(dep.path("inc/libc"));
    module.addIncludePath(dep.path("inc/posix"));
    module.addIncludePath(dep.path("inc/gnu"));
    module.linkLibrary(dep.artifact("cguana"));
}
