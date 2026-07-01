// ── Structured CLI metadata types (serializable via serde) ─────────
// Standalone module — no dependency on m4, safe to import from root.zig

/// Metadata for a CLI flag, including name, optional short form, and description.
pub const FlagInfo = struct {
    name: []const u8,
    short: ?[]const u8 = null,
    description: []const u8,
};

/// Metadata for a CLI subcommand including usage and flags.
pub const SubcommandInfo = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    flags: []const FlagInfo = &.{},
};

/// A CLI usage mode (e.g., run-file, run-stdin, repl).
pub const UsageMode = struct {
    mode: []const u8,
    syntax: []const u8,
};

/// Complete CLI help metadata, serializable via serde.
pub const HelpInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    usage: []const UsageMode,
    subcommands: []const SubcommandInfo,
    flags: []const FlagInfo,
};

/// Version metadata for structured output.
pub const VersionInfo = struct {
    name: []const u8,
    version: []const u8,
};
