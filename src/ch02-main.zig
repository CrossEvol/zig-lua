const std = @import("std");
const Allocator = std.mem.Allocator;

const binchunk = @import("binchunk/root.zig").binchunk;
const LuaString = @import("state/lua_string.zig").LuaString;
const LuaValue = @import("state/root.zig").state.LuaValue;

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
        try list(proto, gpa);
    }
}

fn list(f: *binchunk.Prototype, allocator: Allocator) !void {
    printHeader(f);
    try printCode(f, allocator);
    try printDetail(f, allocator);
    for (f.protos) |p| {
        try list(p, allocator);
    }
}

fn printHeader(f: *binchunk.Prototype) void {
    var funcType: string = "main";
    if (f.line_defined > 0) {
        funcType = "function";
    }

    var varargFlag: string = "";
    if (f.is_vararg > 0) {
        varargFlag = "+";
    }

    std.debug.print(
        "\n {s} <{s}:{d},{d}> ({d} instructions)\n",
        .{ funcType, f.source, f.line_defined, f.last_line_defined, f.code.len },
    );
    std.debug.print(
        "{d}{s} params, {d} slots, {d} upvalues, ",
        .{ f.num_params, varargFlag, f.max_stack_size, f.upvalue_names.len },
    );
    std.debug.print(
        "{d} locals, {d} constants, {d} functions\n",
        .{ f.loc_vars.len, f.constants.len, f.protos.len },
    );
}

fn printCode(f: *binchunk.Prototype, allocator: Allocator) !void {
    for (f.code, 0..) |c, pc| {
        var line: []const u8 = "-";
        var allocated_line: ?[]u8 = null;
        defer if (allocated_line) |al| allocator.free(al);

        if (f.line_info.len > 0) {
            const fmt: []const u8 = "{d}";
            allocated_line = try std.fmt.allocPrint(allocator, fmt, .{f.line_info[pc]});
            line = allocated_line.?;
        }
        std.debug.print("\t{d}\t[{s}]\t0x{X:0>8}\n", .{ pc + 1, line, c });
    }
}

fn printDetail(f: *binchunk.Prototype, allocator: Allocator) !void {
    std.debug.print("constants ({d}):\n", .{f.constants.len});
    for (f.constants, 0..) |k, i| {
        const const_str = try constantToString(k, allocator);
        defer if (!std.mem.eql(u8, const_str, "nil") and !std.mem.eql(u8, const_str, "?")) {
            allocator.free(const_str);
        };
        std.debug.print(
            "\t{d}\t{s}\n",
            .{ i + 1, const_str },
        );
    }

    std.debug.print("locals ({d}):\n", .{f.loc_vars.len});
    for (f.loc_vars, 0..) |loc_var, i| {
        std.debug.print(
            "\t{d}\t{s}\t{d}\t{d}\n",
            .{ i, loc_var.var_name, loc_var.start_pc + 1, loc_var.end_pc + 1 },
        );
    }

    std.debug.print("upvalues ({d}):\n", .{f.upvalue_names.len});
    for (f.upvalues, 0..) |upval, i| {
        std.debug.print(
            "\t{d}\t{s}\t{d}\t{d}\n",
            .{ i, upValName(f, i), upval.in_stack, upval.idx },
        );
    }
}

fn constantToString(k: LuaValue, allocator: Allocator) ![]const u8 {
    return switch (k) {
        .nil => "nil",
        .bool => |b| try std.fmt.allocPrint(allocator, "{s}", .{if (b) "true" else "false"}),
        .float64 => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
        .int64 => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .obj => |obj| switch (obj.kind) {
            .string => |_| try std.fmt.allocPrint(allocator, "\"{s}\"", .{k.asStr().data()}),
            else => "?",
        },
    };
}

fn upValName(f: *binchunk.Prototype, idx: usize) string {
    if (f.upvalue_names.len > 0) {
        return f.upvalue_names[idx];
    }
    return "-";
}
