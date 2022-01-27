const c = @cImport({
    @cInclude("SDL.h");
});
const m = @cImport({
    @cInclude("SDL_mixer.h");
});
const assert = @import("std").debug.assert;
const warn = @import("std").log.warn;

const SdlError = error{
    InitializationFailed,
    CreateWindowFailed,
    CreateRendererFailed,
    LoadWavFailed,
    OpenAudioFailed,
};

pub const EventKind = enum {
    KeyDown,
    KeyUp,
    Quit,
    None,
};

pub const Event = struct {
    kind: EventKind,
    data: u32 = 0,

    pub fn quitEvent() Event {
        return Event{
            .kind = .Quit,
        };
    }

    pub fn noneEvent() Event {
        return Event{
            .kind = .None,
        };
    }

    pub fn keyEvent(event: u32, key: u32) Event {
        _ = event;
        var kind: EventKind = undefined;
        if (event == c.SDL_KEYDOWN) {
            kind = .KeyDown;
        } else {
            kind = .KeyUp;
        }
        return Event{
            .kind = kind,
            .data = key,
        };
    }
};

pub const Key = enum {
    Key_0,
    Key_1,
    Key_2,
    Key_3,
    Key_4,
    Key_5,
    Key_6,
    Key_7,
    Key_8,
    Key_9,
    Key_A,
    Key_B,
    Key_C,
    Key_D,
    Key_E,
    Key_F,
};

const SdlAudio = struct {
    beep: *m.Mix_Chunk,
};

pub const Sdl = struct {
    screen: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    audio: ?SdlAudio,

    pub fn init() SdlError!Sdl {
        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return SdlError.InitializationFailed;
        }

        const screen = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 320, c.SDL_WINDOW_SHOWN) orelse
            {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return SdlError.CreateWindowFailed;
        };

        const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
            c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
            return SdlError.CreateRendererFailed;
        };

        _ = c.SDL_RenderSetLogicalSize(renderer, 64, 32);

        const audio = try initSound();

        return Sdl{
            .screen = screen,
            .renderer = renderer,
            .audio = audio,
        };
    }

    fn initSound() SdlError!SdlAudio {
        if (m.Mix_OpenAudio(44100, m.MIX_DEFAULT_FORMAT, 2, 2048) < 0) {
            c.SDL_Log("Unable to open audio device: %s", c.SDL_GetError());
            return SdlError.OpenAudioFailed;
        }

        const beep = m.Mix_LoadWAV("res/beep.wav") orelse
            {
            c.SDL_Log("Failed to load beep sound effect: %s", m.Mix_GetError());
            return SdlError.LoadWavFailed;
        };

        return SdlAudio{
            .beep = beep,
        };
    }

    pub fn playBeep(self: *Sdl) void {
        if (self.audio) |audio| {
            _ = m.Mix_PlayChannel(-1, audio.beep, 0);
        }
    }

    pub fn updateScreen(self: *Sdl, screen: *[32][64]u8) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 0xFF);
        _ = c.SDL_RenderClear(self.renderer);
        _ = c.SDL_SetRenderDrawColor(self.renderer, 0xFF, 0xFF, 0xFF, 0xFF);

        for (screen) |line, y| {
            for (line) |pixel, x| {
                if (pixel == 1) {
                    _ = c.SDL_RenderDrawPoint(self.renderer, @intCast(c_int, x), @intCast(c_int, y));
                }
            }
        }

        c.SDL_RenderPresent(self.renderer);
    }

    fn getKeyFromScancode(self: *Sdl, scancode: u32) ?u32 {
        _ = self;
        var key: u32 = undefined;
        switch (scancode) {
            0x1e => key = 0x1,
            0x1f => key = 0x2,
            0x20 => key = 0x3,
            0x21 => key = 0xc,
            0x14 => key = 0x4,
            0x1a => key = 0x5,
            0x08 => key = 0x6,
            0x15 => key = 0xd,
            0x04 => key = 0x7,
            0x16 => key = 0x8,
            0x07 => key = 0x9,
            0x09 => key = 0xe,
            0x1d => key = 0xa,
            0x1b => key = 0x0,
            0x06 => key = 0xb,
            0x19 => key = 0xf,
            else => return null,
        }
        return key;
    }

    pub fn getEvent(self: *Sdl) Event {
        _ = self;
        var event: c.SDL_Event = undefined;
        if (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => return Event.quitEvent(),
                c.SDL_KEYDOWN, c.SDL_KEYUP => {
                    const key: c.SDL_KeyboardEvent = event.key;
                    var keynum: u32 = self.getKeyFromScancode(key.keysym.scancode) orelse {
                        return Event.noneEvent();
                    };
                    return Event.keyEvent(event.@"type", keynum);
                },
                else => {},
            }
        }

        return Event.noneEvent();
    }
};
