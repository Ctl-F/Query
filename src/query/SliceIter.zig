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
                    //TODO: index, seek
                },
            };
        }

        fn v_next(this: *anyopaque) ?T {
            const this_ptr: *This = @ptrCast(@alignCast(this));
            return this_ptr.next();
        }

        pub fn next(this: *This) ?T {
            if (this.index >= this.items.len) return null;
            defer this.index += 1;
            return this.items[this.index];
        }
    };
}
