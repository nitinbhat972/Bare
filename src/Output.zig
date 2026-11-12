const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Server = @import("Server.zig");
const utils = @import("utils.zig");
const gpa = utils.gpa;

const Output = @This();

sever: *Server,
wlr_output: *wlr.Output,

on_destroy: wl.Listener(*wlr.Output) = .init(deinit),
on_frame: wl.Listener(*wlr.Output) = .init(onFrame),

pub fn init(server: *Server, wlr_output: *wlr.Output) !void {
    const output = try gpa.create(Output);
    errdefer gpa.destroy(output);

    output.* = .{
        .sever = server,
        .wlr_output = wlr_output,
    };

    wlr_output.events.frame.add(&output.on_frame);
    wlr_output.events.destroy.add(&output.on_destroy);

    const output_layout = try server.output_layout.addAuto(wlr_output);

    const scene_output = try server.scene.createSceneOutput(wlr_output);
    server.scene_output_layout.addOutput(output_layout, scene_output);
}

fn deinit(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
    const output: *Output = @fieldParentPtr("on_destroy", listener);

    output.on_frame.link.remove();
    output.on_destroy.link.remove();

    gpa.destroy(output);

    std.log.info("Bye output", .{});
}

fn onFrame(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
    const output: *Output = @fieldParentPtr("on_frame", listener);

    const scene_output = output.sever.scene.getSceneOutput(output.wlr_output).?;
    _ = scene_output.commit(null);

    var now = utils.timestamp();
    scene_output.sendFrameDone(&now);
}
