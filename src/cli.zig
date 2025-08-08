const std = @import("std");
const flash = @import("flash");
const expose = @import("commands/expose.zig");
const dns = @import("commands/dns.zig");
const route = @import("commands/route.zig");

const GhostscaleCLI = flash.CLI(.{
    .name = "ghostscale",
    .version = "0.1.0",
    .about = "Secure, Programmable Overlay Networking Tool built on Tailscale",
});

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const subcommands = [_]flash.Command{
        flash.Command.init("expose", (flash.CommandConfig{})
            .withAbout("Expose a service through Tailscale reverse proxy")
            .withHandler(expose.handler)),
        flash.Command.init("dns", (flash.CommandConfig{})
            .withAbout("DNS management and synchronization")
            .withHandler(dns.handler)),
        flash.Command.init("route", (flash.CommandConfig{})
            .withAbout("Route management and automation")
            .withHandler(route.handler)),
    };

    var cli = GhostscaleCLI.init(allocator, (flash.CommandConfig{})
        .withSubcommands(&subcommands));
    
    try cli.runWithArgs(args);
}

