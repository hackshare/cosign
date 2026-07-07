import Foundation

/// Renders a time-lock duration in seconds as a friendly string. Mirrors the
/// Rust `format_time_lock` rule so the editor and the decoded-action summary
/// read the same. 0 is "None"; whole days (>= 2) render as days; otherwise
/// whole hours, then whole minutes, then seconds. One day reads "24 hours".
public func cosignTimeLockDisplay(seconds: UInt32) -> String {
    if seconds == 0 { return "None" }
    let days = seconds / 86400
    if days >= 2, seconds % 86400 == 0 { return "\(days) days" }
    if seconds % 3600 == 0 {
        let hours = seconds / 3600
        return "\(hours) hour\(hours == 1 ? "" : "s")"
    }
    if seconds % 60 == 0 {
        let minutes = seconds / 60
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
    return "\(seconds) second\(seconds == 1 ? "" : "s")"
}
