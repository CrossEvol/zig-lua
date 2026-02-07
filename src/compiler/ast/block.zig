const Exp = @import("exp.zig").Exp;
const Stat = @import("stat.zig").Stat;

// chunk ::= block
// type Chunk *Block

// block ::= {stat} [retstat]
// retstat ::= return [explist] [‘;’]
// explist ::= exp {‘,’ exp}
pub const Block = struct {
    last_line: i32,
    stats: []Stat,
    ret_exps: ?[]Exp,

    pub fn init(last_line: usize, stats: []Stat, ret_exps: ?[]Exp) Block {
        return .{
            .last_line = last_line,
            .stats = stats,
            .ret_exps = ret_exps,
        };
    }
};
