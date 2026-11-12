const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const Input = @import("Input.zig");
const utils = @import("utils.zig");
const gpa = utils.gpa;

const Keyboard = @This();

input: *Input,
link: wl.list.Link = undefined,
device: *wlr.InputDevice,

on_destroy: wl.Listener(*wlr.InputDevice) = .init(deinit),
on_modifier: wl.Listener(*wlr.Keyboard) = .init(onModifier),
on_key: wl.Listener(*wlr.Keyboard.event.Key) = .init(onKey),

pub fn init(input: *Input, device: *wlr.InputDevice) !void {
    const keyboard = try gpa.create(Keyboard);
    errdefer gpa.destroy(keyboard);

    keyboard.* = .{
        .input = input,
        .device = device,
    };

    const xkb_context = xkb.Context.new(.no_flags) orelse return error.XkbContextFailed;
    defer xkb_context.unref();

    const keymap = xkb.Keymap.newFromNames(xkb_context, null, .no_flags) orelse return error.KeymapFailed;
    defer keymap.unref();

    const wlr_keyboard = device.toKeyboard();
    if (!wlr_keyboard.setKeymap(keymap)) return error.SetKeymapFailed;
    wlr_keyboard.setRepeatInfo(25, 600);

    device.events.destroy.add(&keyboard.on_destroy);
    wlr_keyboard.events.modifiers.add(&keyboard.on_modifier);
    wlr_keyboard.events.key.add(&keyboard.on_key);

    input.seat.setKeyboard(wlr_keyboard);
    input.keyboards.append(keyboard);
}

pub fn deinit(listener: *wl.Listener(*wlr.InputDevice), _: *wlr.InputDevice) void {
    const keyboard: *Keyboard = @fieldParentPtr("on_destroy", listener);

    keyboard.link.remove();

    keyboard.input.seat.setCapabilities(.{
        .pointer = true,
        .keyboard = keyboard.input.keyboards.length() > 0,
    });

    keyboard.on_destroy.link.remove();
    keyboard.on_modifier.link.remove();
    keyboard.on_key.link.remove();

    gpa.destroy(keyboard);
}

fn onModifier(listener: *wl.Listener(*wlr.Keyboard), wlr_keyboard: *wlr.Keyboard) void {
    const keyboard: *Keyboard = @fieldParentPtr("on_modifier", listener);

    keyboard.input.seat.setKeyboard(wlr_keyboard);
    keyboard.input.seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
}

fn onKey(listener: *wl.Listener(*wlr.Keyboard.event.Key), event: *wlr.Keyboard.event.Key) void {
    const keyboard: *Keyboard = @fieldParentPtr("on_key", listener);
    const wlr_keyboard = keyboard.device.toKeyboard();

    const keycode = event.keycode + 8;

    var handled = false;
    if (event.state == .pressed) {
        for (wlr_keyboard.xkb_state.?.keyGetSyms(keycode)) |sym| {
            if (keyboard.handleKeybinds(sym)) {
                handled = true;
                break;
            }
        }
    }

    if (!handled) {
        keyboard.input.seat.setKeyboard(wlr_keyboard);
        keyboard.input.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    }
}

fn handleKeybinds(self: *Keyboard, key: xkb.Keysym) bool {
    switch (key) {
        .Escape => self.input.server.wl_server.terminate(),
        else => return false,
    }
    return true;
}
