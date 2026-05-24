const std = @import("std");
const serde = @import("serde");

pub const Severity = enum {
    @"error",
    warning,
    note,
    hint,

    pub const serde = .{ .enum_repr = .string };
};

pub const SourceLocation = struct {
    file: []const u8,
    line: u32,
    column: u32,
};

pub const Diagnostic = struct {
    severity: Severity,
    code: []const u8,
    message: []const u8,
    location: ?SourceLocation = null,
    hint: ?[]const u8 = null,
};

pub const Format = enum {
    zon,
    json,
    yaml,

    pub fn fromString(s: []const u8) ?Format {
        const map = std.StaticStringMap(Format).initComptime(.{
            .{ "zon", .zon },
            .{ "json", .json },
            .{ "yaml", .yaml },
        });
        return map.get(s);
    }
};

pub const DiagnosticList = struct {
    diagnostics: std.ArrayListUnmanaged(Diagnostic) = .{ .items = &.{}, .capacity = 0 },
    error_count: u32 = 0,
    warning_count: u32 = 0,

    pub fn init() DiagnosticList {
        return .{};
    }

    pub fn deinit(self: *DiagnosticList, allocator: std.mem.Allocator) void {
        self.diagnostics.deinit(allocator);
        self.* = undefined;
    }

    pub fn add(self: *DiagnosticList, allocator: std.mem.Allocator, d: Diagnostic) !void {
        try self.diagnostics.append(allocator, d);
        switch (d.severity) {
            .@"error" => self.error_count += 1,
            .warning => self.warning_count += 1,
            else => {},
        }
    }

    pub fn hasErrors(self: *const DiagnosticList) bool {
        return self.error_count > 0;
    }

    pub fn items(self: *const DiagnosticList) []const Diagnostic {
        return self.diagnostics.items;
    }
};

pub fn formatDiagnostics(
    allocator: std.mem.Allocator,
    diagnostics: []const Diagnostic,
    format: Format,
) ![]const u8 {
    return switch (format) {
        .zon => try serde.zon.toSlice(allocator, diagnostics),
        .json => try serde.json.toSlice(allocator, diagnostics),
        .yaml => try serde.yaml.toSlice(allocator, diagnostics),
    };
}
