//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");

const Range = struct {
    start: u8,
    end: u8,
};

const StateType = union(enum) {
    CompareChar: u8,
    CompareRange: Range,
    Any: void,
    Split: void,
    Match: void,
};

// State machine
const State = struct {
    type: StateType,
    a: ?State,
    b: ?State,
};

// Regexp
const Split = struct {
    a: usize,
    b: usize,
};

const Instruction = union(enum) {
    char: u8,
    match: void,
    jmp: usize,
    split: Split,
    any: void,
};

const Context = struct {
    sp: usize,
    pc: usize,
};

const Program = []Instruction;

pub fn run(prog: []const Instruction, data: []u8) !bool {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var sps = std.ArrayList(Context).init(gpa.allocator());
    defer sps.deinit();

    try sps.append(.{ .pc = 0, .sp = 0 });

    while (sps.items.len != 0) {
        var i: usize = 0;
        while (i < sps.items.len) {
            switch (prog[sps.items[i].pc]) {
                .any => {
                    if (data.len >= sps.items[i].sp) {
                        sps.items[i].pc += 1;
                        sps.items[i].sp += 1;
                    } else {
                        _ = sps.swapRemove(i);
                        // Decrement I so we rerun on the new item
                        continue;
                    }
                },
                .char => |ch| {
                    if (data.len > sps.items[i].sp and ch == data[sps.items[i].sp]) {
                        sps.items[i].pc += 1;
                        sps.items[i].sp += 1;
                    } else {
                        _ = sps.swapRemove(i);
                        // Decrement I so we rerun on the new item
                        continue;
                    }
                },
                .match => {
                    return true;
                },
                .jmp => |target| {
                    sps.items[i].pc = target;
                },
                .split => |split| {
                    sps.items[i].pc = split.a;
                    try sps.append(.{
                        .pc = split.b,
                        .sp = sps.items[i].sp,
                    });
                },
            }
            i += 1;
        }
    }
    return false;
}

fn calulate_program_size(comptime prog: []const u8) usize {
    var size = 1; // We always finish the program with a match
    for (prog) |char| {
        switch (char) {
            '+' => size += 1,
            '*' => size += 2,
            '(', ')' => {},
            '.' => size += 1,
            else => |_| size += 1,
        }
    }
    return size;
}

fn compile(comptime prog: []const u8) ![calulate_program_size(prog)]Instruction {
    var out: [calulate_program_size(prog)]Instruction = undefined;
    var i: usize = 0;

    // Stack for storing when objects start
    var wsi: usize = 0;
    var ws: [10]usize = undefined;

    for (prog) |char| {
        switch (char) {
            '+' => {
                //Compile error (cant start with +)
                if (i == 0) return error.InvalidRegexp;
                out[i] = .{ .split = .{ .a = ws[wsi], .b = i + 1 } };
                i += 1;
            },
            '(' => {
                // store start of capture
                ws[wsi] = i;
                wsi += 1;
                if (wsi >= 10) return error.StackOverflow;
            },
            ')' => {
                if (wsi == 0) return error.ClosingGroupBeforeOpen;
                wsi -= 1;
            },
            '*' => {
                // Move stack
                const end = ws[wsi];
                for (0..(i - end)) |j| {
                    out[i - j] = out[i - j - 1];
                    switch (out[i - j]) {
                        .split => {
                            out[i - j].split.a += 1;
                            out[i - j].split.b += 1;
                        },
                        .jmp => {
                            out[i - j].jmp += 1;
                        },
                        else => {},
                    }
                }
                out[ws[wsi]] = .{ .split = .{ .a = ws[wsi] + 1, .b = i + 2 } };
                i += 1;
                out[i] = .{ .jmp = ws[wsi] };
                i += 1;
            },
            '|' => {
                // Move stack TODO: move into func
                const end = ws[wsi];
                for (0..(i - end)) |j| {
                    out[i - j] = out[i - j - 1];
                    switch (out[i - j]) {
                        .split => {
                            out[i - j].split.a += 1;
                            out[i - j].split.b += 1;
                        },
                        .jmp => {
                            out[i - j].jmp += 1;
                        },
                        else => {},
                    }
                }
                out[ws[wsi]] = .{ .split = .{ .a = ws[wsi] + 1, .b = i + 1 } };
            },
            '.' => {
                ws[wsi] = i;
                out[i] = .{ .any = undefined };
                i += 1;
            },
            else => |c| {
                std.log.debug("char {d} {c}", .{ i, c });
                ws[wsi] = i;
                out[i] = .{ .char = c };
                i += 1;
            },
        }
    }
    out[out.len - 1] = .{ .match = undefined };
    return out;
}

pub fn main() !void {
    //Step 1: Parse input
    var file = std.io.getStdIn();
    defer file.close();
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();
    var buf: [65536]u8 = undefined;

    const size = try in_stream.readAll(&buf);
    std.log.debug("data size {d}", .{size});

    const prog = try compile("c(ab)*c");

    for (prog) |step| {
        std.log.debug("data size {?}", .{step});
    }

    std.log.debug("data size {?}", .{try run(&prog, buf[0..size])});
}
