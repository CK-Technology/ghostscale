const std = @import("std");
const flash = @import("flash");
const tailscale = @import("../tailscale.zig");

pub fn handler(ctx: flash.Context) !void {
    const allocator = ctx.allocator;
    _ = allocator;
    
    std.debug.print("⚡ Register command called!\n", .{});
    std.debug.print("This is a placeholder for the register functionality\n", .{});
}

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var app = flash.App.init(allocator, .{
        .name = "ghostscale register",
        .description = "Register ghost services with Tailscale",
        .version = "0.1.1",
    });
    defer app.deinit();

    var join_cmd = flash.Command.init("join", "Join this service to Tailscale network");
    try join_cmd.add_option("auth-key", "Tailscale auth key for joining");
    try join_cmd.add_option("service", "Service type (ghostdns, ghostgate, ghostscale)");
    try join_cmd.add_option("hostname", "Custom hostname (optional)");
    try join_cmd.add_option("port", "API port for the service (default: auto)");
    try app.add_command(join_cmd);

    var discover_cmd = flash.Command.init("discover", "Discover ghost services on the network");
    try discover_cmd.add_option("type", "Filter by service type (optional)");
    try app.add_command(discover_cmd);

    const status_cmd = flash.Command.init("status", "Show ghost service registration status");
    try app.add_command(status_cmd);

    const matches = app.parse(args) catch |err| switch (err) {
        error.InvalidArgument => {
            try app.print_help();
            return;
        },
        else => return err,
    };

    if (matches.subcommand) |subcmd| {
        if (std.mem.eql(u8, subcmd.name, "join")) {
            const auth_key = subcmd.get_option("auth-key") orelse {
                std.debug.print("Error: --auth-key parameter is required\n");
                return;
            };
            const service_str = subcmd.get_option("service") orelse {
                std.debug.print("Error: --service parameter is required\n");
                return;
            };
            const service_type = parseServiceType(service_str) orelse {
                std.debug.print("Error: Unknown service type: {s}\n", .{service_str});
                std.debug.print("Valid types: ghostdns, ghostgate, ghostscale\n");
                return;
            };
            const hostname = subcmd.get_option("hostname");
            const port_str = subcmd.get_option("port");
            const port: u16 = if (port_str) |p| try std.fmt.parseInt(u16, p, 10) else getDefaultPort(service_type);
            
            return try joinTailscaleNetwork(allocator, auth_key, service_type, hostname, port);
        } else if (std.mem.eql(u8, subcmd.name, "discover")) {
            const filter_type = subcmd.get_option("type");
            return try discoverGhostServices(allocator, filter_type);
        } else if (std.mem.eql(u8, subcmd.name, "status")) {
            return try showRegistrationStatus(allocator);
        }
    }

    try app.print_help();
}

fn parseServiceType(service_str: []const u8) ?tailscale.GhostServiceType {
    if (std.mem.eql(u8, service_str, "ghostdns")) return .ghostdns;
    if (std.mem.eql(u8, service_str, "ghostgate")) return .ghostgate;
    if (std.mem.eql(u8, service_str, "ghostscale")) return .ghostscale;
    return null;
}

fn getDefaultPort(service_type: tailscale.GhostServiceType) u16 {
    return switch (service_type) {
        .ghostdns => 8080,
        .ghostgate => 8081,
        .ghostscale => 8082,
        .unknown => 8080,
    };
}

fn joinTailscaleNetwork(allocator: std.mem.Allocator, auth_key: []const u8, service_type: tailscale.GhostServiceType, hostname: ?[]const u8, port: u16) !void {
    std.debug.print("Joining Tailscale network as {s} service...\n", .{@tagName(service_type)});
    
    var ts_client = tailscale.TailscaleClient.init(allocator);
    
    // Join the tailnet with auth key
    try ts_client.joinTailnet(auth_key, hostname);
    std.debug.print("✓ Successfully joined Tailscale network\n");
    
    // Register the ghost service
    try ts_client.registerGhostService(service_type, port);
    std.debug.print("✓ Service registered with hostname and funnel enabled\n");
    
    // Show final status
    const status = ts_client.getStatus() catch |err| {
        std.debug.print("Warning: Could not get status after registration: {}\n", .{err});
        return;
    };
    
    std.debug.print("\n=== Registration Complete ===\n");
    std.debug.print("Service: {s}\n", .{@tagName(service_type)});
    std.debug.print("Hostname: {s}\n", .{status.self.hostname});
    std.debug.print("Tailscale IP: {s}\n", .{status.self.addresses[0]});
    std.debug.print("API Port: {}\n", .{port});
    std.debug.print("MagicDNS: {s}.{s}\n", .{ status.self.hostname, status.magicDNSSuffix });
}

fn discoverGhostServices(allocator: std.mem.Allocator, filter_type: ?[]const u8) !void {
    std.debug.print("Discovering ghost services on Tailscale network...\n\n");
    
    var ts_client = tailscale.TailscaleClient.init(allocator);
    const ghost_services = ts_client.findGhostServices() catch |err| {
        std.debug.print("Error: Failed to discover services: {}\n", .{err});
        return;
    };
    defer allocator.free(ghost_services);
    
    const filter_service_type = if (filter_type) |ft| parseServiceType(ft) else null;
    
    std.debug.print("Found {} ghost services:\n", .{ghost_services.len});
    std.debug.print("{s:<15} {s:<12} {s:<20} {s:<15} {s:<8} {s}\n", .{ "SERVICE", "TYPE", "HOSTNAME", "TAILSCALE_IP", "PORT", "STATUS" });
    std.debug.print("{s}\n", .{"=" ** 80});
    
    for (ghost_services) |service| {
        if (filter_service_type == null or service.service_type == filter_service_type.?) {
            const status_str = if (service.online) "ONLINE" else "OFFLINE";
            std.debug.print("{s:<15} {s:<12} {s:<20} {s:<15} {d:<8} {s}\n", .{
                service.name,
                @tagName(service.service_type),
                service.hostname,
                service.tailscale_ip,
                service.api_port,
                status_str,
            });
        }
    }
}

fn showRegistrationStatus(allocator: std.mem.Allocator) !void {
    std.debug.print("=== Ghost Service Registration Status ===\n\n");
    
    var ts_client = tailscale.TailscaleClient.init(allocator);
    const status = ts_client.getStatus() catch |err| {
        std.debug.print("Error: Failed to get Tailscale status: {}\n", .{err});
        return;
    };
    
    // Check if this node is a ghost service
    const self_service_type = tailscale.GhostServiceType.fromHostname(status.self.hostname);
    
    std.debug.print("This Node:\n");
    std.debug.print("  Hostname: {s}\n", .{status.self.hostname});
    std.debug.print("  Service Type: {s}\n", .{@tagName(self_service_type)});
    std.debug.print("  Tailscale IP: {s}\n", .{status.self.addresses[0]});
    std.debug.print("  MagicDNS: {s}.{s}\n", .{ status.self.hostname, status.magicDNSSuffix });
    
    if (status.self.tags.len > 0) {
        std.debug.print("  Tags: ");
        for (status.self.tags, 0..) |tag, i| {
            if (i > 0) std.debug.print(", ");
            std.debug.print("{s}", .{tag});
        }
        std.debug.print("\n");
    }
    
    // Discover other ghost services
    std.debug.print("\nOther Ghost Services:\n");
    const ghost_services = ts_client.findGhostServices() catch |err| {
        std.debug.print("  Error discovering services: {}\n", .{err});
        return;
    };
    defer allocator.free(ghost_services);
    
    if (ghost_services.len == 0) {
        std.debug.print("  No other ghost services found on the network\n");
    } else {
        for (ghost_services) |service| {
            const status_str = if (service.online) "ONLINE" else "OFFLINE";
            std.debug.print("  • {s} ({s}) - {s}:{} [{s}]\n", .{
                service.hostname,
                @tagName(service.service_type),
                service.tailscale_ip,
                service.api_port,
                status_str,
            });
        }
    }
}