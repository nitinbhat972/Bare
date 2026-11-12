const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Server = @import("Server.zig");
const Cursor = @import("Cursor.zig");
const utils = @import("utils.zig");
const gpa = utils.gpa;

const Toplevel = @This();

x: i32 = 0,
y: i32 = 0,

server: *Server,
xdg_toplevel: *wlr.XdgToplevel,
scene_tree: *wlr.SceneTree,

link: wl.list.Link = undefined,
on_commit: wl.Listener(*wlr.Surface) = .init(onXdgToplevelCommit),
on_destroy: wl.Listener(void) = .init(deinit),
on_map: wl.Listener(void) = .init(onMap),
on_unmap: wl.Listener(void) = .init(onUnmap),
on_request_move: wl.Listener(*wlr.XdgToplevel.event.Move) = .init(onRequestMove),
on_request_resize: wl.Listener(*wlr.XdgToplevel.event.Resize) = .init(onRequestResize),

pub fn init(server: *Server, xdg_toplevel: *wlr.XdgToplevel) !void {
    const toplevel = try gpa.create(Toplevel);
    errdefer gpa.destroy(toplevel);

    const xdg_surface = xdg_toplevel.base;

    toplevel.* = .{
        .server = server,
        .xdg_toplevel = xdg_toplevel,
        .scene_tree = try server.scene.tree.createSceneXdgSurface(xdg_surface),
    };

    toplevel.scene_tree.node.data = toplevel;
    xdg_surface.data = toplevel.scene_tree;

    xdg_surface.surface.events.commit.add(&toplevel.on_commit);
    xdg_surface.surface.events.map.add(&toplevel.on_map);
    xdg_surface.surface.events.unmap.add(&toplevel.on_unmap);
    xdg_toplevel.events.destroy.add(&toplevel.on_destroy);
    xdg_toplevel.events.request_move.add(&toplevel.on_request_move);
    xdg_toplevel.events.request_resize.add(&toplevel.on_request_resize);
}

fn deinit(listener: *wl.Listener(void)) void {
    const toplevel: *Toplevel = @fieldParentPtr("on_destroy", listener);

    toplevel.on_commit.link.remove();
    toplevel.on_destroy.link.remove();
    toplevel.on_map.link.remove();
    toplevel.on_unmap.link.remove();
    toplevel.on_request_move.link.remove();
    toplevel.on_request_resize.link.remove();

    gpa.destroy(toplevel);

    std.log.info("Bye toplevel", .{});
}

fn onXdgToplevelCommit(listener: *wl.Listener(*wlr.Surface), wlr_surface: *wlr.Surface) void {
    _ = wlr_surface;
    const toplevel: *Toplevel = @fieldParentPtr("on_commit", listener);

    if (toplevel.xdg_toplevel.base.initial_commit) {
        _ = toplevel.xdg_toplevel.setSize(0, 0);
    }
}

fn onMap(listener: *wl.Listener(void)) void {
    const toplevel: *Toplevel = @fieldParentPtr("on_map", listener);

    toplevel.server.toplevels.prepend(toplevel);
    toplevel.server.input.focusView(
        toplevel,
        toplevel.xdg_toplevel.base.surface,
    );
}

fn onUnmap(listener: *wl.Listener(void)) void {
    const toplevel: *Toplevel = @fieldParentPtr("on_unmap", listener);
    toplevel.link.remove();
}

fn onRequestMove(listener: *wl.Listener(*wlr.XdgToplevel.event.Move), _: *wlr.XdgToplevel.event.Move) void {
    const toplevel: *Toplevel = @fieldParentPtr("on_request_move", listener);
    const cursor = &toplevel.server.input.cursor;

    cursor.cursor_mode = .{
        .move = .{
            .view = toplevel,
            .x = cursor.wlr_cursor.x - @as(f64, @floatFromInt(toplevel.x)),
            .y = cursor.wlr_cursor.y - @as(f64, @floatFromInt(toplevel.y)),
        },
    };
}

fn onRequestResize(listener: *wl.Listener(*wlr.XdgToplevel.event.Resize), event: *wlr.XdgToplevel.event.Resize) void {
    const toplevel: *Toplevel = @fieldParentPtr("on_request_resize", listener);
    const cursor = &toplevel.server.input.cursor;
    var box = toplevel.xdg_toplevel.base.geometry;

    const border_x = toplevel.x + box.x + if (event.edges.right) box.width else 0;
    const border_y = toplevel.y + box.y + if (event.edges.bottom) box.height else 0;

    box.x += toplevel.x;
    box.y += toplevel.y;

    cursor.cursor_mode = .{
        .resize = .{
            .box = box,
            .grab = .{
                .view = toplevel,
                .x = cursor.wlr_cursor.x - @as(f64, @floatFromInt(border_x)),
                .y = cursor.wlr_cursor.y - @as(f64, @floatFromInt(border_y)),
            },
            .edges = event.edges,
        },
    };
}
