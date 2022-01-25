const std = @import("std");
const err = std.log.err;
const debug = std.log.debug;
const machine = @import("machine.zig");
const sdl = @import("sdl.zig");

// Fonts taken from https://tobiasvl.github.io/blog/write-a-chip-8-emulator/
const Fonts = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

pub const log_level: std.log.Level = .info;

pub fn main() !void {
    var mem: [machine.MEM_SIZE]u8 = std.mem.zeroes([machine.MEM_SIZE]u8);

    std.mem.copy(u8, mem[0..80], Fonts[0..80]);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        err("Usage: {s} ROM_FILE", .{args[0]});
        return;
    }

    const rom = args[1];
    var file = try std.fs.cwd().openFile(rom, .{});
    defer file.close();

    const len = try file.readAll(mem[0x200..]);
    debug("Read ROM with {} bytes", .{len});

    var gui = try sdl.Sdl.init();

    var chip8 = machine.Machine.init();

    while (true) {
        if (chip8.cpu_state == .Running) {
            debug("Executing instruction", .{});
            const cost = chip8.fetchAndExec(&mem) catch break;
            std.time.sleep(cost * 1000);
        } else {
            // Take a nap for 16ms
            std.time.sleep(16 * 1000 * 1000);
        }

        gui.updateScreen(chip8.getScreen());
        chip8.updateTimers();

        while (true) {
            var event = gui.getEvent();
            switch (event.kind) {
                .None => break,
                .Quit => return,
                .KeyUp => chip8.updateKey(@intCast(u8, event.data), false),
                .KeyDown => chip8.updateKey(@intCast(u8, event.data), true),
            }
        }

        chip8.dumpState();
    }
}
