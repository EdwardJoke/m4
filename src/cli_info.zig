// ── Structured CLI metadata types (serializable via serde) ─────────
// Standalone module — no dependency on m4, safe to import from root.zig

pub const FlagInfo = struct {
    name: []const u8,
    short: ?[]const u8 = null,
    description: []const u8,
};

pub const SubcommandInfo = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    flags: []const FlagInfo = &.{},
};

pub const UsageMode = struct {
    mode: []const u8,
    syntax: []const u8,
};

pub const HelpInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    usage: []const UsageMode,
    subcommands: []const SubcommandInfo,
    flags: []const FlagInfo,
};

pub const VersionInfo = struct {
    name: []const u8,
    version: []const u8,
};
