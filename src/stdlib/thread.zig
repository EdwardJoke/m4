const std = @import("std");
const VM = @import("../vm.zig");
const value = @import("../value.zig");
const object = @import("../object.zig");
const m4_std = @import("std.zig");

// Channel capacity for message passing between threads.
const CHANNEL_CAP = 64;

const ThreadHandleObj = struct {
    thread: std.Thread,
    result: value.Value,
};

const ChannelObj = struct {
    buf: [CHANNEL_CAP]value.Value,
    head: usize,
    tail: usize,
    closed: u8,
};

const SpawnInfo = struct {
    fun_ptr: *anyopaque,
    handle: *ThreadHandleObj,
    arg_count: usize,
    args: [8]value.Value, // fixed-size arg buffer (supports up to 8 args)
};

/// Register all thread module native functions (spawn, join, channel, send, recv) with the VM.
pub fn register(vm: *VM) !void {
    try vm.registerNative("thread.spawn", @ptrCast(@constCast(&spawnFn)));
    try vm.registerNative("thread.join", @ptrCast(@constCast(&joinFn)));
    try vm.registerNative("thread.channel", @ptrCast(@constCast(&channelFn)));
    try vm.registerNative("thread.send", @ptrCast(@constCast(&sendFn)));
    try vm.registerNative("thread.recv", @ptrCast(@constCast(&recvFn)));
}

/// Spawn a function in a new thread with up to 8 arguments. Returns a handle (vec) for thread.join.
fn spawnFn(vm: *VM, args: []const value.Value) value.Value {
    if (args.len < 1) return .nil;
    if (args[0] != .fun_obj) return .nil;

    const handle = vm.allocator.create(ThreadHandleObj) catch return .nil;
    errdefer vm.allocator.destroy(handle);

    const extra_args = args[1..];
    const arg_count = @min(extra_args.len, 8);

    const info = std.heap.page_allocator.create(SpawnInfo) catch {
        vm.allocator.destroy(handle);
        return .nil;
    };

    info.fun_ptr = args[0].fun_obj;
    info.handle = handle;
    info.arg_count = arg_count;
    info.args = [_]value.Value{.nil} ** 8;
    for (0..arg_count) |i| {
        info.args[i] = extra_args[i];
    }

    const thread = std.Thread.spawn(.{}, threadEntry, .{info}) catch {
        std.heap.page_allocator.destroy(info);
        vm.allocator.destroy(handle);
        return .nil;
    };

    handle.thread = thread;
    handle.result = .nil;

    return .{ .thread_handle = @ptrCast(handle) };
}

/// Entry point for a spawned thread. Runs the function with its arguments and stores the result.
fn threadEntry(info: *SpawnInfo) void {
    const fun: *object.FunObj = @ptrCast(@alignCast(info.fun_ptr));

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var child_vm = VM.init(allocator);
    defer child_vm.deinit();

    m4_std.register(&child_vm) catch {};
    register(&child_vm) catch {};

    // Copy arguments into registers 0..arg_count
    for (0..info.arg_count) |i| {
        child_vm.registers[i] = info.args[i];
    }

    child_vm.chunk = &fun.chunk;
    child_vm.pc = 0;
    child_vm.frame_count = 1;
    child_vm.frames[0] = .{
        .chunk = &fun.chunk,
        .code = fun.chunk.code.items,
        .constants = fun.chunk.constants.items,
        .pc = 0,
        .base_reg = 0,
        .ret_pc = 0,
        .ret_dst = 0,
    };

    child_vm.run() catch {};

    info.handle.result = child_vm.registers[0];

    std.heap.page_allocator.destroy(info);
}

/// Join a spawned thread and return its result. Blocks until the thread completes.
fn joinFn(_: *VM, args: []const value.Value) value.Value {
    if (args.len < 1) return .nil;
    if (args[0] != .thread_handle) return .nil;

    const handle: *ThreadHandleObj = @ptrCast(@alignCast(args[0].thread_handle));
    handle.thread.join();
    return handle.result;
}

/// Create a new channel for inter-thread message passing (capacity: 64).
fn channelFn(vm: *VM, _: []const value.Value) value.Value {
    const ch = vm.allocator.create(ChannelObj) catch return .nil;
    ch.* = .{
        .buf = [_]value.Value{.{ .nil = {} }} ** CHANNEL_CAP,
        .head = 0,
        .tail = 0,
        .closed = 0,
    };
    return .{ .channel = @ptrCast(ch) };
}

/// Send a value into a channel. Blocks if full. Returns true on success, false if closed.
fn sendFn(_: *VM, args: []const value.Value) value.Value {
    if (args.len < 2) return .{ .bool = false };
    if (args[0] != .channel) return .{ .bool = false };

    const ch: *ChannelObj = @ptrCast(@alignCast(args[0].channel));
    const val = args[1];

    while (true) {
        if (@atomicLoad(u8, &ch.closed, .acquire) != 0) return .{ .bool = false };

        const head = @atomicLoad(usize, &ch.head, .acquire);
        const tail = @atomicLoad(usize, &ch.tail, .acquire);
        const next = (tail + 1) % CHANNEL_CAP;
        if (next == head) {
            std.Thread.yield() catch {};
            std.atomic.spinLoopHint();
            continue;
        }

        ch.buf[tail] = val;
        @atomicStore(usize, &ch.tail, next, .release);
        return .{ .bool = true };
    }
}

/// Receive a value from a channel. Blocks if empty. Returns nil if channel is closed and empty.
fn recvFn(_: *VM, args: []const value.Value) value.Value {
    if (args.len < 1) return .nil;
    if (args[0] != .channel) return .nil;

    const ch: *ChannelObj = @ptrCast(@alignCast(args[0].channel));

    while (true) {
        const head = @atomicLoad(usize, &ch.head, .acquire);
        if (@atomicLoad(usize, &ch.tail, .acquire) == head) {
            if (@atomicLoad(u8, &ch.closed, .acquire) != 0) return .nil;
            std.Thread.yield() catch {};
            std.atomic.spinLoopHint();
            continue;
        }

        const val = ch.buf[head];
        @atomicStore(usize, &ch.head, (head + 1) % CHANNEL_CAP, .release);
        return val;
    }
}
