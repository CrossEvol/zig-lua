const std = @import("std");

const Reader = @import("reader.zig").Reader;
const LuaValue = @import("state").LuaValue;

const byte = u8;
const uint = u32;
const string = []const u8;

pub const Header = struct {
    pub const lua_signature = "\x1bLua";
    pub const luac_version = 0x53;
    pub const luac_format = 0;
    pub const luac_data = "\x19\x93\r\n\x1a\n";
    pub const cint_size = 4;
    pub const csizet_size = 8;
    pub const instruction_size = 4;
    pub const lua_integer_size = 8;
    pub const lua_number_size = 8;
    pub const luac_int = 0x5678;
    pub const luac_num = 370.5;
};

pub const Tag = enum(u8) {
    nil = 0x00,
    boolean = 0x01,
    number = 0x03,
    integer = 0x13,
    short_str = 0x04,
    long_str = 0x14,
};

// function prototype
pub const Prototype = struct {
    source: string,
    line_defined: u32,
    last_line_defined: u32,
    num_params: byte,
    is_vararg: byte,
    max_stack_size: byte,
    code: []const uint,
    constants: []LuaValue,
    upvalues: []Upvalue,
    protos: []const *Prototype,
    line_info: []const uint,
    loc_vars: []const LocVar,
    upvalue_names: []const string,
};

pub const Upvalue = struct {
    in_stack: byte,
    idx: byte,
};

pub const LocVar = struct {
    var_name: string,
    start_pc: u32,
    end_pc: u32,
};

pub fn undump(data: []const byte) *Prototype {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // Note: We don't defer arena.deinit() here because the returned Prototype uses arena memory
    const allocator = arena.allocator();
    var reader = Reader.init(data, allocator);
    reader.checkHeader();
    _ = reader.readByte(); // size_upvalues
    return reader.readProto("");
}
