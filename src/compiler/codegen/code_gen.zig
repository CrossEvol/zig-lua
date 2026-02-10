const std = @import("std");

const Prototype = @import("../../binchunk/root.zig").Prototype;
const AstPkg = @import("../ast/root.zig");
const Block = AstPkg.Block;
const FuncDefExp = AstPkg.FuncDefExp;
const cgFuncDefExp = @import("cg_exp.zig").cgFuncDefExp;
const FuncInfo = @import("func_info.zig").FuncInfo;
const toProto = @import("fi2proto.zig").toProto;

pub fn genProto(allocator: std.mem.Allocator, chunk: Block) !*Prototype {
    const fd = try allocator.create(FuncDefExp);
    fd.* = FuncDefExp.init(0, chunk.last_line, null, true, chunk);

    const fi = try FuncInfo.init(allocator, null, fd);
    _ = try fi.addLocVar("_ENV", 0);
    try cgFuncDefExp(fi, fd, 0);
    return try toProto(fi.*.sub_funcs.items[0]);
}
