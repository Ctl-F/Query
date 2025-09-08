const std = @import("std");
const _SliceIter = @import("query/SliceIter.zig");
const _Iter = @import("query/Iter.zig");

pub const Iter = _Iter.Iter;
pub const SliceIter = _SliceIter.SliceIter;

pub fn Query(comptime T: type) type {
    return struct {
        const This = @This();

        iter: Iter(T),

        pub fn init(iter: Iter(T)) This {
            return .{
                .iter = iter,
            };
        }

        pub fn count(this: *This) usize {
            const pos = this.iter.index();
            defer this.iter.seek(pos);

            this.iter.seek(0);
            var num: usize = 0;

            while (this.iter.next()) |_| : (num += 1) {}

            return num;
        }

        pub fn empty(this: *This) bool {
            const pos = this.iter.index();
            defer this.iter.seek(pos);

            this.iter.seek(0);
            return this.iter.next() == null;
        }

        pub const WhereIter = struct {
            iter: Iter(T),
            predicate: *const fn (T) bool,

            pub fn next(this: *@This()) ?T {
                if (this.iter.next()) |v| {
                    if (this.predicate(v)) {
                        return v;
                    }
                    return null;
                }
                return null;
            }

            pub fn to_iter(this: *@This()) Iter(T) {
                return .{
                    .context = this,
                    .vtable = .{
                        .next = @This().next,
                        .index = this.iter.index,
                        .seek = this.iter.seek,
                    },
                };
            }
        };

        pub fn where(this: *This, predicate: anytype) WhereIter {
            const info = if (@TypeOf(predicate) == type) @typeInfo(predicate) else @typeInfo(@TypeOf(predicate));

            switch (info) {
                .@"fn" => |fun| {
                    if (fun.return_type == null or fun.return_type.? != bool) {
                        @compileError("`any` Predicate must return a boolean");
                    }
                    if (fun.params.len != 1) {
                        @compileError("`any` Predicate must accept a single parameter");
                    }
                    if (fun.params[0].type == null or fun.params[0].type.? != T) {
                        @compileError("Expected `" ++ @typeName(T) ++ "` as parameter type, got `" ++ @typeName(fun.params[0].type) ++ "`");
                    }

                    return .{
                        .predicate = predicate,
                        .iter = this.iter,
                    };
                },
                .@"struct" => {
                    return this._any_struct(predicate);
                },
                else => @compileError("Expected function predicate or struct predicate, got " ++ @typeName(predicate)),
            }
        }

        pub fn any(this: *This, predicate: anytype) bool {
            const info = if (@TypeOf(predicate) == type) @typeInfo(predicate) else @typeInfo(@TypeOf(predicate));
            //@compileLog(info);
            switch (info) {
                .@"fn" => |fun| {
                    if (fun.return_type == null or fun.return_type.? != bool) {
                        @compileError("`any` Predicate must return a boolean");
                    }
                    if (fun.params.len != 1) {
                        @compileError("`any` Predicate must accept a single parameter");
                    }
                    if (fun.params[0].type == null or fun.params[0].type.? != T) {
                        @compileError("Expected `" ++ @typeName(T) ++ "` as parameter type, got `" ++ @typeName(fun.params[0].type) ++ "`");
                    }

                    return this._any_fn(predicate);
                },
                .@"struct" => {
                    // for (str.decls) |decl| {
                    //     @compileLog(decl.name);
                    //     if (std.mem.eql(u8, decl.name, "what")) {
                    //         break;
                    //     }
                    // } else {
                    //     @compileError("`any` Predicate struct must declare a `what` function");
                    // }

                    return this._any_struct(predicate);
                },
                else => @compileError("Expected function predicate or struct predicate, got " ++ @typeName(predicate)),
            }
        }

        fn _any_fn(this: *This, comptime predicate: fn (T) bool) bool {
            const pos = this.iter.index();
            defer this.iter.seek(pos);

            this.iter.seek(0);
            while (this.iter.next()) |itm| {
                if (predicate(itm)) return true;
            }
            return false;
        }

        fn _any_struct(this: *This, comptime predicate: anytype) bool {
            const pos = this.iter.index();
            defer this.iter.seek(pos);

            this.iter.seek(0);
            while (this.iter.next()) |itm| {
                if (predicate.what(itm)) return true;
            }

            return false;
        }
    };
}

test "SliceIterator" {
    const items = [_]u32{
        42, 100, 10, 50, 0,
    };

    var count: usize = 0;
    var index: usize = 0;

    var iter = SliceIter(u32).init(&items);
    while (iter.next()) |itm| : ({
        count += 1;
        index += 1;
    }) {
        try std.testing.expectEqual(itm, items[index]);
    }
    try std.testing.expectEqual(items.len, count);
}

test "SliceIter-Generic" {
    const items = [_]u32{ 32, 34, 56, 4, 30 };
    var count: usize = 0;
    var index: usize = 0;

    var slit = SliceIter(u32).init(&items);
    var iter = slit.to_iter();

    while (iter.next()) |itm| : ({
        count += 1;
        index += 1;
    }) {
        try std.testing.expectEqual(itm, items[index]);
    }
    try std.testing.expectEqual(items.len, count);
}

test "Query Count" {
    const items = [_]u32{
        0, 1, 2, 3, 4, 5,
    };
    var slit = SliceIter(u32).init(&items);
    var query = Query(u32).init(slit.to_iter());

    try std.testing.expectEqual(query.count(), items.len);
    try std.testing.expect(!query.empty());

    var eslit = SliceIter(u32).init(&.{});
    var equery = Query(u32).init(eslit.to_iter());

    try std.testing.expectEqual(equery.count(), 0);
    try std.testing.expect(equery.empty());
}

fn TestingPredicate(item: u32) bool {
    return item == 3;
}

test "Query Any Fn" {
    const items = [_]u32{
        0, 1, 2, 3, 4, 5,
    };
    var slit = SliceIter(u32).init(&items);
    var query = Query(u32).init(slit.to_iter());

    try std.testing.expect(query.any(TestingPredicate));
}

test "Query Any Struct" {
    const items = [_]u32{
        0, 1, 2, 3, 4, 5,
    };
    var slit = SliceIter(u32).init(&items);
    var query = Query(u32).init(slit.to_iter());

    try std.testing.expect(query.any(struct {
        pub fn what(i: u32) bool {
            return i == 2;
        }
    }));
}
