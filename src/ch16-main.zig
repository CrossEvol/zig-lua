const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const api = @import("api/root.zig").Api;
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const LuaError = @import("api/root.zig").Api.LuaError;
const strings = @import("api/strings.zig");
const binchunk = @import("binchunk/root.zig").binchunk;
const Lexer = @import("compiler/lexer/lexer.zig").Lexer;
const TokenKind = @import("compiler/lexer/token.zig").TokenKind;
const parser = @import("compiler/parser/parser.zig");
const LuaValue = @import("state/root.zig").state.LuaValue;
const LuaState = @import("state/root.zig").state.LuaState;
const vm = @import("vm/root.zig").vm;
const Instruction = vm.Instruction;
const LuaVM = vm.LuaVM;
const OpCode = vm.OpCode;

const int = i32;

/// hello_world.lua :
// print("Hello, World!")

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

        try testParser(gpa, data, filename);
    }
}

const string = []const u8;

fn testParser(allocator: std.mem.Allocator, chunk: string, chunk_name: string) !void {
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    const ast = try parser.parse(arena, chunk, chunk_name);

    try std.json.fmt(&ast, .{ .whitespace = .indent_2 }).format(stdout_writer);

    const buffer = stdout_writer.toArrayList();
    std.debug.print("{s}", .{buffer.items});
}

test "xxx" {
    const o = @import("compiler/parser/optimizer.zig");
    const block = @import("compiler/ast/block.zig");
    const exp = @import("compiler/ast/exp.zig");
    const stat = @import("compiler/ast/stat.zig");
    std.debug.print("sizeOf Block: {d}\n", .{@sizeOf(block.Block)});
    std.debug.print("sizeOf Exp: {d}\n", .{@sizeOf(exp.Exp)});
    std.debug.print("sizeOf Stat: {d}\n", .{@sizeOf(stat.Stat)});
    _ = o;
}
