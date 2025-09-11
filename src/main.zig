const std = @import("std");
const query = @import("query");

pub fn main() !void {
    const in = std.io.getStdIn().reader();
    const out = std.io.getStdOut().writer();

    var stdin = std.io.bufferedReader(in);
    var stdout = std.io.bufferedWriter(out);

    var raw_buffer = [_]u8{0} ** 4096;
    var buffer = [_]u32{0} ** 32;

    _ = try stdout.write("Up to 32 numbers: ");
    try stdout.flush();
    const read_count = try stdin.read(&raw_buffer);

    var index: usize = 0;
    var iter = std.mem.splitAny(u8, raw_buffer[0..read_count], " \n\r");
    while (iter.next()) |what| {
        if (what.len == 0) continue;

        if (index >= buffer.len) {
            std.debug.print("Too many numbers entered. The rest will be ignored.\n", .{});
            break;
        }

        buffer[index] = std.fmt.parseInt(u32, what, 10) catch {
            std.debug.print("`{s}` is not a valid number!", .{what});
            return error.InvalidSequence;
        };
        index += 1;
    }

    try query_inter(buffer[0..index]);
}

fn query_inter(slice: []usize) void {
    _ = slice;
}
