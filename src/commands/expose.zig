const std = @import("std");
const flash = @import("flash");
const tailscale = @import("../tailscale.zig");
const nginx = @import("../nginx.zig");
const acme = @import("../acme.zig");

pub fn handler(ctx: flash.Context) !void {
    const allocator = ctx.allocator;
    _ = allocator;
    
    std.debug.print("⚡ Expose command called!\n", .{});
    
    // TODO: Implement proper argument parsing with Flash
    std.debug.print("This is a placeholder for the expose functionality\n", .{});
}

// Keep the old run function for now as backup
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var name: ?[]const u8 = null;
    var port: u16 = 80;
    var domain: ?[]const u8 = null;
    var use_ssl = false;
    var use_funnel = false;
    var auto_cert = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--name")) {
            if (i + 1 < args.len) {
                name = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--port")) {
            if (i + 1 < args.len) {
                port = std.fmt.parseInt(u16, args[i + 1], 10) catch 80;
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--domain")) {
            if (i + 1 < args.len) {
                domain = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--ssl")) {
            use_ssl = true;
        } else if (std.mem.eql(u8, arg, "--funnel")) {
            use_funnel = true;
        } else if (std.mem.eql(u8, arg, "--auto-cert")) {
            auto_cert = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        }
    }

    const service_name = name orelse {
        std.debug.print("Error: --name is required\n", .{});
        return;
    };

    const service_domain = domain orelse {
        std.debug.print("Error: --domain is required\n", .{});
        return;
    };

    std.debug.print("Exposing service: {s}\n", .{service_name});
    std.debug.print("  Port: {}\n", .{port});
    std.debug.print("  Domain: {s}\n", .{service_domain});
    std.debug.print("  SSL: {}\n", .{use_ssl});
    std.debug.print("  Funnel: {}\n", .{use_funnel});
    std.debug.print("  Auto-cert: {}\n", .{auto_cert});

    if (use_funnel) {
        try exposeThroughFunnel(allocator, port);
    } else {
        try exposeThroughNginx(allocator, service_domain, port, use_ssl, auto_cert);
    }

    std.debug.print("✅ Service successfully exposed!\n", .{});
}

fn exposeThroughFunnel(allocator: std.mem.Allocator, port: u16) !void {
    std.debug.print("Setting up Tailscale Funnel...\n", .{});
    
    var ts_client = tailscale.TailscaleClient.init(allocator);
    ts_client.enableFunnel(port) catch |err| {
        std.debug.print("Error: Failed to enable Tailscale funnel: {}\n", .{err});
        return;
    };

    std.debug.print("Tailscale funnel enabled for port {}\n", .{port});
}

fn exposeThroughNginx(allocator: std.mem.Allocator, domain: []const u8, port: u16, use_ssl: bool, auto_cert: bool) !void {
    std.debug.print("Setting up Nginx reverse proxy...\n", .{});
    
    var nginx_manager = nginx.NginxManager.init(allocator, "/etc/nginx/sites-available");
    
    var ts_client = tailscale.TailscaleClient.init(allocator);
    const status = ts_client.getStatus() catch |err| {
        std.debug.print("Error: Failed to get Tailscale status: {}\n", .{err});
        return;
    };
    
    const upstream_host = if (status.self.addresses.len > 0) 
        status.self.addresses[0] 
    else 
        "127.0.0.1";

    var cert_path: ?[]const u8 = null;
    var key_path: ?[]const u8 = null;

    if (auto_cert and use_ssl) {
        std.debug.print("Auto-obtaining SSL certificate...\n", .{});
        
        var cert_manager = acme.CertificateManager.init(allocator, "/etc/ssl/ghostscale", .letsencrypt);
        
        const cert_paths = cert_manager.obtainCertificate(domain, "tailscale") catch |err| {
            std.debug.print("Warning: Failed to obtain certificate: {}\n", .{err});
            std.debug.print("Proceeding without SSL...\n", .{});
            return;
        };
        
        cert_path = cert_paths.cert_path;
        key_path = cert_paths.key_path;
    }

    const nginx_config = nginx.NginxConfig{
        .server_name = domain,
        .listen_port = if (use_ssl) 443 else 80,
        .upstream_host = upstream_host,
        .upstream_port = port,
        .ssl_enabled = use_ssl,
        .cert_path = cert_path,
        .key_path = key_path,
    };

    try nginx_manager.createConfig(nginx_config);

    if (!try nginx_manager.testConfig()) {
        std.debug.print("Error: Nginx configuration test failed\n", .{});
        return;
    }

    try nginx_manager.reload();
    
    std.debug.print("Nginx configuration created and reloaded\n", .{});
}

fn printHelp() void {
    std.debug.print(
        \\ghostscale expose - Expose a service through Tailscale reverse proxy
        \\
        \\Usage: ghostscale expose [options]
        \\
        \\Options:
        \\  --name <name>      Service name (required)
        \\  --port <port>      Service port (default: 80)
        \\  --domain <domain>  Domain name (required)
        \\  --ssl              Enable SSL/HTTPS
        \\  --funnel           Use Tailscale funnel for public exposure
        \\  --auto-cert        Automatically obtain SSL certificate
        \\  --help             Show this help message
        \\
        \\Examples:
        \\  ghostscale expose --name portainer --port 9000 --domain portainer.example.com
        \\  ghostscale expose --name app --port 3000 --domain app.example.com --ssl --auto-cert
        \\  ghostscale expose --name service --port 8080 --funnel
        \\
        , .{});
}