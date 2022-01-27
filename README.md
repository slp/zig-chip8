# zig-chip8

A [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8) emulator written in
[Zig](https://ziglang.org/).

## Status

This is intended as a learning exercise to get familiar with Zig. The
code is still a bit rough, but my intention is improving it
iteratively as I become more familiar with the language.

The emulator is already able to run properly most programs, demos and
games I've found.

## Building

### Requisites

- Zig version 0.10.0
- SDL2 and SDL_mixer development headers (SDL2-devel and
  SDL2_mixer-devel in Fedora)

### Building

```
zig build
```

## Running

```
./zig-out/bin/zig-chip8 ROM_FILE
```

## Acknowledgements

I'd like to thank [Tobias V. Langhoff](https://tobiasvl.github.io/)
for his excellent [Guide to making a CHIP-8
emulator](https://tobiasvl.github.io/blog/write-a-chip-8-emulator/) post.
