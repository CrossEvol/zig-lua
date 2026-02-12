const std = @import("std");

const LuaError = @import("../api/root.zig").LuaError;
const ApiPKg = @import("../api/root.zig");
const luaUpvalueIndex = ApiPKg.luaUpvalueIndex;
const LUA_REGISTRYINDEX = ApiPKg.LUA_REGISTRYINDEX;
const LUA_MULTRET = ApiPKg.LUA_MULTRET;
const ThreadStatus = ApiPKg.ThreadStatus;
const strings = ApiPKg.strings;
const StatePkg = @import("../state/root.zig");
const LuaState = StatePkg.LuaState;
const ZigFunction = StatePkg.ZigFunction;
const default_zig_function_impl = @import("../state/root.zig").default_zig_function_impl;

const string = []const u8;
// key, in the registry, for table of loaded modules
const LUA_LOADED_TABLE = "_LOADED";

// key, in the registry, for table of preloaded loaders
const LUA_PRELOAD_TABLE = "_PRELOAD";

// package.config
const LUA_DIRSEP = &[_:0]u8{std.fs.path.sep};
const LUA_PATH_SEP = ";";
const LUA_PATH_MARK = "?";
const LUA_EXEC_DIR = "!";
const LUA_IGMARK = "-";

var pkgFuncs = std.StaticStringMap(?ZigFunction).initComptime(
    .{
        .{ "searchpath", pkgSearchPath },
        // placeholders
        .{ "preload", default_zig_function_impl }, // null
        .{ "cpath", default_zig_function_impl }, // null
        .{ "path", default_zig_function_impl }, // null
        .{ "searchers", default_zig_function_impl }, // null
        .{ "loaded", default_zig_function_impl }, // null
    },
);

var llFuncs = std.StaticStringMap(?ZigFunction).initComptime(
    .{
        .{ "require", pkgRequire },
    },
);

pub fn openPackageLib(ls: *LuaState) LuaError!i32 {
    try ls.newLib(pkgFuncs); // create 'package' table
    try createSearchersTable(ls);

    // set paths
    try ls.pushString("./?.lua;./?/init.lua");
    try ls.setField(-2, "path");

    // store config information
    const config_string = LUA_DIRSEP ++ "\n" ++ LUA_PATH_SEP ++ "\n" ++
        LUA_PATH_MARK ++ "\n" ++ LUA_EXEC_DIR ++ "\n" ++ LUA_IGMARK ++ "\n";
    try ls.pushString(config_string);
    try ls.setField(-2, "config");

    // set field 'loaded'
    _ = try ls.getSubTable(LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
    try ls.setField(-2, "loaded");

    // set field 'preload'
    _ = try ls.getSubTable(LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
    try ls.setField(-2, "preload");

    try ls.pushGlobalTable();
    try ls.pushValue(-2); // set 'package' as upvalue for next lib
    try ls.setFuncs(llFuncs, 1); // open lib into global table
    try ls.pop(1); // pop global table
    return 1; // return 'package' table
}

fn createSearchersTable(ls: *LuaState) LuaError!void {
    const searchers = [_]ZigFunction{ preloadSearcher, luaSearcher };

    // create 'searchers' table
    try ls.createTable(searchers.len, 0);

    // fill it with predefined searchers
    for (0.., searchers) |idx, searcher| {
        try ls.pushValue(-2); // set 'package' as upvalue for all searchers
        try ls.pushZigClosure(searcher, 1);
        try ls.rawSetI(-2, @intCast(idx + 1));
    }
    try ls.setField(-2, "searchers"); // put it in field 'searchers'
}

fn preloadSearcher(ls: *LuaState) LuaError!i32 {
    const name = try ls.checkString(1);
    _ = try ls.getField(LUA_REGISTRYINDEX, "_PRELOAD");
    if (try ls.getField(-1, name) == .lua_t_nil) { // not found?
        const err_msg = try std.fmt.allocPrint(ls.allocator, "\n\tno field package.preload['{s}']", .{name});
        defer ls.allocator.free(err_msg);
        try ls.pushString(err_msg);
    }
    return 1;
}

fn luaSearcher(ls: *LuaState) LuaError!i32 {
    const name = try ls.checkString(1);
    _ = try ls.getField(luaUpvalueIndex(1), "path");
    const path, const ok = try ls.toStringX(ls.allocator, -1);
    if (!ok) {
        _ = try ls.error2("'package.path' must be a string", .{});
    }

    const filename, const err_msg = try _searchPath(ls.allocator, name, path.bytes, ".", LUA_DIRSEP);
    defer ls.allocator.free(filename);
    defer ls.allocator.free(err_msg);

    if (!std.mem.eql(u8, err_msg, "")) {
        try ls.pushString(err_msg);
        return 1;
    }

    if (try ls.loadFile(filename) == .lua_ok) { // module loaded successfully?
        try ls.pushString(filename); // will be 2nd argument to module
        return 2; // return open function and file name
    } else {
        return ls.error2("error loading module '{s}' from file '{s}':\n\t{s}", .{ try ls.checkString(1), filename, try ls.checkString(-1) });
    }
}

// package.searchpath (name, path [, sep [, rep]])
// http://www.lua.org/manual/5.3/manual.html#pdf-package.searchpath
// loadlib.c#ll_searchpath
fn pkgSearchPath(ls: *LuaState) LuaError!i32 {
    const name = try ls.checkString(1);
    const path = try ls.checkString(2);
    const sep = try ls.optString(3, ".");
    const rep = try ls.optString(4, LUA_DIRSEP);
    const filename, const err_msg = try _searchPath(ls.allocator, name, path, sep, rep);
    defer ls.allocator.free(filename);
    defer ls.allocator.free(err_msg);

    if (std.mem.eql(u8, err_msg, "")) {
        try ls.pushString(filename);
        return 1;
    } else {
        try ls.pushNil();
        try ls.pushString(err_msg);
        return 2;
    }
}

/// -> ( filename : string, err_msg : string )
fn _searchPath(allocator: std.mem.Allocator, name0: string, path: string, sep: string, dir_sep: string) !struct { string, string } {
    var err_msg: string = try allocator.alloc(u8, 0);

    const name = if (!std.mem.eql(u8, sep, ""))
        try strings.Replace(allocator, name0, sep, dir_sep, -1)
    else
        try allocator.dupe(u8, name0);
    defer allocator.free(name);

    const filenames = try strings.Split(allocator, path, LUA_PATH_SEP);
    defer allocator.free(filenames);

    for (filenames) |f| {
        const filename = try strings.Replace(allocator, f, LUA_PATH_MARK, name, -1);
        defer allocator.free(filename);

        var threaded: std.Io.Threaded = .init(allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();

        const cwd = std.Io.Dir.cwd();
        if (cwd.statFile(io, filename, .{})) |stat| {
            if (stat.kind == .file or stat.kind == .directory) {
                allocator.free(err_msg);
                return .{ try allocator.dupe(u8, filename), "" };
            }
        } else |err| {
            if (err == error.FileNotFound) {
                const old_err_msg = err_msg;
                defer allocator.free(old_err_msg);
                err_msg = try std.fmt.allocPrint(allocator, "{s}\n\tno file '{s}'", .{ old_err_msg, filename });
            }
        }
    }

    return .{ "", err_msg };
}

// require (modname)
// http://www.lua.org/manual/5.3/manual.html#pdf-require
fn pkgRequire(ls: *LuaState) LuaError!i32 {
    const name = try ls.checkString(1);
    try ls.setTop(1); // LOADED table will be at index 2
    _ = try ls.getField(LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
    _ = try ls.getField(2, name); // LOADED[name]
    if (ls.toBoolean(-1)) { // is it there?
        return 1; // package is already loaded
    }

    // else must load package
    try ls.pop(1); // remove 'getfield' result
    try _findLoader(ls, name);
    try ls.pushString(name); // pass name as argument to module loader
    ls.insert(-2); // name is 1st argument (before search data)
    try ls.call(2, 1); // run loader to load module
    if (!ls.isNil(-1)) { // non-nil return?
        try ls.setField(2, name); // LOADED[name] = returned value
    }
    if (try ls.getField(2, name) == .lua_t_nil) { // module set no value?
        try ls.pushBoolean(true); // use true as result
        try ls.pushValue(-1); // extra copy to be returned
        try ls.setField(2, name); // LOADED[name] = true
    }
    return 1;
}

fn _findLoader(ls: *LuaState, name: string) LuaError!void {
    // push 'package.searchers' to index 3 in the stack
    if (try ls.getField(luaUpvalueIndex(1), "searchers") != .lua_t_table) {
        _ = try ls.error2("'package.searchers' must be a table", .{});
    }

    // to build error message
    var err_msg = try std.ArrayList(u8).initCapacity(ls.allocator, 32);
    defer err_msg.deinit(ls.allocator);
    try err_msg.appendSlice(ls.allocator, "module '");
    try err_msg.appendSlice(ls.allocator, name);
    try err_msg.appendSlice(ls.allocator, "' not found:");

    // iterate over available searchers to find a loader
    var i: i64 = 1;
    while (true) : (i += 1) {
        if (try ls.rawGetI(3, i) == .lua_t_nil) { // no more searchers?
            try ls.pop(1); // remove nil
            std.debug.print("{s}", .{try err_msg.toOwnedSlice(ls.allocator)});
            _ = try ls.error2("module '{s}' not found!", .{name}); // create error message
        }

        try ls.pushString(name);
        try ls.call(1, 2); // call it
        if (ls.isFunction(-2)) { // did it find a loader?
            return; // module loader found
        } else if (ls.isString(-2)) { // searcher returned error message?
            try ls.pop(1); // remove extra return
            try err_msg.appendSlice(ls.allocator, try ls.checkString(-1));
        } else {
            try ls.pop(2); // remove both returns
        }
    }
}
