const std = @import("std");

pub fn Iter(comptime T: type) type {
    return struct {
        context: *anyopaque,
        vtable: VTable,

        pub const VTable = struct {
            next: *const fn (ctx: *anyopaque) ?T,
            index: *const fn (ctx: *anyopaque) Index,
            seek: *const fn (ctx: *anyopaque, index: Index) void,
            extend: *const fn (ctx: *anyopaque) Query(T),
        };

        pub fn next(this: @This()) ?T {
            return this.vtable.next(this.context);
        }

        pub fn index(this: @This()) Index {
            return this.vtable.index(this.context);
        }

        pub fn seek(this: @This(), pos: Index) void {
            return this.vtable.seek(this.context, pos);
        }

        pub fn extend(this: @This()) Query(T) {
            return this.vtable.extend(this.context);
        }
    };
}

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

        pub fn to_iter(this: *This) Iter(T) {
            return Iter(T){
                .context = this,
                .vtable = .{
                    .next = This.v_next,
                    .index = This.v_index,
                    .seek = This.v_seek,
                    .extend = This.v_extend,
                },
            };
        }

        fn v_next(this: *anyopaque) ?T {
            const this_ptr: *This = @ptrCast(@alignCast(this));
            return this_ptr.next();
        }

        fn v_index(this: *anyopaque) Index {
            const this_ptr: *This = @ptrCast(@alignCast(this));
            return @intCast(this_ptr.tell());
        }

        fn v_seek(this: *anyopaque, pos: Index) void {
            const this_ptr: *This = @ptrCast(@alignCast(this));
            return this_ptr.seek(@truncate(pos));
        }

        fn v_extend(this: *anyopaque) Query(T) {
            const this_ptr: *This = @ptrCast(@alignCast(this));
            return this_ptr.extend();
        }

        pub fn extend(this: *This) Query(T) {
            return Query(T).init(this.to_iter());
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

pub const Index = u128;

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

            fn v_index(this: *anyopaque) Index {
                const this_ptr: *@This() = @ptrCast(@alignCast(this));
                return this_ptr.iter.index();
            }

            fn v_seek(this: *anyopaque, pos: Index) void {
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

                pub fn v_index(this: *const anyopaque) Index {
                    var this_ptr: *@This() = @ptrCast(@alignCast(@constCast(this)));
                    return this_ptr.iter.index();
                }

                pub fn v_seek(this: *anyopaque, pos: Index) void {
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

        pub fn JoinIter(comptime V: type, comptime U: type, comptime predicate: fn (T, U) bool, comptime transformer: fn (T, U) V) type {
            return struct {
                outer: Iter(T),
                inner: Iter(U),

                pub fn next(this: *@This()) ?V {
                    while (this.outer.next()) |o| {
                        while (this.inner.next()) |i| {
                            if (predicate(o, i)) {
                                return transformer(o, i);
                            }
                        }
                        this.inner.seek(0);
                        std.debug.print(@typeName(U) ++ " has reset and " ++ @typeName(T) ++ " scan will continue\n", .{});
                    }
                    return null;
                }

                pub fn index(this: *@This()) Index {
                    const outer: u64 = @truncate(this.outer.index());
                    const inner: u64 = @truncate(this.inner.index());

                    const HALF_INDEX = @typeInfo(Index).int.bits / 2;

                    return (@as(Index, @intCast(outer)) << HALF_INDEX) | @as(Index, @intCast(inner));
                }

                pub fn seek(this: *@This(), pos: Index) void {
                    const HALF_INDEX = @typeInfo(Index).int.bits / 2;

                    const inner: u64 = @truncate(pos);
                    const outer: u64 = @truncate(pos >> HALF_INDEX);

                    this.inner.seek(inner);
                    this.outer.seek(outer);
                }

                pub fn extend(this: *const @This()) Query(V) {
                    return Query(V).init(this.to_iter());
                }

                fn v_extend(this: *anyopaque) Query(V) {
                    return extend(@ptrCast(@alignCast(this)));
                }
                fn v_seek(this: *anyopaque, pos: Index) void {
                    return seek(@ptrCast(@alignCast(this)), pos);
                }
                fn v_index(this: *anyopaque) Index {
                    return index(@ptrCast(@alignCast(this)));
                }
                fn v_next(this: *anyopaque) ?V {
                    return next(@ptrCast(@alignCast(this)));
                }

                pub fn to_iter(this: *const @This()) Iter(V) {
                    return .{
                        .context = @constCast(this),
                        .vtable = .{
                            .extend = @This().v_extend,
                            .index = @This().v_index,
                            .next = @This().v_next,
                            .seek = @This().v_seek,
                        },
                    };
                }
            };
        }

        fn JoinIterType(V: type, U: type, comptime predicate: anytype, comptime transformer: anytype) type {
            const pr_info = if (@TypeOf(predicate) == type) @typeInfo(predicate) else @typeInfo(@TypeOf(predicate));
            const tr_info = if (@TypeOf(transformer) == type) @typeInfo(transformer) else @typeInfo(@TypeOf(transformer));

            const predFn = switch (pr_info) {
                .@"fn" => |fun| fun,
                .@"struct" => predicate.what,
                else => @compileError("Unexpected predicate type: " ++ @typeName(predicate)),
            };

            const tranFn = switch (tr_info) {
                .@"fn" => |fun| fun,
                .@"struct" => transformer.what,
                else => @compileError("Unexpected transformer type: " ++ @typeName(transformer)),
            };

            return JoinIter(V, U, predFn, tranFn);
        }

        pub fn join(
            this: *const This,
            comptime JoinedType: type,
            comptime InnerType: type,
            inner: Iter(InnerType),
            comptime predicate: anytype,
            comptime transformer: anytype,
        ) JoinIterType(JoinedType, InnerType, predicate, transformer) {
            return JoinIterType(JoinedType, InnerType, predicate, transformer){
                .outer = this.iter,
                .inner = inner,
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

        pub fn distinct(this: *const This, allocator: std.mem.Allocator) ![]T {
            var seen = std.AutoHashMap(T, void).init(allocator);
            defer seen.deinit();

            var num: usize = 0;
            this.iter.seek(0);
            while (this.iter.next()) |i| {
                if (seen.contains(i)) continue;
                try seen.put(i, void{});
                num += 1;
            }

            const buffer = try allocator.alloc(T, num);
            errdefer allocator.free(buffer);

            seen.clearRetainingCapacity();
            var i: usize = 0;

            this.iter.seek(0);
            while (this.iter.next()) |v| {
                if (seen.contains(v)) continue;
                try seen.put(v, void{});

                buffer[i] = v;
                i += 1;
            }

            return buffer;
        }

        pub fn distinct_order_by(this: *const This, allocator: std.mem.Allocator, selector: anytype) ![]T {
            const info = if (@TypeOf(selector) == type) @typeInfo(selector) else @typeInfo(@TypeOf(selector));

            const selectFn = switch (info) {
                .@"fn" => |fun| fun,
                .@"struct" => selector.what,
                else => @compileError("Unexpected selector type: " ++ @typeName(selector)),
            };

            const fnInfo = @typeInfo(@TypeOf(selectFn)).@"fn";

            if (fnInfo.return_type == null) {
                @compileError("`order_by` selector must return a value to sort by");
            }
            if (fnInfo.params.len != 1) {
                @compileError("`order_by` selector must accept a single parameter");
            }
            if (fnInfo.params[0].type == null or fnInfo.params[0].type.? != T) {
                @compileError("Expected `" ++ @typeName(T) ++ "` parameter, got `" ++ @typeName(fnInfo.params[0].type) ++ "`");
            }

            const buffer = try this.distinct(allocator);
            errdefer allocator.free(buffer);

            const Compare = struct {
                pub fn cmp(_: void, a: T, b: T) bool {
                    return selectFn(a) < selectFn(b);
                }
            };

            std.sort.block(T, buffer, void{}, Compare.cmp);
            return buffer;
        }

        pub fn order_by(this: *const This, allocator: std.mem.Allocator, selector: anytype) ![]T {
            const info = if (@TypeOf(selector) == type) @typeInfo(selector) else @typeInfo(@TypeOf(selector));

            const selectFn = switch (info) {
                .@"fn" => |fun| fun,
                .@"struct" => selector.what,
                else => @compileError("Unexpected selector type: " ++ @typeName(selector)),
            };

            const fnInfo = @typeInfo(@TypeOf(selectFn)).@"fn";

            if (fnInfo.return_type == null) {
                @compileError("`order_by` selector must return a value to sort by");
            }
            if (fnInfo.params.len != 1) {
                @compileError("`order_by` selector must accept a single parameter");
            }
            if (fnInfo.params[0].type == null or fnInfo.params[0].type.? != T) {
                @compileError("Expected `" ++ @typeName(T) ++ "` parameter, got `" ++ @typeName(fnInfo.params[0].type) ++ "`");
            }

            return try this.order_by_impl(allocator, fnInfo.return_type.?, selectFn);
        }

        fn order_by_impl(this: *const This, allocator: std.mem.Allocator, comptime F: type, comptime selector: fn (T) F) ![]T {
            const num = this.count();
            const buffer = try allocator.alloc(T, num);
            errdefer allocator.free(buffer);

            var i: usize = 0;
            this.iter.seek(0);
            while (this.iter.next()) |val| : (i += 1) {
                buffer[i] = val;
            }

            const Compare = struct {
                pub fn cmp(_: void, a: T, b: T) bool {
                    return selector(a) < selector(b);
                }
            };

            std.sort.block(T, buffer, void{}, Compare.cmp);
            return buffer;
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

test "Order By" {
    const items = [_]u32{
        12, 5, 16, 23, 54, 76, 36, 66, 33,
    };
    var sliceIter = SliceIter(u32).init(&items);
    var query = Query(u32).init(sliceIter.to_iter());

    const sorted = try query.order_by(std.testing.allocator, struct {
        pub fn what(a: u32) u32 {
            return a;
        }
    });
    defer std.testing.allocator.free(sorted);

    try std.testing.expectEqual(items.len, sorted.len);
    try std.testing.expectEqualSlices(u32, &.{
        5, 12, 16, 23, 33, 36, 54, 66, 76,
    }, sorted);
}

test "Distinct" {
    const items = [_]u32{
        10, 10, 11, 11, 12, 12, 13, 13, 14, 14,
    };
    var sliceIter = SliceIter(u32).init(&items);
    var query = Query(u32).init(sliceIter.to_iter());
    const distinct_items = try query.distinct(std.testing.allocator);
    defer std.testing.allocator.free(distinct_items);

    try std.testing.expectEqual(5, distinct_items.len);
    try std.testing.expectEqualSlices(u32, &.{ 10, 11, 12, 13, 14 }, distinct_items);
}

test "Order By Distinct" {
    const items = [_]u32{
        12, 5, 16, 23, 54, 5, 76, 36, 36, 66, 33,
    };
    var sliceIter = SliceIter(u32).init(&items);
    var query = Query(u32).init(sliceIter.to_iter());

    const sorted = try query.distinct_order_by(std.testing.allocator, struct {
        pub fn what(a: u32) u32 {
            return a;
        }
    });
    defer std.testing.allocator.free(sorted);

    try std.testing.expectEqual(items.len - 2, sorted.len);
    try std.testing.expectEqualSlices(u32, &.{
        5, 12, 16, 23, 33, 36, 54, 66, 76,
    }, sorted);
}

test "Order By Structs" {
    const Object = struct {
        x: f32,
        y: f32,
        hp: f32,
    };
    const AreaHp = struct {
        area: f32,
        hp: f32,
    };

    const objects = [_]Object{
        .{
            .x = 10,
            .y = 11,
            .hp = 0.1,
        },
        .{
            .x = 11,
            .y = 500,
            .hp = 1.0,
        },
        .{
            .x = 499,
            .y = 200,
            .hp = 100,
        },
        .{
            .x = 390,
            .y = 20,
            .hp = 4,
        },
        .{
            .x = 500,
            .y = 10,
            .hp = 2,
        },
    };
    var slit = SliceIter(Object).init(&objects);
    var query = slit.extend();

    const areasSorted = try query.select(AreaHp, struct {
        pub fn what(obj: Object) AreaHp {
            return .{
                .area = obj.x * obj.y,
                .hp = obj.hp,
            };
        }
    }).extend().order_by(std.testing.allocator, struct {
        pub fn what(a: AreaHp) f32 {
            return a.hp;
        }
    });
    defer std.testing.allocator.free(areasSorted);

    try std.testing.expectEqualSlices(AreaHp, &.{
        .{
            .area = 110,
            .hp = 0.1,
        },
        .{
            .area = 11 * 500,
            .hp = 1.0,
        },
        .{
            .area = 5000,
            .hp = 2,
        },
        .{
            .area = 390 * 20,
            .hp = 4,
        },
        .{
            .area = 499 * 200,
            .hp = 100,
        },
    }, areasSorted);
}

test "Join" {
    const Roles = enum {
        Guest,
        User,
        Admin,
    };

    const Account = struct {
        Id: u32,
        UserName: []const u8,
        PasswordHash: []const u8,
        PasswordSalt: []const u8,
        Role: Roles,
    };

    const User = struct {
        Id: u32,
        AccountID: u32,
        FirstName: []const u8,
        LastName: []const u8,
        Address: []const u8,
        Email: []const u8,
        Phone: []const u8,
    };

    const Post = struct {
        Id: u32,
        Title: []const u8,
        Body: []const u8,
        EntryUserID: u32,
    };

    const accounts = [_]Account{
        .{ .Id = 1, .UserName = "guest", .PasswordHash = "hash1", .PasswordSalt = "salt1", .Role = .Guest },
        .{ .Id = 2, .UserName = "alice", .PasswordHash = "hash2", .PasswordSalt = "salt2", .Role = .User },
        .{ .Id = 3, .UserName = "bob", .PasswordHash = "hash3", .PasswordSalt = "salt3", .Role = .User },
        .{ .Id = 4, .UserName = "carol", .PasswordHash = "hash4", .PasswordSalt = "salt4", .Role = .User },
        .{ .Id = 5, .UserName = "dave", .PasswordHash = "hash5", .PasswordSalt = "salt5", .Role = .User },
        .{ .Id = 6, .UserName = "admin", .PasswordHash = "hash6", .PasswordSalt = "salt6", .Role = .Admin },
    };

    const users = [_]User{
        .{ .Id = 1, .AccountID = 2, .FirstName = "Alice", .LastName = "Anderson", .Address = "123 Maple St", .Email = "alice@example.com", .Phone = "111-1111" },
        .{ .Id = 2, .AccountID = 3, .FirstName = "Bob", .LastName = "Brown", .Address = "456 Oak St", .Email = "bob@example.com", .Phone = "222-2222" },
        .{ .Id = 3, .AccountID = 4, .FirstName = "Carol", .LastName = "Clark", .Address = "789 Pine St", .Email = "carol@example.com", .Phone = "333-3333" },
        .{ .Id = 4, .AccountID = 5, .FirstName = "Dave", .LastName = "Davis", .Address = "101 Elm St", .Email = "dave@example.com", .Phone = "444-4444" },
        .{ .Id = 5, .AccountID = 6, .FirstName = "Eve", .LastName = "Evans", .Address = "202 Birch St", .Email = "eve@example.com", .Phone = "555-5555" },
    };

    const posts = [_]Post{
        .{ .Id = 1, .Title = "Hello", .Body = "First post", .EntryUserID = 1 }, // Alice
        .{ .Id = 2, .Title = "My Day", .Body = "It was good", .EntryUserID = 1 }, // Alice
        .{ .Id = 3, .Title = "Zig Tips", .Body = "Use comptime!", .EntryUserID = 2 }, // Bob
        .{ .Id = 4, .Title = "Cooking", .Body = "Love pasta", .EntryUserID = 3 }, // Carol
        .{ .Id = 5, .Title = "Work Log", .Body = "Busy week", .EntryUserID = 5 }, // Admin Eve
    };

    const PostUserData = struct {
        UserName: []const u8,
        Title: []const u8,
        Body: []const u8,
    };

    var accountIter = SliceIter(Account).init(&accounts);
    var userIter = SliceIter(User).init(&users);
    var postIter = SliceIter(Post).init(&posts);

    var data = accountIter.extend()
        .where(struct {
            pub fn what(a: Account) bool {
                return a.Role != .Guest;
            }
        }).extend()
        .join(User, User, userIter.to_iter(), struct {
            pub fn what(a: Account, u: User) bool {
                std.debug.print("a) {} == {}\n", .{ a.Id, u.AccountID });
                return a.Id == u.AccountID;
            }
        }, struct {
            pub fn what(a: Account, u: User) User {
                _ = a;
                return u;
            }
        }).extend()
        .join(PostUserData, Post, postIter.to_iter(), struct {
        pub fn what(u: User, p: Post) bool {
            std.debug.print("b) {} == {}\n", .{ u.Id, p.EntryUserID });
            return u.Id == p.EntryUserID;
        }
    }, struct {
        pub fn what(u: User, p: Post) PostUserData {
            return .{
                .UserName = u.FirstName,
                .Title = p.Title,
                .Body = p.Body,
            };
        }
    });
    while (data.next()) |pdata| {
        std.debug.print("{s}: {s}\n\t{s}\n~~~~~~~~~~~~~~~~~~~~\n", .{
            pdata.UserName,
            pdata.Title,
            pdata.Body,
        });
    }
}
