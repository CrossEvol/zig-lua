const std = @import("std");

const binchunk = @import("../../binchunk/root.zig");
const Prototype = binchunk.Prototype;
const LocVar = binchunk.LocVar;
const Upvalue = binchunk.Upvalue;
const LuaValue = @import("../../state/root.zig").LuaValue;
const CompilerError = @import("../compiler.zig").CompilerError;
const FuncInfo = @import("func_info.zig").FuncInfo;

const string = []const u8;

pub fn toProto(fi: *FuncInfo) CompilerError!*Prototype {
    const proto = try fi.allocator.create(Prototype);
    proto.* = .{
        .source = "",
        .line_defined = @intCast(fi.line),
        .last_line_defined = @intCast(fi.last_line),
        .num_params = @intCast(fi.num_params),
        .is_vararg = 0,
        .max_stack_size = @intCast(fi.max_regs),
        .code = try fi.insts.toOwnedSlice(fi.allocator),
        .constants = try getConstants(fi),
        .upvalues = try getUpvalues(fi),
        .protos = try toProtos(fi.allocator, try fi.sub_funcs.toOwnedSlice(fi.allocator)),
        .line_info = try fi.line_nums.toOwnedSlice(fi.allocator),
        .loc_vars = try getLocVars(fi),
        .upvalue_names = try getUpvalueNames(fi),
    };

    if (fi.line == 0) {
        proto.last_line_defined = 0;
    }
    if (proto.max_stack_size < 2) {
        proto.max_stack_size = 2;
    }
    if (fi.is_vararg) {
        proto.is_vararg = 1;
    }

    return proto;
}

fn toProtos(allocator: std.mem.Allocator, fis: []*FuncInfo) ![]*Prototype {
    const protos = try allocator.alloc(*Prototype, fis.len);
    for (0.., fis) |i, fi| {
        protos[i] = try toProto(fi);
    }
    return protos;
}

fn getConstants(fi: *FuncInfo) ![]LuaValue {
    const consts = try fi.allocator.alloc(LuaValue, fi.constants.count());
    var iter = fi.constants.iterator();
    while (iter.next()) |entry| {
        const k = entry.key_ptr.*;
        const idx = entry.value_ptr.*;
        consts[@as(usize, @intCast(idx))] = k;
    }
    return consts;
}

fn getLocVars(fi: *FuncInfo) ![]LocVar {
    const loc_vars = try fi.allocator.alloc(LocVar, fi.loc_vars.items.len);
    for (0.., fi.loc_vars.items) |i, loc_var| {
        loc_vars[i] = LocVar.init(
            loc_var.*.name,
            @as(u32, @intCast(loc_var.*.start_pc)),
            @as(u32, @intCast(loc_var.*.end_pc)),
        );
    }
    return loc_vars;
}

fn getUpvalues(fi: *FuncInfo) ![]Upvalue {
    const upvals = try fi.allocator.alloc(Upvalue, fi.upvalues.count());
    var iter = fi.upvalues.valueIterator();
    while (iter.next()) |uv| {
        if (uv.*.loc_var_slot >= 0) { // instack
            upvals[@as(usize, @intCast(uv.index))] = Upvalue.init(1, @as(u8, @intCast(uv.*.loc_var_slot)));
        } else {
            upvals[@as(usize, @intCast(uv.index))] = Upvalue.init(0, @as(u8, @intCast(uv.*.upval_index)));
        }
    }
    return upvals;
}

fn getUpvalueNames(fi: *FuncInfo) ![]string {
    const names = try fi.allocator.alloc(string, fi.upvalues.count());

    var iter = fi.upvalues.iterator();
    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const uv = entry.value_ptr.*;
        names[@as(usize, @intCast(uv.index))] = name;
    }

    return names;
}
