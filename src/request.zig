const std = @import("std");
const Method = @import("method.zig").Method;
const Allocator = std.mem.Allocator;
const Connection = std.net.Server.Connection;

pub const Request = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    http_version: []const u8,
    method: Method,
    target: []const u8,
    body: ?[]const u8,
    headers: std.StringHashMap([]const u8),

    pub fn parse(allocator: Allocator, buffer: []const u8) RequestError!Self {
        var http_version: []const u8 = undefined;
        var method: Method = undefined;
        var target: []const u8 = undefined;
        var body: ?[]const u8 = null;
        var headers = std.StringHashMap([]const u8).init(allocator);

        // Buffer iterator
        var buffer_it = std.mem.tokenizeSequence(u8, buffer, "\r\n\r\n");

        // Iterate head
        const head_part = buffer_it.next() orelse return RequestError.InvalidRequest;
        var head_lines_it = std.mem.tokenizeSequence(u8, head_part, "\r\n");

        // Parse head: request line
        const request_line = head_lines_it.next() orelse return RequestError.MalformedRequestLine;
        var request_line_it = std.mem.tokenizeAny(u8, request_line, " ");
        const method_str = request_line_it.next() orelse return RequestError.MalformedRequestLine;
        method = std.meta.stringToEnum(Method, method_str) orelse return RequestError.InvalidMethod;
        target = request_line_it.next() orelse return RequestError.MalformedRequestLine;
        http_version = request_line_it.next() orelse return RequestError.MalformedRequestLine;

        // Parse head: headers lines
        while (head_lines_it.next()) |kv_header| {
            var kv_header_it = std.mem.tokenizeScalar(u8, kv_header, ':');
            var key = kv_header_it.next() orelse continue;
            var val = kv_header_it.next() orelse continue;

            key = std.mem.trim(u8, key, " ");
            val = std.mem.trim(u8, val, " ");

            headers.put(key, val) catch {
                return RequestError.OutOfMemory;
            };
        }
        const body_part = buffer_it.rest();
        if (body_part.len != 0) {
            body = body_part;
        }

        return Self{
            .allocator = allocator,
            .http_version = http_version,
            .method = method,
            .target = target,
            .body = body,
            .headers = headers,
        };
    }

    pub fn deinit(self: *Request) void {
        self.headers.deinit();
    }
};

pub const RequestError = error{
    InvalidRequest,
    InvalidMethod,
    OutOfMemory,
    MalformedRequestLine,
} || std.posix.ReadError;

test "Valid GET Request" {
    const expect = std.testing.expect;
    const allocator = std.testing.allocator;
    const buffer =
        "GET /index.html HTTP/1.1\r\n" ++
        "Host: example.com\r\n" ++
        "User-Agent: ZigClient/1.0\r\n" ++
        "Accept: text/html\r\n\r\n";

    var request = try Request.parse(allocator, buffer);
    defer request.deinit();

    try expect(request.method == .GET);
    try expect(std.mem.eql(u8, request.target, "/index.html"));
    try expect(std.mem.eql(u8, request.http_version, "HTTP/1.1"));
    try expect(std.mem.eql(u8, request.headers.get("Host") orelse "", "example.com"));
    try expect(std.mem.eql(u8, request.headers.get("User-Agent") orelse "", "ZigClient/1.0"));
    try expect(std.mem.eql(u8, request.headers.get("Accept") orelse "", "text/html"));
    try expect(request.body == null);
}

test "Valid POST Request with Body" {
    const expect = std.testing.expect;
    const allocator = std.testing.allocator;
    const buffer =
        "POST /submit HTTP/1.1\r\n" ++
        "Host: example.com\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 17\r\n\r\n" ++
        "{\"key\":\"value\"}";

    var request = try Request.parse(allocator, buffer);
    defer request.deinit();

    try expect(request.method == .POST);
    try expect(std.mem.eql(u8, request.target, "/submit"));
    try expect(std.mem.eql(u8, request.http_version, "HTTP/1.1"));
    try expect(std.mem.eql(u8, request.headers.get("Host") orelse "", "example.com"));
    try expect(std.mem.eql(u8, request.headers.get("Content-Type") orelse "", "application/json"));
    try expect(std.mem.eql(u8, request.body.?, "{\"key\":\"value\"}"));
}

test "Request with Query Parameters" {
    const expect = std.testing.expect;
    const allocator = std.testing.allocator;
    const buffer =
        "GET /search?q=test HTTP/1.1\r\n" ++
        "Host: example.com\r\n\r\n";

    var request = try Request.parse(allocator, buffer);
    defer request.deinit();

    try expect(request.method == .GET);
    try expect(std.mem.eql(u8, request.target, "/search?q=test"));
    try expect(std.mem.eql(u8, request.http_version, "HTTP/1.1"));
    try expect(std.mem.eql(u8, request.headers.get("Host") orelse "", "example.com"));
}

test "Invalid HTTP Method" {
    const expectError = std.testing.expectError;
    const allocator = std.testing.allocator;
    const buffer =
        "INVALID / HTTP/1.1\r\n" ++
        "Host: example.com\r\n\r\n";

    try expectError(error.InvalidMethod, Request.parse(allocator, buffer));
}

test "Malformed Request Line" {
    const expectError = std.testing.expectError;
    const allocator = std.testing.allocator;
    const buffer =
        "GET\r\n" ++
        "Host: example.com\r\n\r\n";

    try expectError(RequestError.MalformedRequestLine, Request.parse(allocator, buffer));
}

test "Request with Extra Whitespace" {
    const expect = std.testing.expect;
    const allocator = std.testing.allocator;
    const buffer =
        "GET   /index.html   HTTP/1.1\r\n" ++
        "Host: example.com\r\n\r\n";

    var request = try Request.parse(allocator, buffer);
    defer request.deinit();

    try expect(request.method == .GET);
    try expect(std.mem.eql(u8, request.target, "/index.html"));
    try expect(std.mem.eql(u8, request.http_version, "HTTP/1.1"));
    try expect(std.mem.eql(u8, request.headers.get("Host") orelse "", "example.com"));
}
