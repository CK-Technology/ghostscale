const std = @import("std");
const json = std.json;

pub const TailscaleDevice = struct {
    id: []const u8,
    hostname: []const u8,
    name: []const u8,
    addresses: [][]const u8,
    routes: [][]const u8,
    online: bool,
    tags: [][]const u8,
};

pub const GhostService = struct {
    name: []const u8,
    service_type: GhostServiceType,
    hostname: []const u8,
    tailscale_ip: []const u8,
    api_port: u16,
    online: bool,
};

pub const GhostServiceType = enum {
    ghostdns,
    ghostgate,
    ghostscale,
    unknown,
    
    pub fn fromHostname(hostname: []const u8) GhostServiceType {
        if (std.mem.containsAtLeast(u8, hostname, 1, "ghostdns")) return .ghostdns;
        if (std.mem.containsAtLeast(u8, hostname, 1, "ghostgate")) return .ghostgate;
        if (std.mem.containsAtLeast(u8, hostname, 1, "ghostscale")) return .ghostscale;
        return .unknown;
    }
};

pub const TailscaleStatus = struct {
    self: TailscaleDevice,
    peers: []TailscaleDevice,
    magicDNSSuffix: []const u8,
};

pub const TailscaleClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,

    pub fn init(allocator: std.mem.Allocator) TailscaleClient {
        return TailscaleClient{
            .allocator = allocator,
            .base_url = "http://localhost:41641",
        };
    }

    pub fn getStatus(self: *TailscaleClient) !TailscaleStatus {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = try std.Uri.parse(try std.fmt.allocPrint(self.allocator, "{s}/localapi/v0/status", .{self.base_url}));
        defer self.allocator.free(uri.path);

        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();

        var request = try client.open(.GET, uri, headers, .{});
        defer request.deinit();

        try request.send(.{});
        try request.finish();
        try request.wait();

        const body = try request.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(body);

        var parsed = try json.parseFromSlice(json.Value, self.allocator, body, .{});
        defer parsed.deinit();

        return try parseStatus(self.allocator, parsed.value);
    }

    pub fn advertiseRoutes(self: *TailscaleClient, routes: []const []const u8) !void {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const routes_json = try json.stringifyAlloc(self.allocator, routes, .{});
        defer self.allocator.free(routes_json);

        const payload = try std.fmt.allocPrint(self.allocator, "{{\"routes\":{s}}}", .{routes_json});
        defer self.allocator.free(payload);

        const uri = try std.Uri.parse(try std.fmt.allocPrint(self.allocator, "{s}/localapi/v0/routes", .{self.base_url}));
        defer self.allocator.free(uri.path);

        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        try headers.append("Content-Type", "application/json");

        var request = try client.open(.POST, uri, headers, .{});
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = payload.len };
        try request.send(.{});
        try request.writeAll(payload);
        try request.finish();
        try request.wait();

        if (request.response.status != .ok) {
            return error.TailscaleAPIError;
        }
    }

    pub fn enableFunnel(self: *TailscaleClient, port: u16) !void {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const payload = try std.fmt.allocPrint(self.allocator, "{{\"port\":{}}}", .{port});
        defer self.allocator.free(payload);

        const uri = try std.Uri.parse(try std.fmt.allocPrint(self.allocator, "{s}/localapi/v0/serve-config", .{self.base_url}));
        defer self.allocator.free(uri.path);

        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        try headers.append("Content-Type", "application/json");

        var request = try client.open(.POST, uri, headers, .{});
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = payload.len };
        try request.send(.{});
        try request.writeAll(payload);
        try request.finish();
        try request.wait();

        if (request.response.status != .ok) {
            return error.TailscaleAPIError;
        }
    }

    pub fn joinTailnet(self: *TailscaleClient, auth_key: []const u8, hostname: ?[]const u8) !void {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const login_payload = if (hostname) |h|
            try std.fmt.allocPrint(self.allocator, "{{\"authkey\":\"{s}\",\"hostname\":\"{s}\"}}", .{ auth_key, h })
        else
            try std.fmt.allocPrint(self.allocator, "{{\"authkey\":\"{s}\"}}", .{auth_key});
        defer self.allocator.free(login_payload);

        const uri = try std.Uri.parse(try std.fmt.allocPrint(self.allocator, "{s}/localapi/v0/login", .{self.base_url}));
        defer self.allocator.free(uri.path);

        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        try headers.append("Content-Type", "application/json");

        var request = try client.open(.POST, uri, headers, .{});
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = login_payload.len };
        try request.send(.{});
        try request.writeAll(login_payload);
        try request.finish();
        try request.wait();

        if (request.response.status != .ok) {
            return error.TailscaleJoinError;
        }
    }

    pub fn findGhostServices(self: *TailscaleClient) ![]GhostService {
        const status = try self.getStatus();
        var ghost_services = std.ArrayList(GhostService).init(self.allocator);
        defer ghost_services.deinit();

        for (status.peers) |peer| {
            const service_type = GhostServiceType.fromHostname(peer.hostname);
            if (service_type != .unknown and peer.addresses.len > 0) {
                const default_port: u16 = switch (service_type) {
                    .ghostdns => 8080,
                    .ghostgate => 8081,
                    .ghostscale => 8082,
                    .unknown => 8080,
                };

                try ghost_services.append(GhostService{
                    .name = try self.allocator.dupe(u8, peer.name),
                    .service_type = service_type,
                    .hostname = try self.allocator.dupe(u8, peer.hostname),
                    .tailscale_ip = try self.allocator.dupe(u8, peer.addresses[0]),
                    .api_port = default_port,
                    .online = peer.online,
                });
            }
        }

        return try ghost_services.toOwnedSlice();
    }

    pub fn registerGhostService(self: *TailscaleClient, service_type: GhostServiceType, port: u16) !void {
        const hostname = switch (service_type) {
            .ghostdns => "ghostdns",
            .ghostgate => "ghostgate", 
            .ghostscale => "ghostscale",
            .unknown => "ghost-unknown",
        };

        const tag = switch (service_type) {
            .ghostdns => "tag:ghostdns",
            .ghostgate => "tag:ghostgate",
            .ghostscale => "tag:ghostscale", 
            .unknown => "tag:ghost",
        };

        std.debug.print("Registering {s} service on port {} with tag {s}\n", .{ hostname, port, tag });
        
        // Set hostname
        try self.setHostname(hostname);
        
        // Enable funnel for API access
        try self.enableFunnel(port);
    }

    fn setHostname(self: *TailscaleClient, hostname: []const u8) !void {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const payload = try std.fmt.allocPrint(self.allocator, "{{\"hostname\":\"{s}\"}}", .{hostname});
        defer self.allocator.free(payload);

        const uri = try std.Uri.parse(try std.fmt.allocPrint(self.allocator, "{s}/localapi/v0/prefs", .{self.base_url}));
        defer self.allocator.free(uri.path);

        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        try headers.append("Content-Type", "application/json");

        var request = try client.open(.PATCH, uri, headers, .{});
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = payload.len };
        try request.send(.{});
        try request.writeAll(payload);
        try request.finish();
        try request.wait();

        if (request.response.status != .ok) {
            return error.TailscaleAPIError;
        }
    }
};

fn parseStatus(allocator: std.mem.Allocator, value: json.Value) !TailscaleStatus {
    const obj = value.object;
    
    const self_obj = obj.get("Self").?.object;
    const peers_array = obj.get("Peer").?.array;
    
    var peers = try allocator.alloc(TailscaleDevice, peers_array.items.len);
    for (peers_array.items, 0..) |peer, i| {
        peers[i] = try parseDevice(allocator, peer);
    }
    
    return TailscaleStatus{
        .self = try parseDevice(allocator, json.Value{ .object = self_obj }),
        .peers = peers,
        .magicDNSSuffix = try allocator.dupe(u8, obj.get("MagicDNSSuffix").?.string),
    };
}

fn parseDevice(allocator: std.mem.Allocator, value: json.Value) !TailscaleDevice {
    const obj = value.object;
    
    const addresses_array = obj.get("TailscaleIPs").?.array;
    var addresses = try allocator.alloc([]const u8, addresses_array.items.len);
    for (addresses_array.items, 0..) |addr, i| {
        addresses[i] = try allocator.dupe(u8, addr.string);
    }
    
    const tags_array = obj.get("Tags") orelse json.Value{ .array = json.Array.init(allocator) };
    var tags = try allocator.alloc([]const u8, if (tags_array == .array) tags_array.array.items.len else 0);
    if (tags_array == .array) {
        for (tags_array.array.items, 0..) |tag, i| {
            tags[i] = try allocator.dupe(u8, tag.string);
        }
    }

    return TailscaleDevice{
        .id = try allocator.dupe(u8, obj.get("ID").?.string),
        .hostname = try allocator.dupe(u8, obj.get("HostName").?.string),
        .name = try allocator.dupe(u8, obj.get("DNSName").?.string),
        .addresses = addresses,
        .routes = &.{},
        .online = obj.get("Online").?.bool,
        .tags = tags,
    };
}