const query = @import("query.zig");

pub fn Iter(comptime T: type) type {
    return struct {
        context: *anyopaque,
        vtable: VTable,

        pub const VTable = struct {
            next: *const fn (ctx: *anyopaque) ?T,
            index: *const fn (ctx: *anyopaque) usize,
            seek: *const fn (ctx: *anyopaque, index: usize) void,
            extend: *const fn (ctx: *anyopaque) query.Query(T),
        };

        pub fn next(this: @This()) ?T {
            return this.vtable.next(this.context);
        }

        pub fn index(this: @This()) usize {
            return this.vtable.index(this.context);
        }

        pub fn seek(this: @This(), pos: usize) void {
            return this.vtable.seek(this.context, pos);
        }

        pub fn extend(this: @This()) query.Query(T) {
            return this.vtable.extend(this.context);
        }
    };
}
