const std = @import("std");

const binchunk = @import("../binchunk/root.zig");
const codegen = @import("codegen/root.zig");
const parser = @import("parser/parser.zig");

pub const CompilerError = error{ICompilerError} || error{OutOfMemory};
const string = []const u8;

pub fn Compile(allocator: std.mem.Allocator, chunk: string, chunk_name: string) !*binchunk.Prototype {
    const ast = try parser.parse(allocator, chunk, chunk_name);
    const proto = try codegen.genProto(allocator, ast);
    setSource(proto, chunk_name);
    return proto;
}

fn setSource(proto: *binchunk.Prototype, chunk_name: string) void {
    proto.*.source = chunk_name;
    for (proto.protos) |f| {
        setSource(f, chunk_name);
    }
}
