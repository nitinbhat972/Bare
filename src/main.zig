const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Server = @import("Server.zig");

pub fn main() !void {
    // wlr.log.init(.debug, null);
    var server: Server = undefined;

    try server.init();
    defer server.deinit();

    var buf: [11]u8 = undefined;
    const socket = try server.wl_server.addSocketAuto(&buf);

    try server.backend.start();

    // smoke test
    const color: [4]f32 = .{ 1.0, 0.0, 0.0, 1.0 };
    const wrl_scene_rect = try server.scene.tree.createSceneRect(100, 100, &color);
    wrl_scene_rect.node.setPosition(0, 0);

    std.log.info("Running compositor at WAYLAND_DISPLAY={s}", .{socket});
    server.wl_server.run();
}
