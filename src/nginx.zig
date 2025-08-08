const std = @import("std");

pub const NginxConfig = struct {
    server_name: []const u8,
    listen_port: u16,
    upstream_host: []const u8,
    upstream_port: u16,
    ssl_enabled: bool,
    cert_path: ?[]const u8,
    key_path: ?[]const u8,
    
    pub fn generateConfig(self: NginxConfig, allocator: std.mem.Allocator) ![]u8 {
        var config = std.ArrayList(u8).init(allocator);
        const writer = config.writer();
        
        try writer.print("upstream {s}_backend {{\n", .{self.server_name});
        try writer.print("    server {s}:{};\n", .{ self.upstream_host, self.upstream_port });
        try writer.writeAll("}\n\n");
        
        try writer.writeAll("server {\n");
        
        if (self.ssl_enabled) {
            try writer.print("    listen {} ssl http2;\n", .{self.listen_port});
            try writer.print("    server_name {s};\n\n", .{self.server_name});
            
            if (self.cert_path) |cert_path| {
                try writer.print("    ssl_certificate {s};\n", .{cert_path});
            }
            if (self.key_path) |key_path| {
                try writer.print("    ssl_certificate_key {s};\n", .{key_path});
            }
            
            try writer.writeAll("    ssl_protocols TLSv1.2 TLSv1.3;\n");
            try writer.writeAll("    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384;\n");
            try writer.writeAll("    ssl_prefer_server_ciphers off;\n\n");
        } else {
            try writer.print("    listen {};\n", .{self.listen_port});
            try writer.print("    server_name {s};\n\n", .{self.server_name});
        }
        
        try writer.writeAll("    location / {\n");
        try writer.print("        proxy_pass http://{s}_backend;\n", .{self.server_name});
        try writer.writeAll("        proxy_set_header Host $host;\n");
        try writer.writeAll("        proxy_set_header X-Real-IP $remote_addr;\n");
        try writer.writeAll("        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n");
        try writer.writeAll("        proxy_set_header X-Forwarded-Proto $scheme;\n");
        try writer.writeAll("        proxy_buffering off;\n");
        try writer.writeAll("    }\n");
        try writer.writeAll("}\n");
        
        return config.toOwnedSlice();
    }
};

pub const NginxManager = struct {
    allocator: std.mem.Allocator,
    config_dir: []const u8,
    
    pub fn init(allocator: std.mem.Allocator, config_dir: []const u8) NginxManager {
        return NginxManager{
            .allocator = allocator,
            .config_dir = config_dir,
        };
    }
    
    pub fn createConfig(self: *NginxManager, config: NginxConfig) !void {
        const config_content = try config.generateConfig(self.allocator);
        defer self.allocator.free(config_content);
        
        const config_filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}.conf", .{ self.config_dir, config.server_name });
        defer self.allocator.free(config_filename);
        
        const file = try std.fs.cwd().createFile(config_filename, .{});
        defer file.close();
        
        try file.writeAll(config_content);
        
        std.debug.print("Created Nginx config: {s}\n", .{config_filename});
    }
    
    pub fn removeConfig(self: *NginxManager, server_name: []const u8) !void {
        const config_filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}.conf", .{ self.config_dir, server_name });
        defer self.allocator.free(config_filename);
        
        std.fs.cwd().deleteFile(config_filename) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("Config file not found: {s}\n", .{config_filename});
                return;
            },
            else => return err,
        };
        
        std.debug.print("Removed Nginx config: {s}\n", .{config_filename});
    }
    
    pub fn reload(self: *NginxManager) !void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "nginx", "-s", "reload" },
        }) catch |err| {
            std.debug.print("Error: Failed to reload Nginx: {}\n", .{err});
            return;
        };
        
        if (result.term.Exited != 0) {
            std.debug.print("Error: Nginx reload failed with exit code: {}\n", .{result.term.Exited});
            return;
        }
        
        std.debug.print("Nginx reloaded successfully\n");
    }
    
    pub fn testConfig(self: *NginxManager) !bool {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "nginx", "-t" },
        }) catch |err| {
            std.debug.print("Error: Failed to test Nginx config: {}\n", .{err});
            return false;
        };
        
        const success = result.term.Exited == 0;
        if (!success) {
            std.debug.print("Nginx config test failed:\n{s}\n", .{result.stderr});
        }
        
        return success;
    }
};