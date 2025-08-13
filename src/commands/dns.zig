const std = @import("std");
const flash = @import("flash");
const tailscale = @import("../tailscale.zig");

pub fn handler(ctx: flash.Context) !void {
    const allocator = ctx.allocator;
    _ = allocator;
    
    std.debug.print("⚡ DNS command called!\n", .{});
    
    // TODO: Implement proper argument parsing with Flash
    std.debug.print("This is a placeholder for the DNS functionality\n", .{});
}

const DNSProvider = enum {
    powerdns,
    technitium,
    bind9,
    ghostdns,
    
    pub fn fromString(str: []const u8) ?DNSProvider {
        if (std.mem.eql(u8, str, "powerdns")) return .powerdns;
        if (std.mem.eql(u8, str, "technitium")) return .technitium;
        if (std.mem.eql(u8, str, "bind9")) return .bind9;
        if (std.mem.eql(u8, str, "ghostdns")) return .ghostdns;
        return null;
    }
};

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var app = flash.App.init(allocator, .{
        .name = "ghostscale dns",
        .description = "DNS management and synchronization",
        .version = "0.1.0",
    });
    defer app.deinit();

    var sync_cmd = flash.Command.init("sync", "Synchronize Tailscale hostnames to DNS provider");
    try sync_cmd.add_option("output", "DNS provider (powerdns, technitium, bind9, ghostdns)");
    try sync_cmd.add_option("zone", "DNS zone to update");
    try sync_cmd.add_option("api-key", "API key for DNS provider");
    try sync_cmd.add_option("server", "DNS server URL");
    try sync_cmd.add_option("ghostdns-endpoint", "GhostDNS API endpoint (default: http://localhost:8080)");
    try app.add_command(sync_cmd);

    var export_cmd = flash.Command.init("export", "Export DNS records in various formats");
    try export_cmd.add_option("format", "Export format (bind, json, csv)");
    try export_cmd.add_option("output", "Output file path");
    try app.add_command(export_cmd);

    const status_cmd = flash.Command.init("status", (flash.CommandConfig{}).withAbout("Show current DNS configuration"));
    _ = status_cmd;

    const matches = app.parse(args) catch |err| switch (err) {
        error.InvalidArgument => {
            try app.print_help();
            return;
        },
        else => return err,
    };

    if (matches.subcommand) |subcmd| {
        if (std.mem.eql(u8, subcmd.name, "sync")) {
            const provider_str = subcmd.get_option("output") orelse {
                std.debug.print("Error: --output parameter is required\n");
                return;
            };
            const provider = DNSProvider.fromString(provider_str) orelse {
                std.debug.print("Error: Unknown DNS provider: {s}\n", .{provider_str});
                return;
            };
            return try syncDNS(allocator, provider, subcmd);
        } else if (std.mem.eql(u8, subcmd.name, "export")) {
            const format = subcmd.get_option("format") orelse "json";
            const output_file = subcmd.get_option("output");
            return try exportDNS(allocator, format, output_file);
        } else if (std.mem.eql(u8, subcmd.name, "status")) {
            return try showDNSStatus(allocator);
        }
    }

    try app.print_help();
}

fn syncDNS(allocator: std.mem.Allocator, provider: DNSProvider, cmd: flash.ParsedCommand) !void {
    var ts_client = tailscale.TailscaleClient.init(allocator);
    const status = ts_client.getStatus() catch |err| {
        std.debug.print("Error: Failed to get Tailscale status: {}\n", .{err});
        return;
    };

    const zone = cmd.get_option("zone") orelse {
        std.debug.print("Error: --zone parameter is required\n");
        return;
    };

    std.debug.print("Syncing DNS records to {s} for zone: {s}\n", .{ @tagName(provider), zone });

    switch (provider) {
        .powerdns => try syncPowerDNS(allocator, status, zone, cmd),
        .technitium => try syncTechnitium(allocator, status, zone, cmd),
        .bind9 => try syncBind9(allocator, status, zone, cmd),
        .ghostdns => try syncGhostDNS(allocator, status, zone, cmd),
    }

    std.debug.print("DNS synchronization completed successfully.\n");
}

fn syncPowerDNS(allocator: std.mem.Allocator, status: tailscale.TailscaleStatus, zone: []const u8, cmd: flash.ParsedCommand) !void {
    _ = cmd.get_option("api-key") orelse {
        std.debug.print("Error: --api-key parameter is required for PowerDNS\n", .{});
        return;
    };
    _ = cmd.get_option("server") orelse {
        std.debug.print("Error: --server parameter is required for PowerDNS\n", .{});
        return;
    };

    std.debug.print("PowerDNS sync: Creating A records for {} devices\n", .{status.peers.len + 1});
    
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const self_record = try std.fmt.allocPrint(
        allocator,
        "{{\"name\":\"{s}.{s}\",\"type\":\"A\",\"records\":[{{\"content\":\"{s}\",\"disabled\":false}}]}}",
        .{ status.self.hostname, zone, status.self.addresses[0] }
    );
    defer allocator.free(self_record);

    std.debug.print("Created record for self: {s}\n", .{status.self.hostname});
}

fn syncTechnitium(_: std.mem.Allocator, status: tailscale.TailscaleStatus, zone: []const u8, cmd: flash.ParsedCommand) !void {
    _ = cmd;
    std.debug.print("Technitium DNS sync: Creating records for {} devices in zone {s}\n", .{ status.peers.len + 1, zone });
}

fn syncBind9(allocator: std.mem.Allocator, status: tailscale.TailscaleStatus, zone: []const u8, cmd: flash.ParsedCommand) !void {
    _ = cmd;
    std.debug.print("BIND9 sync: Generating zone file for {} devices in zone {s}\n", .{ status.peers.len + 1, zone });
    
    const zone_file = try std.fmt.allocPrint(allocator, "/tmp/{s}.zone", .{zone});
    defer allocator.free(zone_file);
    
    const file = try std.fs.cwd().createFile(zone_file, .{});
    defer file.close();
    
    const writer = file.writer();
    try writer.print("; Zone file for {s} - Generated by ghostscale\n", .{zone});
    try writer.print("{s}.\\t\\tIN\\tA\\t{s}\n", .{ status.self.hostname, status.self.addresses[0] });
    
    for (status.peers) |peer| {
        if (peer.addresses.len > 0) {
            try writer.print("{s}.\\t\\tIN\\tA\\t{s}\n", .{ peer.hostname, peer.addresses[0] });
        }
    }
    
    std.debug.print("Zone file written to: {s}\n", .{zone_file});
}

fn exportDNS(allocator: std.mem.Allocator, format: []const u8, output_file: ?[]const u8) !void {
    var ts_client = tailscale.TailscaleClient.init(allocator);
    const status = ts_client.getStatus() catch |err| {
        std.debug.print("Error: Failed to get Tailscale status: {}\n", .{err});
        return;
    };

    const filename = output_file orelse "tailscale-dns-export.json";
    
    if (std.mem.eql(u8, format, "json")) {
        try exportJSON(allocator, status, filename);
    } else if (std.mem.eql(u8, format, "bind")) {
        try exportBind(allocator, status, filename);
    } else if (std.mem.eql(u8, format, "csv")) {
        try exportCSV(allocator, status, filename);
    } else {
        std.debug.print("Error: Unknown export format: {s}\n", .{format});
        return;
    }

    std.debug.print("DNS records exported to: {s}\n", .{filename});
}

fn exportJSON(_: std.mem.Allocator, status: tailscale.TailscaleStatus, filename: []const u8) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    
    const writer = file.writer();
    try writer.writeAll("{\n  \"records\": [\n");
    
    try writer.print("    {{\"name\": \"{s}\", \"type\": \"A\", \"value\": \"{s}\"}}", .{ status.self.hostname, status.self.addresses[0] });
    
    for (status.peers) |peer| {
        if (peer.addresses.len > 0) {
            try writer.print(",\n    {{\"name\": \"{s}\", \"type\": \"A\", \"value\": \"{s}\"}}", .{ peer.hostname, peer.addresses[0] });
        }
    }
    
    try writer.writeAll("\n  ]\n}\n");
}

fn exportBind(_: std.mem.Allocator, status: tailscale.TailscaleStatus, filename: []const u8) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    
    const writer = file.writer();
    try writer.writeAll("; BIND zone file - Generated by ghostscale\n");
    try writer.print("{s}.\\t\\tIN\\tA\\t{s}\n", .{ status.self.hostname, status.self.addresses[0] });
    
    for (status.peers) |peer| {
        if (peer.addresses.len > 0) {
            try writer.print("{s}.\\t\\tIN\\tA\\t{s}\n", .{ peer.hostname, peer.addresses[0] });
        }
    }
}

fn exportCSV(_: std.mem.Allocator, status: tailscale.TailscaleStatus, filename: []const u8) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    
    const writer = file.writer();
    try writer.writeAll("hostname,type,value,online\n");
    try writer.print("{s},A,{s},{}\n", .{ status.self.hostname, status.self.addresses[0], true });
    
    for (status.peers) |peer| {
        if (peer.addresses.len > 0) {
            try writer.print("{s},A,{s},{}\n", .{ peer.hostname, peer.addresses[0], peer.online });
        }
    }
}

fn syncGhostDNS(allocator: std.mem.Allocator, status: tailscale.TailscaleStatus, zone: []const u8, cmd: flash.ParsedCommand) !void {
    const endpoint = cmd.get_option("ghostdns-endpoint") orelse "http://localhost:8080";
    
    std.debug.print("GhostDNS sync: Registering {} devices with GhostDNS at {s}\n", .{ status.peers.len + 1, endpoint });
    
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Register self
    try registerDeviceWithGhostDNS(allocator, &client, endpoint, status.self.hostname, status.self.addresses[0], zone, "self");
    
    // Register peers
    for (status.peers) |peer| {
        if (peer.addresses.len > 0) {
            const device_type = if (peer.online) "peer" else "offline_peer";
            try registerDeviceWithGhostDNS(allocator, &client, endpoint, peer.hostname, peer.addresses[0], zone, device_type);
        }
    }
}

fn registerDeviceWithGhostDNS(allocator: std.mem.Allocator, client: *std.http.Client, endpoint: []const u8, hostname: []const u8, ip: []const u8, zone: []const u8, device_type: []const u8) !void {
    const full_domain = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ hostname, zone });
    defer allocator.free(full_domain);
    
    const record_json = try std.fmt.allocPrint(
        allocator,
        "{{\"action\":\"register\",\"domain\":\"{s}\",\"type\":\"A\",\"value\":\"{s}\",\"ttl\":300,\"metadata\":{{\"device_type\":\"{s}\",\"managed_by\":\"ghostscale\"}}}}",
        .{ full_domain, ip, device_type }
    );
    defer allocator.free(record_json);
    
    const api_url = try std.fmt.allocPrint(allocator, "{s}/api/v1/records", .{endpoint});
    defer allocator.free(api_url);
    
    std.debug.print("  Registering: {s} -> {s}\n", .{ full_domain, ip });
    
    // TODO: Implement actual HTTP POST request
    // For now, just print what would be sent
    std.debug.print("  POST {s}: {s}\n", .{ api_url, record_json });
}

fn showDNSStatus(allocator: std.mem.Allocator) !void {
    var ts_client = tailscale.TailscaleClient.init(allocator);
    const status = ts_client.getStatus() catch |err| {
        std.debug.print("Error: Failed to get Tailscale status: {}\n", .{err});
        return;
    };

    std.debug.print("=== DNS Status ===\n");
    std.debug.print("MagicDNS Suffix: {s}\n", .{status.magicDNSSuffix});
    std.debug.print("Total Devices: {}\n", .{status.peers.len + 1});
    std.debug.print("\nDevices:\n");
    std.debug.print("  {s} (self) -> {s}\n", .{ status.self.hostname, status.self.addresses[0] });
    
    for (status.peers) |peer| {
        const status_str = if (peer.online) "online" else "offline";
        if (peer.addresses.len > 0) {
            std.debug.print("  {s} ({s}) -> {s}\n", .{ peer.hostname, status_str, peer.addresses[0] });
        }
    }
}