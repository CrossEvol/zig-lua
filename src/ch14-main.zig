const std = @import("std");
const Allocator = std.mem.Allocator;

const ApiPkg = @import("api/root.zig");
const ArithOp = ApiPkg.ArithOp;
const CompareOp = ApiPkg.CompareOp;
const LuaError = @import("api/root.zig").LuaError;
const strings = ApiPkg.strings;
const binchunk = @import("binchunk/root.zig");
const Lexer = @import("compiler/lexer/lexer.zig").Lexer;
const TokenKind = @import("compiler/lexer/token.zig").TokenKind;
const LuaValue = @import("state/root.zig").LuaValue;
const LuaState = @import("state/root.zig").LuaState;
const vm = @import("vm/root.zig");
const Instruction = vm.Instruction;
const LuaVM = vm.LuaVM;
const OpCode = vm.OpCode;

const int = i32;

/// test14_lexer.lua :
// print("hello") -- short comment
// print("world") --> another short comment
// print() --[[ long comment ]]
// --[===[
//   another
//   long comment
// ]===]

// print("hello, \z
//        world!") --> hello, world!

// a = 'alo\n123"'
// a = "alo\n123\""
// a = '\97lo\10\04923"'
// a = [[alo
// 123"]]
// a = [==[
// alo
// 123"]==]

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

        try testLexer(gpa, data, filename);
    }
}

const string = []const u8;

fn testLexer(allocator: std.mem.Allocator, chunk: string, chunk_name: string) !void {
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    var lexer = Lexer.init(arena_allocator.allocator(), chunk, chunk_name);
    defer lexer.deinit();
    while (true) {
        const line, const kind, const token = try lexer.nextToken();
        std.debug.print("[{d:>2}] [{s:<10}] {s}\n", .{ line, kindToCategory(@intFromEnum(kind)), token });
        if (kind == .token_eof) {
            break;
        }
    }
}

fn kindToCategory(kind: u32) string {
    if (kind < @intFromEnum(TokenKind.token_sep_semi)) {
        return "other";
    }
    if (kind <= @intFromEnum(TokenKind.token_sep_rcurly)) {
        return "separator";
    }
    if (kind <= @intFromEnum(TokenKind.token_op_not)) {
        return "operator";
    }
    if (kind <= @intFromEnum(TokenKind.token_kw_while)) {
        return "keyword";
    }
    if (kind == @intFromEnum(TokenKind.token_identifier)) {
        return "identifier";
    }
    if (kind == @intFromEnum(TokenKind.token_number)) {
        return "number";
    }
    if (kind == @intFromEnum(TokenKind.token_string)) {
        return "string";
    }
    return "other";
}
