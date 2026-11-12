const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Input = @import("Input.zig");
const Toplevel = @import("Toplevel.zig");

const Cursor = @This();

const Grab = struct {
    view: *Toplevel,
    x: f64,
    y: f64,
};

input: *Input,
wlr_cursor: *wlr.Cursor,
xcursor_manager: *wlr.XcursorManager,

on_cursor_motion: wl.Listener(*wlr.Pointer.event.Motion) = .init(onCursorMotion),
on_cursor_motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) = .init(onCursorMotionAbsolute),
on_cursor_button: wl.Listener(*wlr.Pointer.event.Button) = .init(onCursorButton),
on_cursor_frame: wl.Listener(*wlr.Cursor) = .init(onCursorFrame),

cursor_mode: union(enum) {
    passthrough,
    move: Grab,
    resize: struct {
        grab: Grab,
        edges: wlr.Edges,
        box: wlr.Box,
    },
} = .passthrough,

pub fn init(self: *Cursor, input: *Input) !void {
    const cursor = try wlr.Cursor.create();
    errdefer cursor.destroy();

    const xcursor_manager = try wlr.XcursorManager.create(null, 24);
    errdefer xcursor_manager.destroy();

    self.* = .{
        .input = input,
        .wlr_cursor = cursor,
        .xcursor_manager = xcursor_manager,
    };

    cursor.attachOutputLayout(input.server.output_layout);
    try xcursor_manager.load(1.0);
    cursor.setXcursor(xcursor_manager, "default");

    cursor.events.motion.add(&self.on_cursor_motion);
    cursor.events.motion_absolute.add(&self.on_cursor_motion_absolute);
    cursor.events.button.add(&self.on_cursor_button);
    cursor.events.frame.add(&self.on_cursor_frame);
}

pub fn deinit(self: *Cursor) void {
    self.on_cursor_motion.link.remove();
    self.on_cursor_motion_absolute.link.remove();
    self.on_cursor_button.link.remove();
    self.on_cursor_frame.link.remove();

    self.xcursor_manager.destroy();
    self.wlr_cursor.destroy();
}

fn processCursorMotion(self: *Cursor, time_msec: u32) void {
    switch (self.cursor_mode) {
        .passthrough => {
            if (self.input.server.viewAt(self.wlr_cursor.x, self.wlr_cursor.y)) |view| {
                self.input.seat.pointerNotifyEnter(view.surface, view.sx, view.sy);
                self.input.seat.pointerNotifyMotion(time_msec, view.sx, view.sy);
                self.input.focusAt(view);
            } else {
                self.clearFocus();
                self.input.clearFocus();
            }
        },
        .move => |move| {
            const toplevel = move.view;
            toplevel.x = @as(i32, @intFromFloat(self.wlr_cursor.x - move.x));
            toplevel.y = @as(i32, @intFromFloat(self.wlr_cursor.y - move.y));
            toplevel.scene_tree.node.setPosition(toplevel.x, toplevel.y);
        },
        .resize => |resize| {
            const toplevel = resize.grab.view;
            const geometry = toplevel.xdg_toplevel.base.geometry;

            const edge_x = @as(i32, @intFromFloat(
                self.wlr_cursor.x - resize.grab.x,
            ));
            const edge_y = @as(i32, @intFromFloat(
                self.wlr_cursor.y - resize.grab.y,
            ));

            var box = resize.box;
            const right = box.x + box.width;
            const bottom = box.y + box.height;

            if (resize.edges.top) {
                box.y = if (edge_y < bottom) edge_y else bottom - 1;
                box.height = bottom - box.y;
            } else if (resize.edges.bottom) {
                box.height = if (edge_y > box.y) edge_y - box.y else 1;
            }

            if (resize.edges.left) {
                box.x = if (edge_x < right) edge_x else right - 1;
                box.width = right - box.x;
            } else if (resize.edges.right) {
                box.width = if (edge_x > box.x) edge_x - box.x else 1;
            }

            toplevel.x = box.x - geometry.x;
            toplevel.y = box.y - geometry.y;
            toplevel.scene_tree.node.setPosition(toplevel.x, toplevel.y);

            _ = toplevel.xdg_toplevel.setSize(box.width, box.height);
        },
    }
}

fn onCursorMotion(
    listener: *wl.Listener(*wlr.Pointer.event.Motion),
    event: *wlr.Pointer.event.Motion,
) void {
    const cursor: *Cursor = @fieldParentPtr("on_cursor_motion", listener);
    cursor.wlr_cursor.move(event.device, event.delta_x, event.delta_y);
    cursor.processCursorMotion(event.time_msec);
}

fn onCursorMotionAbsolute(
    listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
    event: *wlr.Pointer.event.MotionAbsolute,
) void {
    const cursor: *Cursor = @fieldParentPtr("on_cursor_motion_absolute", listener);
    cursor.wlr_cursor.warpAbsolute(event.device, event.x, event.y);
    cursor.processCursorMotion(event.time_msec);
}

fn onCursorButton(
    listener: *wl.Listener(*wlr.Pointer.event.Button),
    event: *wlr.Pointer.event.Button,
) void {
    const cursor: *Cursor = @fieldParentPtr("on_cursor_button", listener);

    _ = cursor.input.seat.pointerNotifyButton(
        event.time_msec,
        event.button,
        event.state,
    );

    if (event.state == .released) cursor.cursor_mode = .passthrough;
}

fn onCursorFrame(listener: *wl.Listener(*wlr.Cursor), _: *wlr.Cursor) void {
    const cursor: *Cursor = @fieldParentPtr("on_cursor_frame", listener);
    cursor.input.seat.pointerNotifyFrame();
}

fn clearFocus(self: *Cursor) void {
    self.wlr_cursor.setXcursor(self.xcursor_manager, "default");
    self.input.seat.pointerNotifyClearFocus();
}
