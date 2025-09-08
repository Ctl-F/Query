const _Iter = @import("Iter.zig");

pub fn SliceIter(comptime T: type) type {
    return struct {
        const This = @This();
        items: []const T,
        index: usize,

        pub fn init(slice: []const T) This {
            return .{
                .items = slice,
                .index = 0,
            };
        }

        pub fn to_iter(this: *This) _Iter.Iter(T) {
            return _Iter.Iter(T){
                .context = this,
                .vtable = .{
                    .next = This.v_next,
                    .index = This.v_index,
                    .seek = This.v_seek,
                },
            };
        }

        fn v_next(this: *anyopaque) ?T {
            const this_ptr: *This = @ptrCast(@alignCast(this));
            return this_ptr.next();
        }

        fn v_index(this: *anyopaque) usize {
            const this_ptr: *This = @ptrCast(@alignCast(this));
            return this_ptr.tell();
        }

        fn v_seek(this: *anyopaque, pos: usize) void {
            const this_ptr: *This = @ptrCast(@alignCast(this));
            return this_ptr.seek(pos);
        }

        pub fn seek(this: *This, pos: usize) void {
            this.index = @min(pos, this.items.len);
        }

        pub fn tell(this: *const This) usize {
            return this.index;
        }

        pub fn next(this: *This) ?T {
            if (this.index >= this.items.len) return null;
            defer this.index += 1;
            return this.items[this.index];
        }
    };
}
