const std = @import("std");

pub const ACMEProvider = enum {
    letsencrypt,
    zerossl,
    custom,
    
    pub fn fromString(str: []const u8) ?ACMEProvider {
        if (std.mem.eql(u8, str, "letsencrypt")) return .letsencrypt;
        if (std.mem.eql(u8, str, "zerossl")) return .zerossl;
        if (std.mem.eql(u8, str, "custom")) return .custom;
        return null;
    }
    
    pub fn getEndpoint(self: ACMEProvider) []const u8 {
        return switch (self) {
            .letsencrypt => "https://acme-v02.api.letsencrypt.org/directory",
            .zerossl => "https://acme.zerossl.com/v2/DV90",
            .custom => "",
        };
    }
};

pub const CertificateManager = struct {
    allocator: std.mem.Allocator,
    cert_dir: []const u8,
    provider: ACMEProvider,
    
    pub fn init(allocator: std.mem.Allocator, cert_dir: []const u8, provider: ACMEProvider) CertificateManager {
        return CertificateManager{
            .allocator = allocator,
            .cert_dir = cert_dir,
            .provider = provider,
        };
    }
    
    pub fn obtainCertificate(self: *CertificateManager, domain: []const u8, dns_provider: []const u8) !CertPaths {
        std.debug.print("Obtaining certificate for domain: {s}\n", .{domain});
        std.debug.print("Using ACME provider: {s}\n", .{@tagName(self.provider)});
        std.debug.print("DNS provider: {s}\n", .{dns_provider});
        
        const cert_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.crt", .{ self.cert_dir, domain });
        const key_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.key", .{ self.cert_dir, domain });
        
        if (std.mem.eql(u8, dns_provider, "tailscale")) {
            return try self.obtainTailscaleCert(domain, cert_path, key_path);
        } else {
            return try self.obtainACMECert(domain, dns_provider, cert_path, key_path);
        }
    }
    
    fn obtainTailscaleCert(self: *CertificateManager, domain: []const u8, cert_path: []const u8, key_path: []const u8) !CertPaths {
        std.debug.print("Requesting Tailscale HTTPS certificate...\n");
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "tailscale", "cert", domain },
        }) catch |err| {
            std.debug.print("Error: Failed to run tailscale cert command: {}\n", .{err});
            return error.TailscaleCertFailed;
        };
        
        if (result.term.Exited != 0) {
            std.debug.print("Error: Tailscale cert failed:\n{s}\n", .{result.stderr});
            return error.TailscaleCertFailed;
        }
        
        const current_cert = try std.fmt.allocPrint(self.allocator, "{s}.crt", .{domain});
        const current_key = try std.fmt.allocPrint(self.allocator, "{s}.key", .{domain});
        defer self.allocator.free(current_cert);
        defer self.allocator.free(current_key);
        
        try std.fs.cwd().copyFile(current_cert, std.fs.cwd(), cert_path, .{});
        try std.fs.cwd().copyFile(current_key, std.fs.cwd(), key_path, .{});
        
        std.debug.print("Tailscale certificate obtained and moved to:\n");
        std.debug.print("  Cert: {s}\n", .{cert_path});
        std.debug.print("  Key: {s}\n", .{key_path});
        
        return CertPaths{
            .cert_path = cert_path,
            .key_path = key_path,
        };
    }
    
    fn obtainACMECert(self: *CertificateManager, domain: []const u8, dns_provider: []const u8, cert_path: []const u8, key_path: []const u8) !CertPaths {
        std.debug.print("Using ACME DNS-01 challenge with provider: {s}\n", .{dns_provider});
        
        const acme_endpoint = self.provider.getEndpoint();
        
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        
        try args.appendSlice(&[_][]const u8{
            "certbot", "certonly",
            "--dns-" ++ dns_provider,
            "--server", acme_endpoint,
            "--non-interactive",
            "--agree-tos",
            "--email", "admin@example.com", // This should be configurable
            "--cert-path", cert_path,
            "--key-path", key_path,
            "-d", domain,
        });
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args.items,
        }) catch |err| {
            std.debug.print("Error: Failed to run certbot: {}\n", .{err});
            return error.ACMECertFailed;
        };
        
        if (result.term.Exited != 0) {
            std.debug.print("Error: Certbot failed:\n{s}\n", .{result.stderr});
            return error.ACMECertFailed;
        }
        
        std.debug.print("ACME certificate obtained:\n");
        std.debug.print("  Cert: {s}\n", .{cert_path});
        std.debug.print("  Key: {s}\n", .{key_path});
        
        return CertPaths{
            .cert_path = cert_path,
            .key_path = key_path,
        };
    }
    
    pub fn renewCertificate(self: *CertificateManager, domain: []const u8) !void {
        std.debug.print("Renewing certificate for domain: {s}\n", .{domain});
        
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "certbot", "renew", "--cert-name", domain },
        }) catch |err| {
            std.debug.print("Error: Failed to renew certificate: {}\n", .{err});
            return;
        };
        
        if (result.term.Exited != 0) {
            std.debug.print("Certificate renewal failed:\n{s}\n", .{result.stderr});
            return;
        }
        
        std.debug.print("Certificate renewed successfully\n");
    }
    
    pub fn checkExpiry(self: *CertificateManager, cert_path: []const u8) !u64 {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ 
                "openssl", "x509", "-in", cert_path, "-noout", "-enddate" 
            },
        }) catch |err| {
            std.debug.print("Error: Failed to check certificate expiry: {}\n", .{err});
            return 0;
        };
        
        if (result.term.Exited != 0) {
            return 0;
        }
        
        // Parse the output to get expiry date
        // This is a simplified implementation - in production you'd want proper date parsing
        std.debug.print("Certificate expiry info: {s}\n", .{result.stdout});
        
        return 0; // Return days until expiry
    }
};

pub const CertPaths = struct {
    cert_path: []const u8,
    key_path: []const u8,
};