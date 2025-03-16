const std = @import("std");
const Context = @import("context.zig").Context;
const Method = @import("method.zig").Method;
const HandlerFn = @import("handler.zig").HandlerFn;

pub const Router = struct {
    allocator: std.mem.Allocator,
    handler: std.AutoHashMap(Method, HandlerFn),
    sub_router: std.StringHashMap(*Router),

    pub fn init(allocator: std.mem.Allocator) Router {}
    pub fn route(self: *const Router, context: *Context) *Context {}
};
