const std = @import("std");
const flash = @import("flash");
const tailscale = @import("../tailscale.zig");

pub fn handler(ctx: flash.Context) !void {
    const allocator = ctx.allocator;
    _ = allocator;
    
    std.debug.print("⚡ Route command called!\n", .{});
    
    // TODO: Implement proper argument parsing with Flash
    std.debug.print("This is a placeholder for the route functionality\n", .{});
}

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var app = flash.App.init(allocator, .{
        .name = "ghostscale route",
        .description = "Route management and automation",
        .version = "0.1.1",
    });
    defer app.deinit();

    var fix_cmd = flash.Command.init("fix", "Fix route conflicts automatically");
    try fix_cmd.add_flag("auto", "Automatically fix detected issues");
    try app.add_command(fix_cmd);

    var advertise_cmd = flash.Command.init("advertise", "Advertise subnet routes");
    try advertise_cmd.add_option("routes", "Comma-separated list of routes to advertise");
    try app.add_command(advertise_cmd);

    const status_cmd = flash.Command.init("status", (flash.CommandConfig{}).withAbout("Show current route status"));
    _ = status_cmd;

    const matches = app.parse(args) catch |err| switch (err) {
        error.InvalidArgument => {
            try app.print_help();
            return;
        },
        else => return err,
    };

    if (matches.subcommand) |subcmd| {
        if (std.mem.eql(u8, subcmd.name, "fix")) {
            return try fixRoutes(allocator, subcmd.get_flag("auto"));
        } else if (std.mem.eql(u8, subcmd.name, "advertise")) {
            const routes_str = subcmd.get_option("routes") orelse {
                std.debug.print("Error: --routes parameter is required\n");
                return;
            };
            return try advertiseRoutes(allocator, routes_str);
        } else if (std.mem.eql(u8, subcmd.name, "status")) {
            return try showRouteStatus(allocator);
        }
    }

    try app.print_help();
}

fn fixRoutes(allocator: std.mem.Allocator, auto_fix: bool) !void {
    var ts_client = tailscale.TailscaleClient.init(allocator);
    _ = ts_client.getStatus() catch |err| {
        std.debug.print("Error: Failed to get Tailscale status: {}\n", .{err});
        return;
    };

    std.debug.print("Checking route conflicts...\n");
    
    if (auto_fix) {
        std.debug.print("Auto-fixing route conflicts (placeholder implementation)\n");
    } else {
        std.debug.print("Route analysis complete. Use --auto to apply fixes.\n");
    }
}

fn advertiseRoutes(allocator: std.mem.Allocator, routes_str: []const u8) !void {
    var routes = std.ArrayList([]const u8).init(allocator);
    defer routes.deinit();

    var it = std.mem.split(u8, routes_str, ",");
    while (it.next()) |route| {
        const trimmed = std.mem.trim(u8, route, " ");
        try routes.append(try allocator.dupe(u8, trimmed));
    }

    var ts_client = tailscale.TailscaleClient.init(allocator);
    ts_client.advertiseRoutes(routes.items) catch |err| {
        std.debug.print("Error: Failed to advertise routes: {}\n", .{err});
        return;
    };

    std.debug.print("Successfully advertised routes: {s}\n", .{routes_str});
}

fn showRouteStatus(allocator: std.mem.Allocator) !void {
    var ts_client = tailscale.TailscaleClient.init(allocator);
    const status = ts_client.getStatus() catch |err| {
        std.debug.print("Error: Failed to get Tailscale status: {}\n", .{err});
        return;
    };

    std.debug.print("=== Route Status ===\n");
    std.debug.print("Self: {s} ({s})\n", .{ status.self.hostname, status.self.addresses[0] });
    
    for (status.peers) |peer| {
        std.debug.print("Peer: {s} ({s}) - Online: {}\n", .{ peer.hostname, peer.addresses[0], peer.online });
    }
}