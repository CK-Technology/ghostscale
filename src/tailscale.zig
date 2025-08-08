const std = @import("std");
const json = std.json;

pub const TailscaleDevice = struct {
    id: []const u8,
    hostname: []const u8,
    name: []const u8,
    addresses: [][]const u8,
    routes: [][]const u8,
    online: bool,
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
    
    return TailscaleDevice{
        .id = try allocator.dupe(u8, obj.get("ID").?.string),
        .hostname = try allocator.dupe(u8, obj.get("HostName").?.string),
        .name = try allocator.dupe(u8, obj.get("DNSName").?.string),
        .addresses = addresses,
        .routes = &.{},
        .online = obj.get("Online").?.bool,
    };
}