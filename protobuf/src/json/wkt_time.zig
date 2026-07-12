//! Calendar math and RFC3339/duration string conversion for the
//! `google.protobuf.Timestamp` and `google.protobuf.Duration` ProtoJSON
//! representations. Pure logic, independent of the JSON tree machinery in
//! `to_json.zig`/`from_json.zig`.
//!
//! See http://howardhinnant.github.io/date_algorithms.html for reference
//! implementation

const std = @import("std");

// The values are checked in a unit test.
pub const timestamp_min_seconds: i64 = -62135596800; // 0001-01-01T00:00:00Z
pub const timestamp_max_seconds: i64 = 253402300799; // 9999-12-31T23:59:59Z

// The values are part of the protobuf spec, see `google/protobuf/duration.proto`.
pub const duration_min_seconds: i64 = -315576000000;
pub const duration_max_seconds: i64 = 315576000000;

/// Returns number of days since civil 1970-01-01.  Negative values indicate
///    days prior to 1970-01-01.
/// Preconditions:  y-m-d represents a date in the civil (Gregorian) calendar
///                 m is in [1, 12]
///                 d is in [1, last_day_of_month(y, m)]
///                 y is "approximately" in
///                   [numeric_limits<Int>::min()/366, numeric_limits<Int>::max()/366]
///                 Exact range of validity is:
///                 [civil_from_days(numeric_limits<Int>::min()),
///                  civil_from_days(numeric_limits<Int>::max()-719468)]
fn daysFromCivil(y_in: i64, m: i64, d: i64) i64 {
    const y: i64 = y_in - @as(i64, if (m <= 2) 1 else 0);
    const era: i64 = @divTrunc(if (y >= 0) y else y - 399, 400);
    const yoe: i64 = y - era * 400; // [0, 399]
    const mp: i64 = m + @as(i64, if (m > 2) -3 else 9); // [0, 11]
    const doy: i64 = @divFloor(153 * mp + 2, 5) + d - 1; // [0, 365]
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy; // [0, 146096]
    return era * 146097 + doe - 719468;
}

/// Inverse of `daysFromCivil`.
fn civilFromDays(z_in: i64) struct { year: i64, month: u32, day: u32 } {
    const z = z_in + 719468;
    const era: i64 = @divTrunc(if (z >= 0) z else z - 146096, 146097);
    const doe: i64 = z - era * 146097; // [0, 146096]
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365); // [0, 399]
    const y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100)); // [0, 365]
    const mp: i64 = @divFloor(5 * doy + 2, 153); // [0, 11]
    const d: i64 = doy - @divFloor(153 * mp + 2, 5) + 1; // [1, 31]
    const m: i64 = mp + (if (mp < 10) @as(i64, 3) else @as(i64, -9)); // [1, 12]
    return .{ .year = y + @as(i64, if (m <= 2) 1 else 0), .month = @intCast(m), .day = @intCast(d) };
}

fn isLeapYear(year: i64) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

fn daysInMonth(year: i64, month: u32) u32 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) @as(u32, 29) else 28,
        else => 0,
    };
}

fn validateTimestampRange(seconds: i64, nanos: i32) !void {
    if (seconds < timestamp_min_seconds or seconds > timestamp_max_seconds) {
        return error.TimestampOutOfRange;
    }
    if (nanos < 0 or nanos > 999_999_999) {
        return error.TimestampNanosOutOfRange;
    }
}

fn validateDurationRange(seconds: i64, nanos: i32) !void {
    if (seconds < duration_min_seconds or seconds > duration_max_seconds) {
        return error.DurationOutOfRange;
    }
    if (nanos < -999_999_999 or nanos > 999_999_999) {
        return error.DurationNanosOutOfRange;
    }
    if (seconds != 0 and nanos != 0 and (seconds < 0) != (nanos < 0)) {
        return error.DurationNanosSignMismatch;
    }
}

/// Returns "" if n==0, otherwise ".NNN"/".NNNNNN"/".NNNNNNNNN" using the
/// smallest digit count (3, 6, or 9) that exactly represents n. `n` must be
/// in [0, 999_999_999]. `buf` must have length >= 10.
fn formatFracSeconds(buf: []u8, n: u32) []const u8 {
    if (n == 0) return "";
    if (n % 1_000_000 == 0) return std.fmt.bufPrint(buf, ".{d:0>3}", .{n / 1_000_000}) catch unreachable;
    if (n % 1_000 == 0) return std.fmt.bufPrint(buf, ".{d:0>6}", .{n / 1_000}) catch unreachable;
    return std.fmt.bufPrint(buf, ".{d:0>9}", .{n}) catch unreachable;
}

/// Formats a Timestamp as RFC3339 text (e.g. "1972-01-01T10:00:20.021Z")
/// into `buf` (recommend a `[40]u8` stack buffer) and returns the slice.
pub fn formatTimestamp(buf: []u8, seconds: i64, nanos: i32) ![]const u8 {
    try validateTimestampRange(seconds, nanos);

    const days = @divFloor(seconds, 86400);
    const secs_of_day = @mod(seconds, 86400);
    const ymd = civilFromDays(days);
    const hour: u32 = @intCast(@divFloor(secs_of_day, 3600));
    const minute: u32 = @intCast(@divFloor(@mod(secs_of_day, 3600), 60));
    const sec: u32 = @intCast(@mod(secs_of_day, 60));

    var frac_buf: [10]u8 = undefined;
    const frac = formatFracSeconds(&frac_buf, @intCast(nanos));

    // Cast the (always non-negative, range-validated) year to unsigned:
    // Zig's `{d:0>N}` formatting prepends an explicit '+' for positive
    // *signed* integers when a width is given, which we don't want here.
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}{s}Z", .{
        @as(u32, @intCast(ymd.year)), ymd.month, ymd.day, hour, minute, sec, frac,
    }) catch unreachable;
}

/// Formats a Duration as e.g. "3s" / "3.000001s" / "-0.5s" into `buf`
/// (recommend a `[40]u8` stack buffer) and returns the slice.
pub fn formatDuration(buf: []u8, seconds: i64, nanos: i32) ![]const u8 {
    try validateDurationRange(seconds, nanos);

    const negative = seconds < 0 or nanos < 0;
    const abs_seconds: u64 = @abs(seconds);
    const abs_nanos: u32 = @abs(nanos);

    var frac_buf: [10]u8 = undefined;
    const frac = formatFracSeconds(&frac_buf, abs_nanos);

    return std.fmt.bufPrint(buf, "{s}{d}{s}s", .{
        if (negative) "-" else "", abs_seconds, frac,
    }) catch unreachable;
}

/// Parses up to 9 fractional-second digits (e.g. from after a `.` in a
/// timestamp or duration string) into a nanosecond count in [0, 999_999_999].
fn parseFracDigits(digits: []const u8) !u32 {
    if (digits.len == 0 or digits.len > 9) return error.InvalidJson;
    for (digits) |c| {
        if (c < '0' or c > '9') return error.InvalidJson;
    }
    var n: u32 = 0;
    for (digits) |c| {
        n = n * 10 + (c - '0');
    }
    var i: usize = digits.len;
    while (i < 9) : (i += 1) {
        n *= 10;
    }
    return n;
}

fn parseDigits(comptime T: type, s: []const u8) !T {
    for (s) |c| {
        if (c < '0' or c > '9') return error.InvalidJson;
    }
    return std.fmt.parseInt(T, s, 10) catch error.InvalidJson;
}

/// Parses an RFC3339 timestamp string, e.g. "1972-01-01T10:00:20.021Z" or
/// "1972-01-01T10:00:20-05:00".
pub fn parseTimestamp(s: []const u8) !struct { seconds: i64, nanos: i32 } {
    if (s.len < 20) return error.InvalidJson;
    if (s[4] != '-' or s[7] != '-' or s[10] != 'T' or s[13] != ':' or s[16] != ':') {
        return error.InvalidJson;
    }

    const year = try parseDigits(i64, s[0..4]);
    const month = try parseDigits(u32, s[5..7]);
    const day = try parseDigits(u32, s[8..10]);
    const hour = try parseDigits(i64, s[11..13]);
    const minute = try parseDigits(i64, s[14..16]);
    const second = try parseDigits(i64, s[17..19]);

    if (month < 1 or month > 12) return error.InvalidJson;
    if (day < 1 or day > daysInMonth(year, month)) return error.InvalidJson;
    if (hour < 0 or hour > 23) return error.InvalidJson;
    if (minute < 0 or minute > 59) return error.InvalidJson;
    if (second < 0 or second > 59) return error.InvalidJson;

    var rest = s[19..];

    var nanos: u32 = 0;
    if (rest.len > 0 and rest[0] == '.') {
        const frac_end = blk: {
            var i: usize = 1;
            while (i < rest.len and rest[i] >= '0' and rest[i] <= '9') : (i += 1) {}
            break :blk i;
        };
        nanos = try parseFracDigits(rest[1..frac_end]);
        rest = rest[frac_end..];
    }

    var offset_seconds: i64 = 0;
    if (rest.len == 1 and rest[0] == 'Z') {
        offset_seconds = 0;
    } else if (rest.len == 6 and (rest[0] == '+' or rest[0] == '-') and rest[3] == ':') {
        const offset_hour = try parseDigits(i64, rest[1..3]);
        const offset_minute = try parseDigits(i64, rest[4..6]);
        if (offset_hour > 23 or offset_minute > 59) return error.InvalidJson;
        const magnitude = offset_hour * 3600 + offset_minute * 60;
        offset_seconds = if (rest[0] == '-') -magnitude else magnitude;
    } else {
        return error.InvalidJson;
    }

    const days = daysFromCivil(year, month, day);
    const seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset_seconds;

    try validateTimestampRange(seconds, @intCast(nanos));

    return .{ .seconds = seconds, .nanos = @intCast(nanos) };
}

/// Parses a Duration string, e.g. "3s" / "3.000001s" / "-0.5s".
pub fn parseDuration(s: []const u8) !struct { seconds: i64, nanos: i32 } {
    if (s.len == 0 or s[s.len - 1] != 's') return error.InvalidJson;
    var body = s[0 .. s.len - 1];

    var negative = false;
    if (body.len > 0 and body[0] == '-') {
        negative = true;
        body = body[1..];
    }

    const dot_index = std.mem.indexOfScalar(u8, body, '.');
    const int_part = if (dot_index) |i| body[0..i] else body;
    if (int_part.len == 0) return error.InvalidJson;

    const abs_seconds = try parseDigits(i64, int_part);

    var abs_nanos: u32 = 0;
    if (dot_index) |i| {
        abs_nanos = try parseFracDigits(body[i + 1 ..]);
    }

    const seconds: i64 = if (negative) -abs_seconds else abs_seconds;
    const nanos: i32 = if (negative) -@as(i32, @intCast(abs_nanos)) else @intCast(abs_nanos);

    try validateDurationRange(seconds, nanos);

    return .{ .seconds = seconds, .nanos = nanos };
}

test "timestamp constants" {
    try std.testing.expectEqual(timestamp_min_seconds, (try parseTimestamp("0001-01-01T00:00:00Z")).seconds);
    try std.testing.expectEqual(timestamp_max_seconds, (try parseTimestamp("9999-12-31T23:59:59Z")).seconds);
}

test "daysFromCivil epoch sanity" {
    try std.testing.expectEqual(@as(i64, 0), daysFromCivil(1970, 1, 1));
    try std.testing.expectEqual(@as(i64, 1), daysFromCivil(1970, 1, 2));
    try std.testing.expectEqual(@as(i64, -1), daysFromCivil(1969, 12, 31));
}

test "daysFromCivil / civilFromDays round trip" {
    const dates = [_]struct { y: i64, m: u32, d: u32 }{
        .{ .y = 1970, .m = 1, .d = 1 },
        .{ .y = 1969, .m = 12, .d = 31 },
        .{ .y = 1, .m = 1, .d = 1 },
        .{ .y = 9999, .m = 12, .d = 31 },
        .{ .y = 2000, .m = 2, .d = 29 }, // leap century year
        .{ .y = 1900, .m = 2, .d = 28 }, // non-leap century year (no Feb 29)
        .{ .y = 2024, .m = 2, .d = 29 },
        .{ .y = -100, .m = 6, .d = 15 },
        .{ .y = 1, .m = 3, .d = 1 },
    };
    for (dates) |date| {
        const days = daysFromCivil(date.y, date.m, date.d);
        const back = civilFromDays(days);
        try std.testing.expectEqual(date.y, back.year);
        try std.testing.expectEqual(date.m, back.month);
        try std.testing.expectEqual(date.d, back.day);
    }
}

test "isLeapYear" {
    try std.testing.expect(isLeapYear(2000));
    try std.testing.expect(!isLeapYear(1900));
    try std.testing.expect(isLeapYear(2024));
    try std.testing.expect(!isLeapYear(2023));
    try std.testing.expect(isLeapYear(4));
}

test "formatTimestamp epoch" {
    var buf: [40]u8 = undefined;
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", try formatTimestamp(&buf, 0, 0));
}

test "formatTimestamp fractional digit widths" {
    var buf: [40]u8 = undefined;
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", try formatTimestamp(&buf, 0, 0));
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.500Z", try formatTimestamp(&buf, 0, 500_000_000));
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.000001Z", try formatTimestamp(&buf, 0, 1_000));
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.000000001Z", try formatTimestamp(&buf, 0, 1));
}

test "formatTimestamp example from spec" {
    var buf: [40]u8 = undefined;
    // 15.01 seconds past 01:30 UTC on January 15, 2017.
    const days = daysFromCivil(2017, 1, 15);
    const seconds = days * 86400 + 1 * 3600 + 30 * 60 + 15;
    const s = try formatTimestamp(&buf, seconds, 10_000_000);
    try std.testing.expectEqualStrings("2017-01-15T01:30:15.010Z", s);
}

test "formatTimestamp pre-1970" {
    var buf: [40]u8 = undefined;
    try std.testing.expectEqualStrings("1969-12-31T23:59:59Z", try formatTimestamp(&buf, -1, 0));
    try std.testing.expectEqualStrings("0001-01-01T00:00:00Z", try formatTimestamp(&buf, timestamp_min_seconds, 0));
    try std.testing.expectEqualStrings("9999-12-31T23:59:59Z", try formatTimestamp(&buf, timestamp_max_seconds, 0));
}

test "formatTimestamp out of range" {
    var buf: [40]u8 = undefined;
    try std.testing.expectError(error.TimestampOutOfRange, formatTimestamp(&buf, timestamp_min_seconds - 1, 0));
    try std.testing.expectError(error.TimestampOutOfRange, formatTimestamp(&buf, timestamp_max_seconds + 1, 0));
    try std.testing.expectError(error.TimestampNanosOutOfRange, formatTimestamp(&buf, 0, -1));
    try std.testing.expectError(error.TimestampNanosOutOfRange, formatTimestamp(&buf, 0, 1_000_000_000));
}

test "parseTimestamp round trip" {
    const cases = [_][]const u8{
        "1970-01-01T00:00:00Z",
        "1970-01-01T00:00:00.500Z",
        "1970-01-01T00:00:00.000001Z",
        "1970-01-01T00:00:00.000000001Z",
        "0001-01-01T00:00:00Z",
        "9999-12-31T23:59:59Z",
        "1969-12-31T23:59:59Z",
    };
    for (cases) |case| {
        const parsed = try parseTimestamp(case);
        var buf: [40]u8 = undefined;
        try std.testing.expectEqualStrings(case, try formatTimestamp(&buf, parsed.seconds, parsed.nanos));
    }
}

test "parseTimestamp with timezone offsets" {
    const positive = try parseTimestamp("2017-01-15T09:30:15Z");
    const with_offset = try parseTimestamp("2017-01-15T01:30:15-08:00");
    try std.testing.expectEqual(positive.seconds, with_offset.seconds);

    const neg_offset = try parseTimestamp("2017-01-15T13:30:15+04:00");
    try std.testing.expectEqual(positive.seconds, neg_offset.seconds);
}

test "parseTimestamp rejects invalid input" {
    try std.testing.expectError(error.InvalidJson, parseTimestamp("not-a-timestamp"));
    try std.testing.expectError(error.InvalidJson, parseTimestamp("2017-13-15T01:30:15Z")); // bad month
    try std.testing.expectError(error.InvalidJson, parseTimestamp("2017-02-29T01:30:15Z")); // non-leap Feb 29
    try std.testing.expectError(error.InvalidJson, parseTimestamp("2017-01-15T01:30:60Z")); // leap second
    try std.testing.expectError(error.InvalidJson, parseTimestamp("2017-01-15T01:30:15.0000000001Z")); // too many frac digits
}

test "formatDuration basic" {
    var buf: [40]u8 = undefined;
    try std.testing.expectEqualStrings("3s", try formatDuration(&buf, 3, 0));
    try std.testing.expectEqualStrings("3.000001s", try formatDuration(&buf, 3, 1_000));
    try std.testing.expectEqualStrings("3.000000001s", try formatDuration(&buf, 3, 1));
    try std.testing.expectEqualStrings("0s", try formatDuration(&buf, 0, 0));
}

test "formatDuration negative" {
    var buf: [40]u8 = undefined;
    try std.testing.expectEqualStrings("-5.500s", try formatDuration(&buf, -5, -500_000_000));
    try std.testing.expectEqualStrings("-0.500s", try formatDuration(&buf, 0, -500_000_000));
}

test "formatDuration rejects sign mismatch and out of range" {
    var buf: [40]u8 = undefined;
    try std.testing.expectError(error.DurationNanosSignMismatch, formatDuration(&buf, 5, -1));
    try std.testing.expectError(error.DurationNanosSignMismatch, formatDuration(&buf, -5, 1));
    try std.testing.expectError(error.DurationOutOfRange, formatDuration(&buf, duration_max_seconds + 1, 0));
    try std.testing.expectError(error.DurationOutOfRange, formatDuration(&buf, duration_min_seconds - 1, 0));
    try std.testing.expectError(error.DurationNanosOutOfRange, formatDuration(&buf, 0, 1_000_000_000));
}

test "parseDuration round trip" {
    const cases = [_][]const u8{
        "3s",
        "3.000001s",
        "3.000000001s",
        "0s",
        "-5.500s",
        "-0.500s",
    };
    for (cases) |case| {
        const parsed = try parseDuration(case);
        var buf: [40]u8 = undefined;
        try std.testing.expectEqualStrings(case, try formatDuration(&buf, parsed.seconds, parsed.nanos));
    }
}

test "parseDuration rejects invalid input" {
    try std.testing.expectError(error.InvalidJson, parseDuration("s"));
    try std.testing.expectError(error.InvalidJson, parseDuration("-s"));
    try std.testing.expectError(error.InvalidJson, parseDuration(".5s"));
    try std.testing.expectError(error.InvalidJson, parseDuration("5"));
    try std.testing.expectError(error.InvalidJson, parseDuration("5.0000000001s"));
}
