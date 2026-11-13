const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Input = @import("Input.zig");
const Output = @import("Output.zig");
const Toplevel = @import("Toplevel.zig");
const utils = @import("utils.zig");
const gpa = utils.gpa;

const Server = @This();

wl_server: *wl.Server,
backend: *wlr.Backend,
renderer: *wlr.Renderer,
allocator: *wlr.Allocator,
scene: *wlr.Scene,

output_layout: *wlr.OutputLayout,
scene_output_layout: *wlr.SceneOutputLayout,

on_output_add: wl.Listener(*wlr.Output) = .init(onOutputAdd),

xdg_shell: *wlr.XdgShell,
toplevels: wl.list.Head(Toplevel, .link) = undefined,
on_toplevel_add: wl.Listener(*wlr.XdgToplevel) = .init(onToplevelAdd),

input: Input = undefined,

pub fn init(self: *Server) !void {
    const server = try wl.Server.create();
    const loop = server.getEventLoop();
    const backend = try wlr.Backend.autocreate(loop, null);
    const renderer = try wlr.Renderer.autocreate(backend);
    const output_layout = try wlr.OutputLayout.create(server);
    const scene = try wlr.Scene.create();

    self.* = .{
        .wl_server = server,
        .backend = backend,
        .renderer = renderer,
        .allocator = try wlr.Allocator.autocreate(backend, renderer),
        .scene = scene,

        .output_layout = output_layout,
        .scene_output_layout = try scene.attachOutputLayout(output_layout),

        .xdg_shell = try wlr.XdgShell.create(server, 6),
    };

    try self.renderer.initServer(server);
    _ = try wlr.Compositor.create(server, 6, renderer);
    _ = try wlr.Subcompositor.create(self.wl_server);
    _ = try wlr.DataDeviceManager.create(self.wl_server);

    self.backend.events.new_output.add(&self.on_output_add);
    self.toplevels.init();
    self.xdg_shell.events.new_toplevel.add(&self.on_toplevel_add);
    try self.input.init(self);
}

pub fn deinit(self: *Server) void {
    self.wl_server.destroyClients();

    self.on_output_add.link.remove();
    self.on_toplevel_add.link.remove();
    self.input.deinit();

    // you don't need cleanup for rest of the object their lifetime
    // will be handeled by the wlroots using wlr_addon (atleast that's what I learned)
    self.backend.destroy();
    self.scene.tree.node.destroy();
    self.renderer.destroy();
    self.allocator.destroy();
    self.wl_server.destroy();
}

fn onOutputAdd(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    const server: *Server = @fieldParentPtr("on_output_add", listener);

    if (!wlr.Output.initRender(wlr_output, server.allocator, server.renderer)) return;

    var state = wlr.Output.State.init();
    defer state.finish();
    state.setEnabled(true);

    if (wlr_output.preferredMode()) |mode| {
        state.setMode(mode);
    }

    if (!wlr_output.commitState(&state)) return;

    Output.init(server, wlr_output) catch {
        std.log.err("failed to allocate new output", .{});
        wlr_output.destroy();
        return;
    };

    std.log.info("New output", .{});
}

fn onToplevelAdd(listener: *wl.Listener(*wlr.XdgToplevel), xdg_toplevel: *wlr.XdgToplevel) void {
    const server: *Server = @fieldParentPtr("on_toplevel_add", listener);

    Toplevel.init(server, xdg_toplevel) catch {
        std.log.err("failed to allocate new toplevel", .{});
        xdg_toplevel.sendClose();
        return;
    };

    std.log.info("New Toplevel", .{});
}

pub const ViewAtResult = struct {
    toplevel: *Toplevel,
    surface: *wlr.Surface,
    sx: f64,
    sy: f64,
};

pub fn viewAt(self: *Server, lx: f64, ly: f64) ?ViewAtResult {
    var sx: f64 = undefined;
    var sy: f64 = undefined;

    const node = self.scene.tree.node.at(lx, ly, &sx, &sy) orelse return null;
    if (node.type != .buffer) return null;

    const scene_buffer = wlr.SceneBuffer.fromNode(node);
    const scene_surface = wlr.SceneSurface.tryFromBuffer(scene_buffer) orelse return null;

    var tree: ?*wlr.SceneTree = node.parent;
    while (tree) |current| : (tree = current.node.parent) {
        if (@as(?*Toplevel, @ptrCast(@alignCast(current.node.data)))) |toplevel| {
            return .{
                .toplevel = toplevel,
                .surface = scene_surface.surface,
                .sx = sx,
                .sy = sy,
            };
        }
    }

    return null;
}
