const std = @import("std");
const Allocator = std.mem.Allocator;

const api = @import("api/root.zig");
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const LuaError = @import("api/root.zig").LuaError;
const binchunk = @import("binchunk/root.zig");
const LuaValue = @import("state/root.zig").LuaValue;
const LuaState = @import("state/root.zig").LuaState;
const vm = @import("vm/root.zig");
const Instruction = vm.Instruction;
const LuaVM = vm.LuaVM;
const OpCode = vm.OpCode;

const string = []const u8;
const int = i32;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit(); // This checks for leaks.
    const gpa = debug_allocator.allocator();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    _ = args.skip();
    if (args.next()) |filename| {
        var threaded: std.Io.Threaded = .init(gpa, .{});
        defer threaded.deinit();
        const io = threaded.io();

        const cwd = std.Io.Dir.cwd();
        const file = try cwd.openFile(io, filename, .{ .mode = .read_only });
        defer file.close(io);
        const stat = try file.stat(io);
        const file_size = stat.size;
        const data = try gpa.alloc(u8, file_size);
        defer gpa.free(data);

        var fr = file.reader(io, data);
        var reader = &fr.interface;
        try reader.readSliceAll(data);

        const proto = binchunk.undump(data);
        try luaMain(proto, gpa);
    }
}

pub fn luaMain(proto: *binchunk.Prototype, allocator: std.mem.Allocator) !void {
    const n_registers: i32 = @intCast(proto.max_stack_size);
    var lua_vm = try LuaVM.init(allocator);
    var ls = &lua_vm;
    defer ls.deinit();

    ls.setClosure(proto);
    try ls.setTop(n_registers);
    outer: while (true) {
        const pc = ls.pc();
        const inst = Instruction.of(ls.fetch());
        if (inst.Opcode() != @intFromEnum(OpCode.OP_RETURN)) {
            try inst.execute(ls);
            std.debug.print("[{d:0>2}] {s: <9}", .{ @as(u32, @intCast(pc + 1)), inst.opName() });
            try printStack(ls);
        } else {
            break :outer;
        }
    }
}

fn printStack(ls: *LuaVM) LuaError!void {
    const top = @as(usize, @intCast(ls.getTop()));
    for (1..top + 1) |x| {
        const i: i32 = @intCast(x);
        const t = ls.Type(i);
        switch (t) {
            .lua_t_boolean => {
                std.debug.print("[{}]", .{ls.toBoolean(i)});
            },
            .lua_t_number => {
                std.debug.print("[{d}]", .{ls.toNumber(i)});
            },
            .lua_t_string => {
                std.debug.print("[\"{s}\"]", .{(try ls.toString(i)).data()});
            },
            else => {
                std.debug.print("[{s}]", .{ls.typeName(t)});
            },
        }
    }
    std.debug.print("\n", .{});
}
