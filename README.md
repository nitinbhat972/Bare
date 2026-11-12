# Bare
Bare is a minimal wayland compositor written in [`Zig`](https://ziglang.org/) with no distractions.

> [!NOTE]
> This is my learning project but I'm developing to daily driving it myself.

# Planned Things
- No animations
- No blur
- No borders
- No shadow
- No runtime config [^config]
- No bar (Idk maybe or maybe not)
- One layout (scrolling)
- Maybe server side wallpaper support

[^config]: Configuration is done by editing the Zig file directly, mainly rules and keybindings. It is planned to be compiled into a dynamic shared object. Major changes, such as adding a new layout, require rebuilding the compositor. 

### Protocols
- Layer shell (Only for wallpaper but can remove if I managed to add server side wallpaper)
- Clipboard
- Screen capture

# Current Status
Bare is highly based on [`tinywl`](https://codeberg.org/ifreund/zig-wlroots/src/branch/master/tinywl/tinywl.zig).

It for now only handles the `ESCAPE` for exiting the compositor. And also supports `Focusing` using hover, `Resizing`, and `Moving`.

# Testing
A small red rectangle is included as a rendering smoke test.

For further testing, Weston provides useful test clients [^weston]:
```sh
WAYLAND_DISPLAY=wayland-1 weston-terminal
WAYLAND_DISPLAY=wayland-1 weston-resizor
```
> [!NOTE]
> If running inside another compositor WAYLAND_DISPLAY mostly likely be *wayland-1* for Bare else *wayland-0* though naming its not garunteed

[^weston]: You need to install weston for using weston's testing utils
