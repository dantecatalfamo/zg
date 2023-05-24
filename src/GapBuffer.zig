const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const testing = std.testing;
const assert = std.debug.assert;

const init_gap_size = 20;

pub const GapBuffer = struct {
    buffer: std.ArrayList(u8),
    gap_start: usize,
    gap_end: usize,
    point_pos: usize,
    // XXX utf8: bool,

    pub fn init(allocator: mem.Allocator) !GapBuffer {
        var buffer = try std.ArrayList(u8).initCapacity(allocator, init_gap_size);
        buffer.expandToCapacity();
        return .{
            .buffer = buffer,
            .gap_start = 0,
            .gap_end = init_gap_size,
            .point_pos = 0,
            // XXX .utf8 = true,
        };
    }

    pub fn deinit(self: GapBuffer) void {
        self.buffer.deinit();
    }

    pub inline fn gap_size(self: GapBuffer) usize {
        return self.gap_end - self.gap_start;
    }

    pub inline fn length(self: GapBuffer) usize {
        return self.buffer.items.len - self.gap_size();
    }

    pub fn point(self: GapBuffer) usize {
        // XXX NOT UTF-8 AWARE
        assert(self.point_pos <= self.gap_start or self.point_pos >= self.gap_end);
        if (self.point_pos <= self.gap_start) {
            return self.point_pos;
        } else {
            return self.point_pos - self.gap_size();
        }
    }

    pub fn setPoint(self: *GapBuffer, position: usize) void {
        // XXX NOT UTF-8 AWARE!! Use std.unicode.Utf8View to set correctly
        if (position <= self.gap_start) {
            self.point_pos = position;
        } else if (position < self.length()) {
            self.point_pos = position + self.gap_size();
        } else {
            self.point_pos = self.length() + self.gap_size();
        }
    }

    pub fn format(self: GapBuffer, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_writer: anytype) !void {
        _ = options;
        _ = fmt;
        try out_writer.print("(len:{d} cap:{d})[b:{d} e:{d} p:{d} P:{d}] ", .{ self.length(), self.buffer.items.len, self.gap_start, self.gap_end, self.point_pos, self.point() });

        if (self.point_pos == self.gap_start and self.point_pos == self.gap_end) {
            try out_writer.print("{s}><[]{s}", .{ self.buffer.items[0..self.point_pos], self.buffer.items[self.point_pos..] });
            try out_writer.print("  /// {s}{s}", .{ self.buffer.items[0..self.gap_start], self.buffer.items[self.gap_end..] });
            return;
        }
        if (self.point_pos <= self.gap_start) {
            try out_writer.print("{s}><{s}", .{ self.buffer.items[0..self.point_pos], self.buffer.items[self.point_pos..self.gap_start]} );
        } else {
            try out_writer.print("{s}", .{ self.buffer.items[0..self.gap_start] });
        }
        try out_writer.writeByte('[');
        for (0..self.gap_size()) |_| {
            try out_writer.writeByte('_');
        }
        try out_writer.writeByte(']');
        if (self.point_pos >= self.gap_end) {
            try out_writer.print("{s}><{s}", .{ self.buffer.items[self.gap_end..self.point_pos], self.buffer.items[self.point_pos..] });
        } else {
            try out_writer.print("{s}", .{ self.buffer.items[self.gap_end..] });
        }
        try out_writer.print("  /// {s}{s}", .{ self.buffer.items[0..self.gap_start], self.buffer.items[self.gap_end..] });
    }

    /// XXX Doesn't validate utf8
    pub fn insert(self: *GapBuffer, bytes: []const u8) !void {
        self.moveGapToPoint();
        if (self.gap_size() > bytes.len) {
            self.insertAssumeCapacity(bytes);
        } else {
            try self.grow_gap(@max(bytes.len, self.length() / 64));
            self.insertAssumeCapacity(bytes);
        }
    }

    /// XXX Not utf8 aware
    pub fn deleteForward(self: *GapBuffer, bytes: usize) void {
        self.moveGapToPoint();
        self.gap_end = @min(self.gap_end + bytes, self.buffer.items.len);
    }

    /// XXX Not utf8 aware
    pub fn deleteBackward(self: *GapBuffer, bytes: usize) void {
        self.moveGapToPoint();
        self.gap_start = if (self.gap_start > bytes) self.gap_start - bytes else 0;
        self.point_pos = self.gap_start;
    }

    pub fn grow_gap(self: *GapBuffer, amount: usize) !void {
        if (amount == 0) {
            return;
        }
        const old_end = self.buffer.items.len;
        try self.buffer.resize(self.buffer.items.len + amount);
        const source = self.buffer.items[self.gap_end..old_end];
        var destination = self.buffer.items[self.buffer.items.len-source.len..];
        mem.copyBackwards(u8, destination, source);
        self.gap_end += amount;
    }

    fn moveGapToPoint(self: *GapBuffer) void {
        assert(self.point_pos <= self.gap_start or self.point_pos >= self.gap_end);
        if (self.point_pos == self.gap_start) {
            return;
        }
        if (self.point_pos == self.gap_end) {
            self.point_pos = self.gap_start;
            return;
        }
        if (self.point_pos < self.gap_start) {
            const size = self.gap_size();
            const source = self.buffer.items[self.point_pos..self.gap_start];
            var destination = self.buffer.items[self.gap_end-source.len..self.gap_end];
            mem.copyBackwards(u8, destination, source);
            self.gap_start = self.point_pos;
            self.gap_end = self.gap_start + size;
        } else {
            const size = self.gap_size();
            const moved_items = self.buffer.items[self.gap_end..self.point_pos];
            var destination = self.buffer.items[self.gap_start..self.gap_start+moved_items.len];
            mem.copyForwards(u8, destination, moved_items);
            self.gap_start = self.point_pos - size;
            self.gap_end = self.gap_start + size;
        }
    }

    /// Insert at point, assuming it's at the beginning of the gap,
    /// it's valid utf-8, and there's enough room.
    pub fn insertAssumeCapacity(self: *GapBuffer, text: []const u8) void {
        assert(text.len <= self.gap_size());
        @memcpy(self.buffer.items[self.gap_start..self.gap_start+text.len], text);
        self.gap_start += text.len;
        self.point_pos = self.gap_start;
    }

    pub fn write(self: *GapBuffer, bytes: []const u8) WriteError!usize {
        try self.insert(bytes);
        return bytes.len;
    }

    pub const Writer = std.io.Writer(*GapBuffer, WriteError, write);
    pub const WriteError = mem.Allocator.Error;

    pub fn writer(self: *GapBuffer) Writer {
        return .{ .context = self };
    }

    pub fn read(self: *GapBuffer, buffer: []u8) ReadError!usize {
        if (self.point_pos < self.gap_start) {
            const source_end = @min(self.gap_start, self.point_pos + buffer.len);
            const source = self.buffer.items[self.point_pos..source_end];
            @memcpy(buffer[0..source.len], source);
            self.point_pos += source.len;
            return source.len;
        } else {
            if (self.point_pos == self.gap_start) {
                self.point_pos = self.gap_end;
            }
            const source_end = @min(self.buffer.items.len, self.point_pos + buffer.len);
            const source = self.buffer.items[self.point_pos..source_end];
            @memcpy(buffer[0..source.len], source);
            self.point_pos += source.len;
            return source.len;
        }
    }

    const Reader = std.io.Reader(*GapBuffer, ReadError, read);
    const ReadError = error{};

    pub fn reader(self: *GapBuffer) Reader {
        return .{ .context = self };
    }

    pub const SeekableStream = std.io.SeekableStream(*GapBuffer, SeekError, GetSeekPosError, seekTo, seekBy, getPos, getEndPos);
    pub const SeekError = error{};
    pub const GetSeekPosError = error{};

    pub fn seekTo(self: *GapBuffer, pos: u64) SeekError!void {
        self.setPoint(pos);
    }

    pub fn seekBy(self: *GapBuffer, amt: i64) SeekError!void {
        const point_signed = @intCast(i64, self.point());
        const new_point = std.math.clamp(point_signed + amt, 0, self.length());
        self.setPoint(@intCast(usize, new_point));
        return;
    }

    pub fn getPos(self: *GapBuffer) GetSeekPosError!u64 {
        return self.point();
    }

    pub fn getEndPos(self: *GapBuffer) GetSeekPosError!u64 {
        return self.length();
    }

    pub fn seekableStream(self: *GapBuffer) SeekableStream {
        return .{ .context = self };
    }
};

test "debug printing" {
    var buf = try GapBuffer.init(testing.allocator);
    defer buf.deinit();
    std.debug.print("Buffer {}\n", .{ buf });
    buf.insertAssumeCapacity("12345");
    std.debug.print("Buffer {}\n", .{ buf });
    buf.setPoint(3);
    std.debug.print("Buffer {}\n", .{ buf });
    buf.moveGapToPoint();
    std.debug.print("Buffer {}\n", .{ buf });
    buf.moveGapToPoint();
    std.debug.print("Buffer {}\n", .{ buf });
    buf.insertAssumeCapacity("a");
    std.debug.print("Buffer {}\n", .{ buf });
    buf.setPoint(10);
    std.debug.print("Buffer {}\n", .{ buf });
    buf.moveGapToPoint();
    std.debug.print("Buffer {}\n", .{ buf });
    buf.insertAssumeCapacity("b");
    std.debug.print("Buffer {}\n", .{ buf });
    buf.setPoint(1);
    std.debug.print("Buffer {}\n", .{ buf });
    buf.moveGapToPoint();
    std.debug.print("Buffer {}\n", .{ buf });
    buf.insertAssumeCapacity("c");
    std.debug.print("Buffer {}\n", .{ buf });
    try buf.grow_gap(1);
    std.debug.print("Buffer {}\n", .{ buf });
    try buf.grow_gap(0);
    try buf.insert("longer text test!");
    std.debug.print("Buffer {}\n", .{ buf });
    buf.setPoint(buf.point() + 3);
    try buf.insert("lol");
    std.debug.print("Buffer {}\n", .{ buf });
    buf.deleteForward(1);
    std.debug.print("Buffer {}\n", .{ buf });
    buf.deleteBackward(5);
    std.debug.print("Buffer {}\n", .{ buf });
    try buf.writer().print("{s}", .{ "very long text printed!" });
    std.debug.print("Buffer {}\n", .{ buf });
    try buf.writer().print("{s}", .{ " hehe lol" });
    std.debug.print("Buffer {}\n", .{ buf });
    buf.setPoint(0);
    var read_test: [100]u8 = undefined;
    const n = try buf.reader().readAll(&read_test);
    std.debug.print("Read test: {d} {s}\n", .{ n, read_test[0..n] });
    const seek = buf.seekableStream();
    try seek.seekBy(-100);
    std.debug.print("Buffer {}\n", .{ buf });
    try seek.seekBy(20);
    std.debug.print("Buffer {}\n", .{ buf });
    std.debug.print("Curr: {d} End: {d}\n", .{ try seek.getPos(), try seek.getEndPos() });
    try seek.seekBy(100);
    std.debug.print("Buffer {}\n", .{ buf });
    try seek.seekTo(40);
    std.debug.print("Buffer {}\n", .{ buf });
}
