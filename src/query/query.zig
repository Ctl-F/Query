const std = @import("std");
const _SliceIter = @import("SliceIter.zig");
const _Iter = @import("Iter.zig");

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

        pub fn count(const_this: *const This) usize {
            // the overall side-effects of this function should respect the "const" qualifier
            // but we do need to make some temporary modifications to our iterator thus we must drop
            // const for the purposes of this method
            var this: *This = @constCast(const_this);

            const pos = this.iter.index();
            defer this.iter.seek(pos);

            this.iter.seek(0);
            var num: usize = 0;

            while (this.iter.next()) |_| : (num += 1) {}

            return num;
        }

        pub fn restart(const_this: *const This) *This {
            var this: *This = @constCast(const_this);
            this.iter.seek(0);

            return this;
        }

        pub fn empty(const_this: *const This) bool {
            var this: *This = @constCast(const_this);

            const pos = this.iter.index();
            defer this.iter.seek(pos);

            this.iter.seek(0);
            return this.iter.next() == null;
        }

        pub const WhereIter = struct {
            iter: Iter(T),
            predicate: *const fn (T) bool,

            pub fn next(this: *@This()) ?T {
                while (this.iter.next()) |v| {
                    if (this.predicate(v)) {
                        return v;
                    }
                }
                return null;
            }

            pub fn extend(this: *const @This()) Query(T) {
                return Query(T).init(this.to_iter());
            }

            fn v_extend(this: *anyopaque) Query(T) {
                const this_ptr: *@This() = @ptrCast(@alignCast(this));
                return this_ptr.extend();
            }

            fn v_next(this: *anyopaque) ?T {
                return next(@ptrCast(@alignCast(this)));
            }

            fn v_index(this: *anyopaque) usize {
                const this_ptr: *@This() = @ptrCast(@alignCast(this));
                return this_ptr.iter.index();
            }

            fn v_seek(this: *anyopaque, pos: usize) void {
                const this_ptr: *@This() = @ptrCast(@alignCast(this));
                return this_ptr.iter.seek(pos);
            }

            pub fn to_iter(this: *const @This()) Iter(T) {
                return .{
                    .context = @constCast(this),
                    .vtable = .{
                        .next = @This().v_next,
                        .index = @This().v_index,
                        .seek = @This().v_seek,
                        .extend = @This().v_extend,
                    },
                };
            }
        };

        pub fn SelectIter(comptime U: type) type {
            return struct {
                iter: Iter(T),
                transformer: *const fn (T) U,

                pub fn next(this: *@This()) ?U {
                    if (this.iter.next()) |v| {
                        return this.transformer(v);
                    }
                    return null;
                }

                pub fn v_next(this: *const anyopaque) ?U {
                    var this_ptr: *@This() = @ptrCast(@alignCast(@constCast(this)));
                    return this_ptr.next();
                }

                pub fn v_index(this: *const anyopaque) usize {
                    var this_ptr: *@This() = @ptrCast(@alignCast(@constCast(this)));
                    return this_ptr.iter.index();
                }

                pub fn v_seek(this: *anyopaque, pos: usize) void {
                    const this_ptr: *@This() = @ptrCast(@alignCast(this));
                    return this_ptr.iter.seek(pos);
                }

                pub fn v_extend(this: *const anyopaque) Query(U) {
                    return extend(@ptrCast(@alignCast(this)));
                }

                pub fn extend(this: *const @This()) Query(U) {
                    return Query(U).init(this.to_iter());
                }

                pub fn to_iter(this: *const @This()) Iter(U) {
                    return .{
                        .context = @constCast(this),
                        .vtable = .{
                            .next = @This().v_next,
                            .index = @This().v_index,
                            .seek = @This().v_seek,
                            .extend = @This().v_extend,
                        },
                    };
                }
            };
        }

        pub fn where(this: *const This, predicate: anytype) WhereIter {
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
                    return .{
                        .predicate = predicate.what,
                        .iter = this.iter,
                    };
                },
                else => @compileError("Expected function predicate or struct predicate, got " ++ @typeName(predicate)),
            }
        }

        pub fn select(this: *const This, comptime U: type, predicate: anytype) SelectIter(U) {
            const info = if (@TypeOf(predicate) == type) @typeInfo(predicate) else @typeInfo(@TypeOf(predicate));

            switch (info) {
                .@"fn" => |fun| {
                    if (fun.return_type == null or fun.return_type.? != U) {
                        @compileError("`select` Transformer must return a " ++ @typeName(U));
                    }
                    if (fun.params.len != 1) {
                        @compileError("`select` Transformer must accept a single parameter.");
                    }
                    if (fun.params[0].type == null or fun.params[0].type.? != T) {
                        @compileError("Expected `" ++ @typeName(T) ++ "` as parameter type, got `" ++ @typeName(fun.params[0].type) ++ "`");
                    }

                    return SelectIter(U){
                        .iter = this.iter,
                        .transformer = predicate,
                    };
                },
                .@"struct" => {
                    return .{
                        .iter = this.iter,
                        .transformer = predicate.what,
                    };
                },
                else => @compileError("Expected function or struct transformer, got " ++ @typeName(predicate)),
            }
        }

        pub fn any(const_this: *const This, predicate: anytype) bool {
            var this = @constCast(const_this);

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

test "Select" {
    const Item = struct {
        x: f32,
        y: f32,
        id: usize,
    };

    const items = [_]Item{
        .{ .x = 0.0, .y = 0.0, .id = 23 },
        .{ .x = 10.0, .y = 23.0, .id = 24 },
        .{ .x = 100.0, .y = 200.0, .id = 23 },

        .{ .x = 45.3, .y = 123.7, .id = 25 },
        .{ .x = 300.1, .y = 50.9, .id = 23 },
        .{ .x = 412.8, .y = 210.4, .id = 24 },
        .{ .x = 199.5, .y = 88.2, .id = 25 },
        .{ .x = 355.0, .y = 400.6, .id = 23 },
        .{ .x = 138.3, .y = 145.9, .id = 24 },
        .{ .x = 499.2, .y = 320.7, .id = 25 },

        .{ .x = 120.0, .y = 310.0, .id = 23 },
        .{ .x = 240.5, .y = 410.1, .id = 24 },
        .{ .x = 75.9, .y = 66.6, .id = 25 },
        .{ .x = 333.3, .y = 123.4, .id = 23 },
        .{ .x = 287.7, .y = 15.8, .id = 24 },
        .{ .x = 410.0, .y = 499.0, .id = 25 },
        .{ .x = 59.2, .y = 489.5, .id = 23 },
        .{ .x = 470.4, .y = 70.7, .id = 24 },
        .{ .x = 150.6, .y = 250.3, .id = 25 },
        .{ .x = 360.8, .y = 175.9, .id = 23 },
    };

    var slice_iter = SliceIter(Item).init(&items);
    var query = slice_iter.extend();

    const Point = struct { x: f32, y: f32 };
    var points = query.select(Point, struct {
        pub fn what(item: Item) Point {
            return .{
                .x = item.x,
                .y = item.y,
            };
        }
    });
    var points_query = points.extend();

    std.debug.print("Total number of points: {}\n", .{points_query.count()});

    try std.testing.expectEqual(items.len, points_query.count());

    const count = points_query.where(struct {
        pub fn what(p: Point) bool {
            return in_range(p.x, 0, 100) and in_range(p.y, 0, 100);
        }
        inline fn in_range(val: f32, min: f32, max: f32) bool {
            return min <= val and val <= max;
        }
    }).extend().count();

    std.debug.print("Total number of points within region: {}\n", .{count});

    try std.testing.expectEqual(count, 3);

    var items_of_type = query.where(struct {
        pub fn what(i: Item) bool {
            return i.id == 24 and i.x > 10 and i.x < 150 and i.x > 10 and i.y < 150;
        }
    }).extend().select(f32, struct {
        pub fn what(item: Item) f32 {
            return item.x * item.y;
        }
    }).extend();

    std.debug.print("Num Items of type 24 and in region: {}\n", .{items_of_type.count()});
    while (items_of_type.iter.next()) |item| {
        std.debug.print("  Area: {}\n", .{item});
    }
}
