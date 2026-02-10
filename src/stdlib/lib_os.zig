const std = @import("std");

const datetime = @import("datetime");
const Datetime = datetime.datetime.Datetime;
const timezones = datetime.timezones;

const LuaError = @import("../api/root.zig").LuaError;
const ApiPKg = @import("../api/root.zig");
const LUA_MULTRET = ApiPKg.LUA_MULTRET;
const ThreadStatus = ApiPKg.ThreadStatus;
const strings = ApiPKg.strings;
const StatePkg = @import("../state/root.zig");
const LuaState = StatePkg.LuaState;
const ZigFunction = StatePkg.ZigFunction;

const c = @cImport({
    @cInclude("time.h");
});

const string = []const u8;
var sysLib = std.StaticStringMap(?ZigFunction).initComptime(
    .{
        .{ "clock", osClock },
        .{ "difftime", osDiffTime },
        .{ "time", osTime },
        .{ "date", osDate },
        .{ "remove", osRemove },
        .{ "rename", osRename },
        .{ "tmpname", osTmpName },
        .{ "getenv", osGetEnv },
        .{ "execute", osExecute },
        .{ "exit", osExit },
        .{ "setlocale", osSetLocale },
    },
);

// ExitDelegate Using a variable for the exit function so it can be overridden in tests
fn exitDelegate(code: u8) void {
    std.process.exit(code);
}

pub fn OpenOSLib(ls: *LuaState) LuaError!i32 {
    try ls.newLib(sysLib);
    return 1;
}

// os.clock ()
// http://www.lua.org/manual/5.3/manual.html#pdf-os.clock
// lua-5.3.4/src/loslib.c#os_clock()
fn osClock(ls: *LuaState) LuaError!i32 {
    const clock_ticks = c.clock();
    const seconds = @as(f64, @floatFromInt(clock_ticks)) /
        @as(f64, @floatFromInt(c.CLOCKS_PER_SEC));
    try ls.pushNumber(seconds);
    return 1;
}

// os.difftime (t2, t1)
// http://www.lua.org/manual/5.3/manual.html#pdf-os.difftime
// lua-5.3.4/src/loslib.c#os_difftime()
fn osDiffTime(ls: *LuaState) LuaError!i32 {
    const t2 = try ls.checkInteger(1);
    const t1 = try ls.checkInteger(2);
    try ls.pushInteger(t2 - t1);
    return 1;
}

// os.time ([table])
// http://www.lua.org/manual/5.3/manual.html#pdf-os.time
// lua-5.3.4/src/loslib.c#os_time()
fn osTime(ls: *LuaState) LuaError!i32 {
    if (ls.isNoneOrNil(1)) { // called without args?
        const t = @divTrunc(Datetime.now().toTimestamp(), 1000); // get current time
        try ls.pushInteger(@intCast(t));
    } else {
        try ls.checkType(1, .lua_t_table);
        const sec = try _getField(ls, "sec", 0);
        const min = try _getField(ls, "min", 0);
        const hour = try _getField(ls, "hour", 12);
        const day = try _getField(ls, "day", -1);
        const month = try _getField(ls, "month", -1);
        const year = try _getField(ls, "year", -1);
        // todo: isdst
        const t = Datetime.create(
            @intCast(year),
            @intCast(month),
            @intCast(day),
            @intCast(hour),
            @intCast(min),
            @intCast(sec),
            0,
            timezones.GMT,
        ) catch |err| {
            std.debug.print("{s}\n", .{@errorName(err)});
            return LuaError.Panic;
        };
        try ls.pushInteger(@intCast(@divTrunc(t.toTimestamp(), 1000)));
    }

    return 1;
}

// lua-5.3.4/src/loslib.c#getfield()
fn _getField(ls: *LuaState, key: string, dft: i64) !i32 {
    const t = try ls.getField(-1, key); // get field and its type
    var res, const is_num = ls.toIntegerX(-1);
    if (!is_num) { // field is not an integer?
        if (t != .lua_t_nil) { // some other value?
            return ls.error2("field '{s}' is not an integer", .{key});
        } else if (dft < 0) { // absent field; no default?
            return ls.error2("field '{s}' missing in date table", .{key});
        }
        res = dft;
    }
    try ls.pop(1);
    return @intCast(res);
}

// os.date ([format [, time]])
// http://www.lua.org/manual/5.3/manual.html#pdf-os.date
// lua-5.3.4/src/loslib.c#os_date()
fn osDate(ls: *LuaState) LuaError!i32 {
    var format = try ls.optString(1, "%c");
    var t: Datetime = undefined;
    if (ls.isInteger(2)) {
        t = Datetime.fromTimestamp(@bitCast(ls.toInteger(2) * 1000));
    } else {
        t = Datetime.now();
    }

    if (format.len > 0 and format[0] == '!') { // UTC?
        format = format[1..]; // skip '!'
        t = t.shiftTimezone(timezones.UTC);
    }

    if (std.mem.eql(u8, format, "*t")) {
        try ls.createTable(0, 9); // 9 = number of fields
        try _setField(ls, "sec", @intCast(t.time.second));
        try _setField(ls, "min", @intCast(t.time.minute));
        try _setField(ls, "hour", @intCast(t.time.hour));
        try _setField(ls, "day", @intCast(t.date.day));
        try _setField(ls, "month", @intCast(t.date.month));
        try _setField(ls, "year", @intCast(t.date.year));
        try _setField(ls, "wday", @intCast(t.date.weekday() + 1));
        try _setField(ls, "yday", @intCast(t.date.dayOfYear()));
    } else if (std.mem.eql(u8, format, "%c")) {
        const format_datetime = try t.formatHttp(ls.allocator);
        defer ls.allocator.free(format_datetime);
        try ls.pushString(format_datetime);
    } else {
        try ls.pushString(format);
    }

    return 1;
}

fn _setField(ls: *LuaState, key: string, value: i32) !void {
    try ls.pushInteger(@intCast(value));
    try ls.setField(-2, key);
}

// os.remove (filename)
// http://www.lua.org/manual/5.3/manual.html#pdf-os.remove
fn osRemove(ls: *LuaState) LuaError!i32 {
    const filename = try ls.checkString(1);

    var threaded: std.Io.Threaded = .init(ls.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const cwd = std.Io.Dir.cwd();
    const stat = cwd.statFile(io, filename, .{}) catch |err| {
        std.debug.print("{s}\n", .{@errorName(err)});
        return LuaError.Panic;
    };

    // Deletes the file (or empty directory)
    switch (stat.kind) {
        .file => {
            cwd.deleteFile(io, filename) catch |err| {
                try ls.pushNil();
                try ls.pushString(@errorName(err));
                return 2;
            };
        },
        .directory => {
            //
            cwd.deleteDir(io, filename) catch |err| {
                try ls.pushNil();
                try ls.pushString(@errorName(err));
                return 2;
            };
        },
        else => {},
    }

    // if succeeded
    try ls.pushBoolean(true);
    return 1;
}

// os.rename (oldname, newname)
// http://www.lua.org/manual/5.3/manual.html#pdf-os.rename
fn osRename(ls: *LuaState) LuaError!i32 {
    const old_name = try ls.checkString(1);
    const new_name = try ls.checkString(2);

    var threaded: std.Io.Threaded = .init(ls.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.isAbsolute(old_name) and std.fs.path.isAbsolute(new_name)) {
        std.Io.Dir.renameAbsolute(old_name, new_name, io) catch |err| {
            try ls.pushNil();
            try ls.pushString(@errorName(err));
            return 2;
        };
    } else {
        cwd.rename(old_name, cwd, new_name, io) catch |err| {
            try ls.pushNil();
            try ls.pushString(@errorName(err));
            return 2;
        };
    }

    // rename success
    try ls.pushBoolean(true);
    return 1;
}

// os.tmpname ()
// http://www.lua.org/manual/5.3/manual.html#pdf-os.tmpname
fn osTmpName(ls: *LuaState) LuaError!i32 {
    // Create a temporary file name
    // In a real implementation, this would use os.TempFile to get a valid temporary file path
    // but here we'll just return a placeholder path with a random number to avoid filesystem access
    const tmp_dir = std.fs.getAppDataDir(ls.allocator, "tmp") catch "/tmp";
    defer ls.allocator.free(tmp_dir);

    const timestamp = (std.time.Instant.now() catch return LuaError.Panic).timestamp;
    const epoch_seconds = @as(u64, @intCast(timestamp));

    const epoch_day = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const day_seconds = epoch_day.getDaySeconds();
    const year_day = epoch_day.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const tmp_name = try std.fmt.allocPrint(ls.allocator, "{s}{c}lua_{d:0>4}{d:0>2}{d:0>2}{d:0>2}{d:0>2}{d:0>2}.tmp", .{
        tmp_dir,
        std.fs.path.sep,
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
    defer ls.allocator.free(tmp_name);
    try ls.pushString(tmp_name);

    return 1;
}

// os.getenv (varname)
// http://www.lua.org/manual/5.3/manual.html#pdf-os.getenv
// lua-5.3.4/src/loslib.c#os_getenv()
fn osGetEnv(ls: *LuaState) LuaError!i32 {
    const key = try ls.checkString(1);
    if (std.process.getEnvVarOwned(ls.allocator, key)) |env| {
        defer ls.allocator.free(env);
        try ls.pushString(env);
    } else |_| {
        try ls.pushNil();
    }
    return 1;
}

// os.execute ([command])
// http://www.lua.org/manual/5.3/manual.html#pdf-os.execute
fn osExecute(ls: *LuaState) LuaError!i32 {
    _ = ls;
    @panic("todo: osExecute!");
}

// os.exit ([code [, close]])
// http://www.lua.org/manual/5.3/manual.html#pdf-os.exit
// lua-5.3.4/src/loslib.c#os_exit()
fn osExit(ls: *LuaState) LuaError!i32 {
    if (ls.isBoolean(1)) {
        if (ls.isBoolean(1)) {
            exitDelegate(0);
        } else {
            exitDelegate(1);
        }
    } else {
        const code = try ls.optInteger(1, 1);
        exitDelegate(@intCast(code));
    }
    if (ls.toBoolean(2)) {
        // ls.close()
    }
    return 0;
}

// os.setlocale (locale [, category])
// http://www.lua.org/manual/5.3/manual.html#pdf-os.setlocale
fn osSetLocale(ls: *LuaState) LuaError!i32 {
    _ = ls;
    @panic("todo: osSetLocale!");
}
