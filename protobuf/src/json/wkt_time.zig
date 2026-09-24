//! Calendar math and RFC3339/duration string conversion for the
//! `google.protobuf.Timestamp` and `google.protobuf.Duration` ProtoJSON
//! representations. Pure logic, independent of the JSON tree machinery in
//! `to_json.zig`/`from_json.zig`.
//!
//! See http://howardhinnant.github.io/date_algorithms.html for the reference
//! calendar algorithms.

const std = @import("std");

// The values are checked in a unit test.
pub const timestamp_min_seconds: i64 = -62135596800; // 0001-01-01T00:00:00Z
pub const timestamp_max_seconds: i64 = 253402300799; // 9999-12-31T23:59:59Z

// The values are part of the protobuf spec, see `google/protobuf/duration.proto`.
pub const duration_min_seconds: i64 = -315576000000;
pub const duration_max_seconds: i64 = 315576000000;

test "timestamp constants" {
    try std.testing.expectEqual(timestamp_min_seconds, (try parseTimestamp("0001-01-01T00:00:00Z")).seconds);
    try std.testing.expectEqual(timestamp_max_seconds, (try parseTimestamp("9999-12-31T23:59:59Z")).seconds);
}

/// Returns the number of days since 1970-01-01 (negative before it) of a date
/// in the proleptic Gregorian calendar. `m` must be in [1, 12] and `d` in
/// [1, daysInMonth(y, m)].
fn daysFromCivil(y_in: i64, m: i64, d: i64) i64 {
    const y = if (m <= 2) y_in - 1 else y_in;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400; // [0, 399]
    const mp = if (m > 2) m - 3 else m + 9; // [0, 11]
    const doy = @divFloor(153 * mp + 2, 5) + d - 1; // [0, 365]
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy; // [0, 146096]
    return era * 146097 + doe - 719468;
}

/// Inverse of `daysFromCivil`.
fn civilFromDays(z_in: i64) struct { year: i64, month: i64, day: i64 } {
    const z = z_in + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097; // [0, 146096]
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365); // [0, 399]
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100)); // [0, 365]
    const mp = @divFloor(5 * doy + 2, 153); // [0, 11]
    const d = doy - @divFloor(153 * mp + 2, 5) + 1; // [1, 31]
    const m = if (mp < 10) mp + 3 else mp - 9; // [1, 12]
    const y = yoe + era * 400;
    return .{ .year = if (m <= 2) y + 1 else y, .month = m, .day = d };
}

// Conformance only exercises a handful of dates near the epoch and the range
// bounds, so check the calendar conversion on every representable day.
test "daysFromCivil / civilFromDays round trip" {
    var prev_z: i64 = daysFromCivil(1, 1, 1) - 1;

    var year: i64 = 1;
    while (year <= 9999) : (year += 1) {
        var month: i64 = 1;
        while (month <= 12) : (month += 1) {
            const last_day = daysInMonth(year, month);
            var day: i64 = 1;
            while (day <= last_day) : (day += 1) {
                const z = daysFromCivil(year, month, day);
                try std.testing.expectEqual(prev_z + 1, z);

                const back = civilFromDays(z);
                try std.testing.expectEqual(year, back.year);
                try std.testing.expectEqual(month, back.month);
                try std.testing.expectEqual(day, back.day);

                prev_z = z;
            }
        }
    }
    try std.testing.expectEqual(0, daysFromCivil(1970, 1, 1));
}

fn isLeapYear(year: i64) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

fn daysInMonth(year: i64, month: i64) i64 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => unreachable,
    };
}

fn validateTimestamp(seconds: i64, nanos: i32) !void {
    if (seconds < timestamp_min_seconds or seconds > timestamp_max_seconds) return error.InvalidTimestamp;
    if (nanos < 0 or nanos > 999_999_999) return error.InvalidTimestamp;
}

fn validateDuration(seconds: i64, nanos: i32) !void {
    if (seconds < duration_min_seconds or seconds > duration_max_seconds) return error.InvalidDuration;
    if (nanos < -999_999_999 or nanos > 999_999_999) return error.InvalidDuration;
    if (seconds != 0 and nanos != 0 and (seconds < 0) != (nanos < 0)) return error.InvalidDuration;
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
/// into `buf` and returns the slice. `buf` must have length >= 30.
pub fn formatTimestamp(buf: []u8, seconds: i64, nanos: i32) ![]const u8 {
    try validateTimestamp(seconds, nanos);

    const ymd = civilFromDays(@divFloor(seconds, 86400));
    const secs_of_day: u32 = @intCast(@mod(seconds, 86400));

    var frac_buf: [10]u8 = undefined;
    const frac = formatFracSeconds(&frac_buf, @intCast(nanos));

    // Cast the (always non-negative, range-validated) fields to unsigned:
    // Zig's `{d:0>N}` formatting prepends an explicit '+' for positive
    // *signed* integers when a width is given, which we don't want here.
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}{s}Z", .{
        @as(u32, @intCast(ymd.year)),
        @as(u32, @intCast(ymd.month)),
        @as(u32, @intCast(ymd.day)),
        secs_of_day / 3600,
        secs_of_day / 60 % 60,
        secs_of_day % 60,
        frac,
    });
}

/// Formats a Duration as e.g. "3s" / "3.000001s" / "-0.5s" into `buf` and
/// returns the slice. `buf` must have length >= 24.
pub fn formatDuration(buf: []u8, seconds: i64, nanos: i32) ![]const u8 {
    try validateDuration(seconds, nanos);

    const negative = seconds < 0 or nanos < 0;

    var frac_buf: [10]u8 = undefined;
    const frac = formatFracSeconds(&frac_buf, @abs(nanos));

    return std.fmt.bufPrint(buf, "{s}{d}{s}s", .{ if (negative) "-" else "", @abs(seconds), frac });
}

/// Parses 1 to 9 fractional-second digits (from after the `.` in a timestamp
/// or duration string) into a nanosecond count in [0, 999_999_999].
fn parseFracDigits(digits: []const u8) !u32 {
    if (digits.len == 0 or digits.len > 9) return error.InvalidJson;
    var n = try parseDigits(u32, digits);
    for (digits.len..9) |_| n *= 10;
    return n;
}

/// Parses a non-empty string of ASCII digits (no sign allowed).
fn parseDigits(comptime T: type, s: []const u8) !T {
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return error.InvalidJson;
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
    const month = try parseDigits(i64, s[5..7]);
    const day = try parseDigits(i64, s[8..10]);
    const hour = try parseDigits(i64, s[11..13]);
    const minute = try parseDigits(i64, s[14..16]);
    const second = try parseDigits(i64, s[17..19]);

    if (month < 1 or month > 12) return error.InvalidJson;
    if (day < 1 or day > daysInMonth(year, month)) return error.InvalidJson;
    if (hour > 23 or minute > 59 or second > 59) return error.InvalidJson;

    var rest = s[19..];

    var nanos: u32 = 0;
    if (rest.len > 0 and rest[0] == '.') {
        var frac_end: usize = 1;
        while (frac_end < rest.len and std.ascii.isDigit(rest[frac_end])) : (frac_end += 1) {}
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

    const seconds = daysFromCivil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second - offset_seconds;
    try validateTimestamp(seconds, @intCast(nanos));

    return .{ .seconds = seconds, .nanos = @intCast(nanos) };
}

/// Parses a Duration string, e.g. "3s" / "3.000001s" / "-0.5s".
pub fn parseDuration(s: []const u8) !struct { seconds: i64, nanos: i32 } {
    if (s.len == 0 or s[s.len - 1] != 's') return error.InvalidJson;
    var body = s[0 .. s.len - 1];

    const negative = body.len > 0 and body[0] == '-';
    if (negative) body = body[1..];

    const dot_index = std.mem.indexOfScalar(u8, body, '.');
    const int_part = if (dot_index) |i| body[0..i] else body;
    if (int_part.len == 0) return error.InvalidJson;

    const abs_seconds = try parseDigits(i64, int_part);
    const abs_nanos: i32 = if (dot_index) |i| @intCast(try parseFracDigits(body[i + 1 ..])) else 0;

    const seconds = if (negative) -abs_seconds else abs_seconds;
    const nanos = if (negative) -abs_nanos else abs_nanos;
    try validateDuration(seconds, nanos);

    return .{ .seconds = seconds, .nanos = nanos };
}

// Malformed inputs that the conformance suite doesn't exercise.
test "parse rejects invalid input" {
    try std.testing.expectError(error.InvalidJson, parseTimestamp("2017-13-15T01:30:15Z")); // bad month
    try std.testing.expectError(error.InvalidJson, parseTimestamp("2017-02-29T01:30:15Z")); // non-leap Feb 29
    try std.testing.expectError(error.InvalidJson, parseTimestamp("2017-01-15T01:30:15.0000000001Z")); // > 9 frac digits
    try std.testing.expectError(error.InvalidJson, parseDuration("5.0000000001s")); // > 9 frac digits
    try std.testing.expectError(error.InvalidJson, parseDuration(".5s")); // empty integer part
}
