const std = @import("std");

pub const c = @cImport({
    @cInclude("unarr.h");
});

pub const Error = error{
    OpenStreamFailed,
    OpenArchiveFailed,
    ParseFailed,
    DecompressFailed,
    EntryTooLarge,
    OutOfMemory,
};

pub const Format = enum {
    rar,
    tar,
    zip,
    @"7z",
};

pub const Version = struct {
    packed_version: u32,
    major: u8,
    minor: u8,
    patch: u8,
    string: []const u8,
};

pub fn runtimeVersion() Version {
    const packed_version = c.ar_get_version();
    return .{
        .packed_version = packed_version,
        .major = @as(u8, @intCast((packed_version >> 16) & 0xff)),
        .minor = @as(u8, @intCast((packed_version >> 8) & 0xff)),
        .patch = @as(u8, @intCast(packed_version & 0xff)),
        .string = zStr(c.ar_get_version_str()),
    };
}

pub const Archive = struct {
    stream: *c.ar_stream,
    archive: *c.ar_archive,
    owns_stream: bool,

    pub fn openFile(format: Format, path: [:0]const u8, options: OpenOptions) Error!Archive {
        const stream = c.ar_open_file(path.ptr) orelse return error.OpenStreamFailed;
        errdefer c.ar_close(stream);
        const archive = openArchive(format, stream, options) orelse return error.OpenArchiveFailed;
        return .{
            .stream = stream,
            .archive = archive,
            .owns_stream = true,
        };
    }

    pub fn openMemory(format: Format, data: []const u8, options: OpenOptions) Error!Archive {
        if (data.len == 0) return error.OpenStreamFailed;
        const stream = c.ar_open_memory(data.ptr, data.len) orelse return error.OpenStreamFailed;
        errdefer c.ar_close(stream);
        const archive = openArchive(format, stream, options) orelse return error.OpenArchiveFailed;
        return .{
            .stream = stream,
            .archive = archive,
            .owns_stream = true,
        };
    }

    pub fn openStream(format: Format, stream: *c.ar_stream, options: OpenOptions) Error!Archive {
        const archive = openArchive(format, stream, options) orelse return error.OpenArchiveFailed;
        return .{
            .stream = stream,
            .archive = archive,
            .owns_stream = false,
        };
    }

    pub fn deinit(self: *Archive) void {
        c.ar_close_archive(self.archive);
        if (self.owns_stream) c.ar_close(self.stream);
    }

    pub fn nextEntry(self: *Archive) Error!?Entry {
        if (c.ar_parse_entry(self.archive)) {
            return Entry{ .archive = self };
        }
        if (c.ar_at_eof(self.archive)) return null;
        return error.ParseFailed;
    }

    pub fn parseEntryAt(self: *Archive, offset: i64) Error!void {
        if (!c.ar_parse_entry_at(self.archive, @as(c.off64_t, @intCast(offset)))) {
            return error.ParseFailed;
        }
    }

    pub fn parseEntryFor(self: *Archive, name: [:0]const u8) bool {
        return c.ar_parse_entry_for(self.archive, name.ptr);
    }

    pub fn atEof(self: *Archive) bool {
        return c.ar_at_eof(self.archive);
    }

    pub fn globalCommentSize(self: *Archive) usize {
        return c.ar_get_global_comment(self.archive, null, 0);
    }

    pub fn readGlobalComment(self: *Archive, buffer: []u8) usize {
        if (buffer.len == 0) return 0;
        return c.ar_get_global_comment(self.archive, buffer.ptr, buffer.len);
    }
};

pub const OpenOptions = struct {
    zip_deflated_only: bool = false,
};

pub const Entry = struct {
    archive: *Archive,

    pub fn name(self: Entry) ?[]const u8 {
        const ptr = c.ar_entry_get_name(self.archive.archive) orelse return null;
        return zStr(ptr);
    }

    pub fn rawName(self: Entry) ?[]const u8 {
        const ptr = c.ar_entry_get_raw_name(self.archive.archive) orelse return null;
        return zStr(ptr);
    }

    pub fn offset(self: Entry) i64 {
        return @as(i64, @intCast(c.ar_entry_get_offset(self.archive.archive)));
    }

    pub fn size(self: Entry) usize {
        return c.ar_entry_get_size(self.archive.archive);
    }

    pub fn filetime(self: Entry) i64 {
        return @as(i64, @intCast(c.ar_entry_get_filetime(self.archive.archive)));
    }

    pub fn read(self: Entry, out: []u8) Error!void {
        if (out.len == 0) return;
        if (!c.ar_entry_uncompress(self.archive.archive, out.ptr, out.len)) {
            return error.DecompressFailed;
        }
    }

    pub fn readAlloc(self: Entry, allocator: std.mem.Allocator, limit: usize) Error![]u8 {
        const n = self.size();
        if (n > limit) return error.EntryTooLarge;
        const out = allocator.alloc(u8, n) catch return error.OutOfMemory;
        errdefer allocator.free(out);
        try self.read(out);
        return out;
    }
};

fn openArchive(format: Format, stream: *c.ar_stream, options: OpenOptions) ?*c.ar_archive {
    return switch (format) {
        .rar => c.ar_open_rar_archive(stream),
        .tar => c.ar_open_tar_archive(stream),
        .zip => c.ar_open_zip_archive(stream, options.zip_deflated_only),
        .@"7z" => c.ar_open_7z_archive(stream),
    };
}

fn zStr(ptr: [*c]const u8) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

test "version parse is stable" {
    const v = runtimeVersion();
    try std.testing.expect(v.string.len > 0);
}
