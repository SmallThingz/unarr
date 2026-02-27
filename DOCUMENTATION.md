# 📚 Documentation

## Overview

`unarr-zig` is a Zig wrapper around [`selmf/unarr`](https://github.com/selmf/unarr). It exposes:

- low-level C symbols via `unarr.c`
- a higher-level Zig API (`Archive`, `Entry`, `Format`, `Error`)
- Zig-managed build integration for fetching and compiling upstream `unarr`

Supported archive formats:

- `rar`
- `tar`
- `zip`
- `7z`

## Requirements

- Zig `0.15.2+`
- C toolchain supported by your Zig target

## Build and Test

```bash
zig build
zig build test
```

Useful build flags:

```bash
zig build -Dshared=true
zig build -Denable_7z=false
```

- `-Dshared=true`: builds `libunarr` as a shared library
- `-Denable_7z=false`: excludes 7z source set/defines

## Package Integration

Add dependency:

```bash
zig fetch --save <repo-url>
```

`build.zig`:

```zig
const dep = b.dependency("unarr", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("unarr", dep.module("unarr"));
```

Then in Zig source:

```zig
const unarr = @import("unarr");
```

## API Reference

### Types

### `unarr.Error`

Possible errors:

- `OpenStreamFailed`
- `OpenArchiveFailed`
- `ParseFailed`
- `DecompressFailed`
- `EntryTooLarge`
- `OutOfMemory`

### `unarr.Format`

Archive type selector:

- `.rar`
- `.tar`
- `.zip`
- `.@"7z"`

### `unarr.OpenOptions`

```zig
pub const OpenOptions = struct {
    zip_deflated_only: bool = false,
};
```

Only affects ZIP opening behavior.

### `unarr.Version`

```zig
pub const Version = struct {
    packed_version: u32,
    major: u8,
    minor: u8,
    patch: u8,
    string: []const u8,
};
```

### `unarr.runtimeVersion() Version`

Returns runtime version from linked `unarr`.

## `Archive`

### `Archive.openFile(format, path_z, options)`

Open archive by filesystem path (`[:0]const u8`, null-terminated).

### `Archive.openMemory(format, bytes, options)`

Open archive from memory buffer.

### `Archive.openStream(format, stream_ptr, options)`

Open from raw `*unarr.c.ar_stream`.

Important: this API does **not** take stream ownership.

### `archive.deinit()`

Releases archive resources. Closes stream only for `openFile` and `openMemory`.

### `archive.nextEntry() Error!?Entry`

Iterates entries.

- returns `Entry` when available
- returns `null` at EOF
- returns `error.ParseFailed` for parse errors

### `archive.parseEntryAt(offset)`

Repositions parser to a previously captured entry offset.

### `archive.parseEntryFor(name_z)`

Attempts to locate an entry by name. Returns `bool`.

### `archive.atEof()`

Returns parser EOF state.

### `archive.globalCommentSize()` / `archive.readGlobalComment(buffer)`

ZIP global comment helpers.

## `Entry`

### Metadata

- `entry.name() ?[]const u8`
- `entry.rawName() ?[]const u8`
- `entry.offset() i64`
- `entry.size() usize`
- `entry.filetime() i64`

### Data Reads

- `entry.read(out)` reads exactly `out.len` bytes from current entry stream position
- `entry.readAlloc(allocator, limit)` allocates full entry size with explicit upper bound

## Usage Examples

### 1. Inspect archive entries

```zig
const std = @import("std");
const unarr = @import("unarr");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const path_z = try allocator.dupeZ(u8, "/tmp/example.zip");
    defer allocator.free(path_z);

    var ar = try unarr.Archive.openFile(.zip, path_z, .{});
    defer ar.deinit();

    while (try ar.nextEntry()) |entry| {
        const name = entry.name() orelse "(unnamed)";
        std.debug.print("name={s} size={} offset={}\n", .{ name, entry.size(), entry.offset() });
    }
}
```

### 2. Read a specific entry by name

```zig
const std = @import("std");
const unarr = @import("unarr");

fn readNamed(path: []const u8, wanted: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    var ar = try unarr.Archive.openFile(.zip, path_z, .{});
    defer ar.deinit();

    const wanted_z = try allocator.dupeZ(u8, wanted);
    defer allocator.free(wanted_z);

    if (!ar.parseEntryFor(wanted_z)) return error.FileNotFound;

    // parseEntryFor positions the parser on the matching entry
    const entry: unarr.Entry = .{ .archive = &ar };
    const bytes = try entry.readAlloc(allocator, 64 * 1024 * 1024);
    defer allocator.free(bytes);

    std.debug.print("read {d} bytes from {s}\n", .{ bytes.len, wanted });
}
```

### 3. Random-access re-read by offset

```zig
const std = @import("std");
const unarr = @import("unarr");

fn rereadFirst(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    var ar = try unarr.Archive.openFile(.tar, path_z, .{});
    defer ar.deinit();

    const first = (try ar.nextEntry()) orelse return error.EndOfStream;
    const off = first.offset();

    const first_data = try first.readAlloc(allocator, 8 * 1024 * 1024);
    defer allocator.free(first_data);

    try ar.parseEntryAt(off);
    const same_again: unarr.Entry = .{ .archive = &ar };
    const second_data = try same_again.readAlloc(allocator, 8 * 1024 * 1024);
    defer allocator.free(second_data);

    try std.testing.expectEqualSlices(u8, first_data, second_data);
}
```

### 4. Open from in-memory bytes

```zig
const std = @import("std");
const unarr = @import("unarr");

fn parseEmbedded(bytes: []const u8) !void {
    var ar = try unarr.Archive.openMemory(.zip, bytes, .{});
    defer ar.deinit();

    while (try ar.nextEntry()) |entry| {
        _ = entry.name();
    }
}
```

### 5. Read ZIP global comment

```zig
const std = @import("std");
const unarr = @import("unarr");

fn showComment(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    var ar = try unarr.Archive.openFile(.zip, path_z, .{});
    defer ar.deinit();

    const n = ar.globalCommentSize();
    if (n == 0) return;

    const buf = try allocator.alloc(u8, n);
    defer allocator.free(buf);

    const copied = ar.readGlobalComment(buf);
    std.debug.print("comment: {s}\n", .{buf[0..copied]});
}
```

### 6. Use `openStream` with explicit ownership

```zig
const std = @import("std");
const unarr = @import("unarr");

fn openWithExistingStream(data: []const u8) !void {
    const stream = unarr.c.ar_open_memory(data.ptr, data.len) orelse return error.OpenStreamFailed;
    defer unarr.c.ar_close(stream); // you own stream lifetime

    var ar = try unarr.Archive.openStream(.zip, stream, .{});
    defer ar.deinit(); // closes archive only, not stream

    _ = try ar.nextEntry();
}
```

## Error Handling Guidance

Recommended pattern:

```zig
switch (err) {
    error.OpenArchiveFailed => { /* unsupported/invalid format */ },
    error.ParseFailed => { /* malformed entry or traversal failure */ },
    error.DecompressFailed => { /* damaged compressed data */ },
    error.EntryTooLarge => { /* increase limit or skip file */ },
    error.OutOfMemory => { /* allocator pressure */ },
    else => return err,
}
```

## Behavioral Notes and Gotchas

- `openFile` and `parseEntryFor` require null-terminated strings (`[:0]const u8`).
- `parseEntryFor`/`parseEntryAt` reposition parser state; treat iteration as stateful.
- `Entry` is a lightweight view over current archive parser state, not an owned snapshot.
- `readAlloc` is bounded by your provided `limit`; use it to prevent pathological allocations.
- String pointers from C are converted to Zig slices, but validity is tied to parser progression.
- `filetime()` is raw upstream value; interpretation depends on archive format metadata.

## Testing Strategy

The repository test suite validates:

- version mapping correctness
- reject-empty and reject-invalid inputs
- ZIP entry reading, comments, and random access by offset
- TAR multi-entry traversal and name lookup
- stream ownership contract for `openStream`

Run:

```bash
zig build test
```

## Stability and Compatibility

Current package version is pre-`1.0`. API and behavior may evolve while the wrapper matures.

For compatibility-sensitive integration, pin commit hashes in your consuming `build.zig.zon`.
