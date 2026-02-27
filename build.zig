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
            .link_libc = true,
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

    lib.installConfigHeader(generated_unarr_h);
    b.installArtifact(lib);

    const check = b.step("check", "Compile libunarr without installing");
    check.dependOn(&lib.step);
}
