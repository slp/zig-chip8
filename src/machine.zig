const std = @import("std");
const debug = std.log.debug;
const warn = std.log.warn;
const assert = std.debug.assert;
const times = @import("times.zig");

const SCREEN_WIDTH = 64;
const SCREEN_HEIGHT = 32;
pub const MEM_SIZE = 4096;

const MachineError = error{
    InvalidRegister,
    UnknownInstruction,
};

pub const CpuState = enum {
    Running,
    WaitingForKey,
};

pub const Machine = struct {
    screen: [SCREEN_HEIGHT][SCREEN_WIDTH]u8 = undefined,

    cpu_state: CpuState = .Running,
    pc: u16 = 0x200,
    index: u16 = 0,
    vregs: [16]u8,
    stack: [16]u16,
    sp: u8 = 0,

    delay_timer: u8 = 0,
    sound_timer: u8 = 0,
    timestamp: i64 = 0,

    key_down: [16]bool = [_]bool{false} ** 16,
    read_key_reg: u8 = 0,

    rnd: std.rand.Xoshiro256,

    pub fn init() Machine {
        var machine = Machine{
            .vregs = std.mem.zeroes([16]u8),
            .stack = std.mem.zeroes([16]u16),
            .rnd = std.rand.DefaultPrng.init(0),
        };

        machine.clearScreen();

        return machine;
    }

    pub fn dumpState(self: *Machine) void {
        debug("PC={X:0>4}\nINDEX={X:0>4}", .{ self.pc, self.index });
        for (self.vregs) |val, i| {
            debug("V{X}={X:0>2}", .{ i, val });
        }
    }

    pub fn updateTimers(self: *Machine) void {
        if (self.timestamp == 0) {
            self.timestamp = std.time.milliTimestamp();
        } else {
            const now = std.time.milliTimestamp();
            if ((now - self.timestamp) > 16) {
                self.timestamp = now;
                if (self.delay_timer > 0) {
                    self.delay_timer -= 1;
                }
                if (self.sound_timer > 0) {
                    self.sound_timer -= 1;
                }
            }
        }
    }

    pub fn updateKey(self: *Machine, key: u8, is_down: bool) void {
        debug("Update key: {} {}", .{ key, is_down });
        assert(key < 16);
        if (self.cpu_state == CpuState.WaitingForKey and self.key_down[key] != is_down) {
            self.cpu_state = CpuState.Running;
            self.vregs[self.read_key_reg] = key;
        }
        self.key_down[key] = is_down;
    }

    fn fetchOpcode(self: *Machine, mem: *[MEM_SIZE]u8, pc: u16) u16 {
        _ = self;
        const b1: u8 = mem[pc];
        const b2: u8 = mem[pc + 1];
        return (@as(u16, b1) << 8) | b2;
    }

    fn clearScreen(self: *Machine) void {
        _ = self;
        var y: u8 = 0;
        while (y < SCREEN_HEIGHT) : (y += 1) {
            self.screen[y] = std.mem.zeroes([SCREEN_WIDTH]u8);
        }
    }

    pub fn getScreen(self: *Machine) *[SCREEN_HEIGHT][SCREEN_WIDTH]u8 {
        return &self.screen;
    }

    fn addAndFlag(self: *Machine, xreg: u8, yreg: u8) void {
        var result: u8 = undefined;
        if (@addWithOverflow(u8, self.vregs[xreg], self.vregs[yreg], &result)) {
            self.vregs[0xf] = 1;
        } else {
            self.vregs[0xf] = 0;
        }
        self.vregs[xreg] = result;
    }

    fn subAndFlag(self: *Machine, xreg: u8, minuend_reg: u8, subtrahend_reg: u8) void {
        var result: u8 = undefined;
        if (!@subWithOverflow(u8, self.vregs[minuend_reg], self.vregs[subtrahend_reg], &result)) {
            self.vregs[0xf] = 1;
        } else {
            self.vregs[0xf] = 0;
        }
        self.vregs[xreg] = result;
    }

    fn checkBitAndShift(self: *Machine, xreg: u8, yreg: u8, left: bool) void {
        _ = yreg;

        //self.vregs[xreg] = self.vregs[yreg];

        var bit: u8 = undefined;
        if (left) {
            bit = 0x80;
        } else {
            bit = 0x1;
        }

        if (self.vregs[xreg] & bit == bit) {
            self.vregs[0xf] = 1;
        } else {
            self.vregs[0xf] = 0;
        }

        if (left) {
            self.vregs[xreg] = self.vregs[xreg] << 1;
        } else {
            self.vregs[xreg] = self.vregs[xreg] >> 1;
        }
    }

    fn doArithmetic(self: *Machine, op: u16, xreg: u8, yreg: u8) MachineError!void {
        switch (op) {
            0 => self.vregs[xreg] = self.vregs[yreg],
            1 => self.vregs[xreg] |= self.vregs[yreg],
            2 => self.vregs[xreg] &= self.vregs[yreg],
            3 => self.vregs[xreg] ^= self.vregs[yreg],
            4 => self.addAndFlag(xreg, yreg),
            5 => self.subAndFlag(xreg, xreg, yreg),
            6 => self.checkBitAndShift(xreg, yreg, false),
            7 => self.subAndFlag(xreg, yreg, xreg),
            0xe => self.checkBitAndShift(xreg, yreg, true),
            else => {
                debug("unknown 0x8XXX instruction: 0x8X{X:0>2}", .{op});
                return MachineError.UnknownInstruction;
            },
        }
    }

    fn doDraw(self: *Machine, mem: *[MEM_SIZE]u8, npix: u8, xreg: u8, yreg: u8) void {
        self.vregs[0xf] = 0;

        debug("npix={}", .{npix});

        var y = self.vregs[yreg] & 31;
        var n: u8 = 0;
        while (n < npix) : (n += 1) {
            var x = self.vregs[xreg] & 63;
            var sprite: u8 = mem[self.index + n];
            var bit: u8 = 0;
            while (bit < 8) : (bit += 1) {
                debug("x={}, y={}", .{ x, y });
                if ((sprite & 0x80) == 0x80) {
                    if (self.screen[y][x] == 1) {
                        debug(" OFF", .{});
                        self.screen[y][x] = 0;
                        self.vregs[0xf] = 1;
                    } else {
                        debug(" ON", .{});
                        self.screen[y][x] = 1;
                    }
                } else {
                    debug(" empty", .{});
                }
                sprite <<= 1;
                x += 1;
                if (x == SCREEN_WIDTH) break;
            }
            y += 1;
            if (y == SCREEN_HEIGHT) break;
        }
    }

    fn getRegisterX(self: *Machine, inst: u16) MachineError!u8 {
        _ = self;
        const reg: u8 = @intCast(u8, (inst & 0x0f00) >> 8);
        if (reg > 0xf) {
            return MachineError.InvalidRegister;
        }
        return reg;
    }

    fn getRegisterY(self: *Machine, inst: u16) MachineError!u8 {
        _ = self;
        const reg: u8 = @intCast(u8, (inst & 0x00f0) >> 4);
        if (reg > 0xf) {
            return MachineError.InvalidRegister;
        }
        return reg;
    }

    pub fn fetchAndExec(self: *Machine, mem: *[MEM_SIZE]u8) MachineError!u32 {
        const inst: u16 = self.fetchOpcode(mem, self.pc);
        self.pc += 2;

        debug("inst={x:0>4}", .{inst});

        var inst_cost: u32 = 0;

        switch (inst) {
            0x00e0 => {
                debug("clear screen", .{});
                self.clearScreen();
                inst_cost = times.CLEAR_SCREEN;
            },
            0x00ee => {
                debug("return", .{});
                self.sp -= 1;
                self.pc = self.stack[self.sp];
                inst_cost = times.RETURN;
            },
            0x1000...0x1fff => {
                debug("jump", .{});
                const new_pc: u16 = inst & 0x0fff;
                assert(new_pc < 4096);
                self.pc = new_pc;
                inst_cost = times.JUMP;
            },
            0x2000...0x2fff => {
                debug("call 2x", .{});
                const new_pc: u16 = inst & 0x0fff;
                assert(new_pc < 4096);
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = new_pc;
                inst_cost = times.CALL;
            },
            0x3000...0x3fff => {
                debug("skip 3x", .{});
                const xreg = try self.getRegisterX(inst);
                if (self.vregs[xreg] == @intCast(u8, inst & 0x00ff)) {
                    self.pc += 2;
                }
                inst_cost = times.SKIP_3X;
            },
            0x4000...0x4fff => {
                debug("skip 4x", .{});
                const xreg = try self.getRegisterX(inst);
                if (self.vregs[xreg] != @intCast(u8, inst & 0x00ff)) {
                    self.pc += 2;
                }
                inst_cost = times.SKIP_4X;
            },
            0x5000...0x5fff => {
                debug("skip 5x", .{});
                const xreg = try self.getRegisterX(inst);
                const yreg = try self.getRegisterY(inst);
                if (self.vregs[xreg] == self.vregs[yreg]) {
                    self.pc += 2;
                }
                inst_cost = times.SKIP_5X;
            },
            0x6000...0x6fff => {
                debug("set register", .{});
                const xreg = try self.getRegisterX(inst);
                self.vregs[xreg] = @intCast(u8, inst & 0x00ff);
                inst_cost = times.SET_REGISTER;
            },
            0x7000...0x7fff => {
                debug("add", .{});
                const xreg: u16 = (inst & 0x0f00) >> 8;
                var result: u8 = undefined;
                _ = @addWithOverflow(u8, self.vregs[xreg], @intCast(u8, inst & 0x00ff), &result);
                self.vregs[xreg] = result;
                inst_cost = times.ADD;
            },
            0x8000...0x8fff => {
                debug("arithmetic", .{});
                const op: u16 = (inst & 0xf);
                const xreg = try self.getRegisterX(inst);
                const yreg = try self.getRegisterY(inst);

                try self.doArithmetic(op, xreg, yreg);
                inst_cost = times.ARITHMETIC;
            },
            0x9000...0x9fff => {
                debug("skip 9x", .{});
                const xreg = try self.getRegisterX(inst);
                const yreg = try self.getRegisterY(inst);
                if (self.vregs[xreg] != self.vregs[yreg]) {
                    self.pc += 2;
                }
                inst_cost = times.SKIP_9X;
            },
            0xa000...0xafff => {
                debug("set index", .{});
                self.index = inst & 0x0fff;
                inst_cost = times.SET_INDEX;
            },
            0xc000...0xcfff => {
                debug("random", .{});
                const xreg = try self.getRegisterX(inst);
                var number: u8 = @intCast(u8, inst & 0x00ff);
                const randnum: u8 = self.rnd.random().int(u8);
                number &= randnum;
                self.vregs[xreg] = number;
                inst_cost = times.GET_RANDOM;
            },
            0xd000...0xdfff => {
                debug("draw screen", .{});
                const npix = @intCast(u8, inst & 0x000f);
                const xreg = try self.getRegisterX(inst);
                const yreg = try self.getRegisterY(inst);
                self.doDraw(mem, npix, xreg, yreg);
                inst_cost = times.DRAW;
            },
            0xe000...0xefff => {
                debug("check key", .{});
                const op = @intCast(u8, inst & 0x00ff);
                const xreg = try self.getRegisterX(inst);
                const key = self.vregs[xreg];
                assert(key < 16);

                switch (op) {
                    0x9e => {
                        if (self.key_down[key]) {
                            self.pc += 2;
                        }
                    },
                    0xa1 => {
                        if (!self.key_down[key]) {
                            self.pc += 2;
                        }
                    },
                    else => {
                        warn("unknown 0xEXXX instruction: 0x{X:0>4}", .{inst});
                        return MachineError.UnknownInstruction;
                    },
                }
                inst_cost = times.CHECK_KEY;
            },
            0xf000...0xffff => {
                const op = inst & 0xff;
                const xreg = try self.getRegisterX(inst);
                switch (op) {
                    0x07 => {
                        debug("get delay timer", .{});
                        self.vregs[xreg] = self.delay_timer;
                        inst_cost = times.GET_DELAY_TIMER;
                    },
                    0x0a => {
                        debug("get key", .{});
                        self.read_key_reg = xreg;
                        self.cpu_state = CpuState.WaitingForKey;
                        inst_cost = times.GET_KEY;
                    },
                    0x15 => {
                        debug("set delay timer", .{});
                        self.delay_timer = self.vregs[xreg];
                        inst_cost = times.SET_DELAY_TIMER;
                    },
                    0x18 => {
                        debug("set sound timer", .{});
                        self.sound_timer = self.vregs[xreg];
                        inst_cost = times.SET_SOUND_TIMER;
                    },
                    0x1e => {
                        var result: u16 = undefined;
                        _ = @addWithOverflow(u16, self.index, @as(u16, self.vregs[xreg]), &result);
                        self.index = result;
                        inst_cost = times.ADD_TO_INDEX;
                    },
                    0x29 => {
                        debug("set font", .{});
                        self.index = self.vregs[xreg] * 5;
                        inst_cost = times.SET_FONT;
                    },
                    0x33 => {
                        var number = self.vregs[xreg];
                        debug("number={}", .{number});
                        mem[self.index] = number / 100;
                        number = number % 100;
                        mem[self.index + 1] = number / 10;
                        mem[self.index + 2] = number % 10;
                        debug(" mem={} {} {}", .{ mem[self.index], mem[self.index + 1], mem[self.index + 2] });
                        inst_cost = times.BCD;
                    },
                    0x55 => {
                        var i: u8 = 0;
                        while (i <= xreg) : (i += 1) {
                            mem[self.index + i] = self.vregs[i];
                        }
                        inst_cost = times.STORE_MEM;
                    },
                    0x65 => {
                        var i: u8 = 0;
                        while (i <= xreg) : (i += 1) {
                            self.vregs[i] = mem[self.index + i];
                        }
                        inst_cost = times.LOAD_MEM;
                    },
                    else => {
                        warn("unknown 0xFXXX instruction: 0x{X:0>4}", .{inst});
                        return MachineError.UnknownInstruction;
                    },
                }
            },
            else => {
                warn("unknown instruction 0x{X:0>4}", .{mem[self.pc]});
                return MachineError.UnknownInstruction;
            },
        }

        return inst_cost;
    }
};
