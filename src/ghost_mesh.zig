const std = @import("std");
const tailscale = @import("tailscale.zig");

/// GhostMesh manages the lifecycle and coordination of ghost services
pub const GhostMesh = struct {
    allocator: std.mem.Allocator,
    ts_client: tailscale.TailscaleClient,
    service_type: tailscale.GhostServiceType,
    config: GhostMeshConfig,

    pub const GhostMeshConfig = struct {
        auth_key: ?[]const u8 = null,
        auto_join: bool = true,
        api_port: ?u16 = null,
        hostname_override: ?[]const u8 = null,
        enable_discovery: bool = true,
        health_check_interval: u32 = 30, // seconds
    };

    pub fn init(allocator: std.mem.Allocator, service_type: tailscale.GhostServiceType, config: GhostMeshConfig) GhostMesh {
        return GhostMesh{
            .allocator = allocator,
            .ts_client = tailscale.TailscaleClient.init(allocator),
            .service_type = service_type,
            .config = config,
        };
    }

    /// Auto-join Tailscale network and register this service
    pub fn bootstrap(self: *GhostMesh) !void {
        if (!self.config.auto_join) {
            std.debug.print("Auto-join disabled, skipping Tailscale registration\n");
            return;
        }

        const auth_key = self.config.auth_key orelse {
            std.debug.print("Warning: No auth key provided, skipping auto-join\n");
            return;
        };

        std.debug.print("🚀 Bootstrapping {s} service...\n", .{@tagName(self.service_type)});

        // Join Tailscale network
        try self.joinNetwork(auth_key);

        // Register as ghost service
        const api_port = self.config.api_port orelse self.getDefaultPort();
        try self.registerService(api_port);

        // Start health monitoring
        if (self.config.enable_discovery) {
            try self.startHealthMonitoring();
        }

        std.debug.print("✅ {s} successfully joined ghost mesh\n", .{@tagName(self.service_type)});
    }

    /// Join Tailscale network with auth key
    fn joinNetwork(self: *GhostMesh, auth_key: []const u8) !void {
        std.debug.print("🔐 Joining Tailscale network...\n");
        
        try self.ts_client.joinTailnet(auth_key, self.config.hostname_override);
        
        // Verify we're connected
        const status = self.ts_client.getStatus() catch |err| {
            std.debug.print("❌ Failed to verify Tailscale connection: {}\n", .{err});
            return err;
        };
        
        std.debug.print("✅ Connected to Tailscale as {s} ({s})\n", .{ status.self.hostname, status.self.addresses[0] });
    }

    /// Register this node as a ghost service
    fn registerService(self: *GhostMesh, api_port: u16) !void {
        std.debug.print("📝 Registering {s} service on port {}...\n", .{ @tagName(self.service_type), api_port });
        
        try self.ts_client.registerGhostService(self.service_type, api_port);
        
        std.debug.print("✅ Service registered and API funnel enabled\n");
    }

    /// Discover other ghost services on the network
    pub fn discoverPeers(self: *GhostMesh) ![]tailscale.GhostService {
        return try self.ts_client.findGhostServices();
    }

    /// Get the API endpoint for this service (for other services to connect)
    pub fn getAPIEndpoint(self: *GhostMesh) ![]const u8 {
        const status = try self.ts_client.getStatus();
        const api_port = self.config.api_port orelse self.getDefaultPort();
        
        return try std.fmt.allocPrint(
            self.allocator,
            "http://{s}.{s}:{}",
            .{ status.self.hostname, status.magicDNSSuffix, api_port }
        );
    }

    /// Get the tailscale IP of this service
    pub fn getTailscaleIP(self: *GhostMesh) ![]const u8 {
        const status = try self.ts_client.getStatus();
        return try self.allocator.dupe(u8, status.self.addresses[0]);
    }

    /// Find a specific ghost service by type
    pub fn findService(self: *GhostMesh, service_type: tailscale.GhostServiceType) !?tailscale.GhostService {
        const services = try self.discoverPeers();
        defer self.allocator.free(services);
        
        for (services) |service| {
            if (service.service_type == service_type and service.online) {
                return service;
            }
        }
        
        return null;
    }

    /// Start background health monitoring and service discovery
    fn startHealthMonitoring(self: *GhostMesh) !void {
        std.debug.print("💓 Starting health monitoring (interval: {}s)\n", .{self.config.health_check_interval});
        
        // TODO: Implement background thread for health checks
        // For now, just print that it would start
        std.debug.print("📊 Health monitoring would run every {}s\n", .{self.config.health_check_interval});
    }

    /// Get default API port for this service type
    fn getDefaultPort(self: *GhostMesh) u16 {
        return switch (self.service_type) {
            .ghostdns => 8080,
            .ghostgate => 8081,
            .ghostscale => 8082,
            .unknown => 8080,
        };
    }

    /// Create a mesh coordination message for inter-service communication
    pub fn createCoordinationMessage(self: *GhostMesh, message_type: MeshMessageType, payload: []const u8) ![]const u8 {
        const status = try self.ts_client.getStatus();
        
        const message = MeshMessage{
            .sender_id = status.self.id,
            .sender_type = self.service_type,
            .sender_ip = status.self.addresses[0],
            .message_type = message_type,
            .payload = payload,
            .timestamp = std.time.timestamp(),
        };
        
        return try std.json.stringifyAlloc(self.allocator, message, .{});
    }

    pub const MeshMessageType = enum {
        service_discovery,
        health_check,
        configuration_update,
        dns_record_sync,
        route_advertisement,
        security_alert,
    };

    pub const MeshMessage = struct {
        sender_id: []const u8,
        sender_type: tailscale.GhostServiceType,
        sender_ip: []const u8,
        message_type: MeshMessageType,
        payload: []const u8,
        timestamp: i64,
    };
};

/// Utility functions for auto-starting ghost services
pub const GhostAutoStart = struct {
    /// Auto-detect service type from environment or binary name
    pub fn detectServiceType() tailscale.GhostServiceType {
        // Try environment variable first
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "GHOST_SERVICE_TYPE")) |service_type| {
            defer std.heap.page_allocator.free(service_type);
            if (std.mem.eql(u8, service_type, "ghostdns")) return .ghostdns;
            if (std.mem.eql(u8, service_type, "ghostgate")) return .ghostgate;
            if (std.mem.eql(u8, service_type, "ghostscale")) return .ghostscale;
        } else |_| {}

        // Try to detect from binary name
        const args = std.process.argsAlloc(std.heap.page_allocator) catch return .unknown;
        defer std.process.argsFree(std.heap.page_allocator, args);
        
        if (args.len > 0) {
            const binary_name = std.fs.path.basename(args[0]);
            if (std.mem.containsAtLeast(u8, binary_name, 1, "ghostdns")) return .ghostdns;
            if (std.mem.containsAtLeast(u8, binary_name, 1, "ghostgate")) return .ghostgate;
            if (std.mem.containsAtLeast(u8, binary_name, 1, "ghostscale")) return .ghostscale;
        }

        return .unknown;
    }

    /// Load configuration from environment variables
    pub fn loadConfigFromEnv(allocator: std.mem.Allocator) GhostMesh.GhostMeshConfig {
        var config = GhostMesh.GhostMeshConfig{};

        // Load auth key
        if (std.process.getEnvVarOwned(allocator, "TAILSCALE_AUTHKEY")) |auth_key| {
            config.auth_key = auth_key;
        } else |_| {}

        // Load API port
        if (std.process.getEnvVarOwned(allocator, "GHOST_API_PORT")) |port_str| {
            defer allocator.free(port_str);
            config.api_port = std.fmt.parseInt(u16, port_str, 10) catch null;
        } else |_| {}

        // Load hostname override
        if (std.process.getEnvVarOwned(allocator, "GHOST_HOSTNAME")) |hostname| {
            config.hostname_override = hostname;
        } else |_| {}

        // Load auto-join setting
        if (std.process.getEnvVarOwned(allocator, "GHOST_AUTO_JOIN")) |auto_join_str| {
            defer allocator.free(auto_join_str);
            config.auto_join = std.mem.eql(u8, auto_join_str, "true") or std.mem.eql(u8, auto_join_str, "1");
        } else |_| {}

        return config;
    }
};