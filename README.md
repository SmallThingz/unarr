# 📦 unarr-zig

Zig-first bindings and high-level API for [`selmf/unarr`](https://github.com/selmf/unarr), with Zig-managed dependency fetching and C library build.

![Zig](https://img.shields.io/badge/Zig-0.15.2%2B-f7a41d)
![Formats](https://img.shields.io/badge/Formats-RAR%20%7C%20TAR%20%7C%20ZIP%20%7C%207z-2ea44f)
![Build](https://img.shields.io/badge/Build-Zig%20build%20system-0366d6)

## ⚡ Features

- 🧩 **Pure Zig build orchestration**: upstream `unarr` is downloaded and compiled via `zig build`.
- 🛠 **High-level wrapper API**: ergonomic `Archive`/`Entry` types over raw C symbols.
- 📦 **Multi-format archive support**: RAR, TAR, ZIP, and 7z.
- 🧪 **Integration-heavy tests**: deterministic ZIP/TAR fixtures, parsing, seek/reparse, and ownership checks.
- 🔒 **Safe defaults**: explicit error surface (`Error`), bounded allocation reads (`readAlloc(limit)`).

## 🚀 Quick Start

```bash
zig build
zig build test
```

Build options:

```bash
zig build -Dshared=true      # build shared libunarr
zig build -Denable_7z=false  # compile without 7z sources
```

List all options/steps:

```bash
zig build -h
zig build -l
```

## 🧭 API At A Glance

```zig
const std = @import("std");
const unarr = @import("unarr");

test "read first zip entry" {
    var ar = try unarr.Archive.openFile(.zip, "/tmp/example.zip", .{});
    defer ar.deinit();

    const entry = (try ar.nextEntry()) orelse return error.TestUnexpectedResult;
    const data = try entry.readAlloc(std.testing.allocator, 64 * 1024 * 1024);
    defer std.testing.allocator.free(data);

    std.debug.print("entry={s} size={}\n", .{ entry.name() orelse "(unnamed)", data.len });
}
```

Core surface:

- `unarr.Archive.openFile`, `openMemory`, `openStream`
- `unarr.Archive.nextEntry`, `parseEntryAt`, `parseEntryFor`, `atEof`
- `unarr.Entry.name`, `rawName`, `size`, `offset`, `read`, `readAlloc`
- `unarr.runtimeVersion()`

## 📦 Installation (As Dependency)

```bash
zig fetch --save <this-repo-url>
```

In your `build.zig`:

```zig
const dep = b.dependency("unarr", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("unarr", dep.module("unarr"));
```

## 🧪 Testing and Validation

```bash
zig build test
zig build check
zig build
```

Current test coverage includes:

- version consistency checks
- invalid/empty archive rejection paths
- ZIP entry reads, comments, and offset reparsing
- TAR multi-entry iteration and lookup behavior
- `openFile` and `openStream` ownership semantics

## 📚 Documentation

- [DOCUMENTATION.md](./DOCUMENTATION.md)
- [SECURITY.md](./SECURITY.md)
- [CONTRIBUTIONS.md](./CONTRIBUTIONS.md)

## 🧱 Build Model

This project pins upstream `selmf/unarr` in `build.zig.zon` and compiles the C sources directly from that fetched dependency.

Generated headers (`unarr.h`) are produced during build from upstream `unarr.h.in` using Zig's `addConfigHeader`.

## 📜 License

GNU Lesser General Public License v3. See [LICENCE](./LICENCE).
