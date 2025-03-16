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
    body: []const u8,
    headers: std.StringHashMap([]const u8),

    pub fn parse(allocator: Allocator, buffer: []const u8) RequestError!Self {
        var http_version: []const u8 = undefined;
        var method: Method = undefined;
        var target: []const u8 = undefined;
        var body: []const u8 = "";
        var headers = std.StringHashMap([]const u8).init(allocator);

        // Buffer iterator
        var buffer_it = std.mem.tokenizeSequence(u8, buffer, "\r\n\r\n");

        // Iterate http head
        const head_part = buffer_it.next() orelse return RequestError.InvalidRequest;
        var head_lines_it = std.mem.tokenizeSequence(u8, head_part, "\r\n");

        // Head request line
        const request_line = head_lines_it.next() orelse return RequestError.InvalidRequest;
        var request_line_it = std.mem.tokenizeSequence(u8, request_line, " ");
        const method_str = request_line_it.next() orelse return RequestError.InvalidRequest;
        method = std.meta.stringToEnum(Method, method_str) orelse return RequestError.InvalidMethod;
        target = request_line_it.next() orelse return RequestError.InvalidRequest;
        http_version = request_line_it.next() orelse return RequestError.InvalidRequest;

        // Head headers lines
        while (head_lines_it.next()) |kv_header| {
            var kv_header_it = std.mem.tokenizeSequence(u8, kv_header, ": ");
            const key = kv_header_it.next() orelse continue;
            const val = kv_header_it.next() orelse continue;

            headers.put(key, val) catch {
                return RequestError.OutOfMemory;
            };
        }
        body = buffer_it.rest();

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
} || std.posix.ReadError;

test "parse request" {
    const expect = std.testing.expect;
    const allocator = std.testing.allocator;
    const buffer = "GET /index.html HTTP/1.1\r\nHost: example.com\r\nUser-Agent: ZigClient/1.0\r\nAccept: text/html\r\n\r\nHello, this is a test body!\n";

    var request = try Request.parse(allocator, buffer);
    defer request.deinit();

    try expect(request.method == .GET);
    const host = request.headers.get("Host") orelse "";
    const user_agent = request.headers.get("User-Agent") orelse "";
    const accept = request.headers.get("Accept") orelse "";

    try expect(request.method == .GET);
    try expect(std.mem.eql(u8, request.target, "/index.html"));
    try expect(std.mem.eql(u8, request.http_version, "HTTP/1.1"));
    try expect(std.mem.eql(u8, host, "example.com"));
    try expect(std.mem.eql(u8, user_agent, "ZigClient/1.0"));
    try expect(std.mem.eql(u8, accept, "text/html"));
    try expect(std.mem.eql(u8, request.body, "Hello, this is a test body!\n"));
}
