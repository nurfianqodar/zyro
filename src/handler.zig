const Context = @import("context.zig").Context;

pub const HandlerFn = *const fn (*Context) *Context;
