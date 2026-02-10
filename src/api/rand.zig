const std = @import("std");

pub const Rand = struct {
    prng: std.Random.DefaultPrng,

    pub fn init(seed0: u64) Rand {
        return .{ .prng = std.Random.DefaultPrng.init(seed0) };
    }

    pub fn seed(self: *Rand, new_seed: u64) void {
        self.prng = std.Random.DefaultPrng.init(new_seed);
    }

    pub fn float64(self: *Rand) f64 {
        return self.prng.random().float(f64);
    }

    pub fn int63(self: *Rand) i64 {
        return self.prng.random().int(i64) & 0x7FFFFFFFFFFFFFFF;
    }

    pub fn int63n(self: *Rand, n: i64) i64 {
        return self.prng.random().intRangeAtMost(i64, 0, n - 1);
    }
};
