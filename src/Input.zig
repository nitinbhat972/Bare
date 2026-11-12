const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Cursor = @import("Cursor.zig");
const Keyboard = @import("Keyboard.zig");
const Server = @import("Server.zig");
const Toplevel = @import("Toplevel.zig");

const Input = @This();

server: *Server,
seat: *wlr.Seat,
cursor: Cursor = undefined,
keyboards: wl.list.Head(Keyboard, .link) = undefined,

on_new_device: wl.Listener(*wlr.InputDevice) = .init(onNewDevice),

pub fn init(self: *Input, server: *Server) !void {
    self.* = .{
        .server = server,
        .seat = try wlr.Seat.create(server.wl_server, "default"),
    };

    self.keyboards.init();
    try self.cursor.init(self);
    server.backend.events.new_input.add(&self.on_new_device);
}

pub fn deinit(self: *Input) void {
    self.on_new_device.link.remove();
    self.cursor.deinit();
}

fn onNewDevice(listener: *wl.Listener(*wlr.InputDevice), device: *wlr.InputDevice) void {
    const input: *Input = @fieldParentPtr("on_new_device", listener);

    switch (device.type) {
        .pointer => {
            std.log.info("Pointer Input Added: {s}", .{device.name.?});
            input.cursor.wlr_cursor.attachInputDevice(device);
        },
        .keyboard => {
            Keyboard.init(input, device) catch |err| {
                std.log.err("Failed to create a new keyboard: {}", .{err});
            };
            std.log.info("Keyboard Input Added: {s}", .{device.name.?});
        },
        else => {},
    }

    input.seat.setCapabilities(.{
        .pointer = true,
        .keyboard = input.keyboards.length() > 0,
    });
}

pub fn focusAt(self: *Input, view: Server.ViewAtResult) void {
    self.focusView(view.toplevel, view.surface);
}

pub fn focusView(self: *Input, toplevel: *Toplevel, surface: *wlr.Surface) void {
    if (self.seat.keyboard_state.focused_surface) |previous_surface| {
        if (previous_surface == surface) return;

        if (wlr.XdgSurface.tryFromWlrSurface(previous_surface)) |xdg_surface| {
            _ = xdg_surface.role_data.toplevel.?.setActivated(false);
        }
    }

    toplevel.scene_tree.node.raiseToTop();
    toplevel.link.remove();
    self.server.toplevels.prepend(toplevel);

    _ = toplevel.xdg_toplevel.setActivated(true);

    const keyboard = self.seat.getKeyboard() orelse return;
    self.seat.keyboardNotifyEnter(
        surface,
        keyboard.keycodes[0..keyboard.num_keycodes],
        &keyboard.modifiers,
    );
}

pub fn clearFocus(self: *Input) void {
    if (self.seat.keyboard_state.focused_surface) |surface| {
        if (wlr.XdgSurface.tryFromWlrSurface(surface)) |xdg_surface| {
            _ = xdg_surface.role_data.toplevel.?.setActivated(false);
        }
    }

    self.seat.keyboardNotifyClearFocus();
}
