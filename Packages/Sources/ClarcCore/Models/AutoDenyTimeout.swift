import Foundation

/// How long a pending permission request is allowed to wait for the user
/// before Clarc auto-denies it. Configurable per app; persisted in
/// UserDefaults. Mirrors the hard-coded 5-minute timeout that previous
/// versions used, with three additions: longer windows for users who
/// occasionally step away, and `.never` for unattended long-running
/// sessions.
public enum AutoDenyTimeout: String, CaseIterable, Sendable, Codable {
    case fiveMinutes
    case tenMinutes
    case thirtyMinutes
    case never

    /// Length of the timeout in seconds. For `.never` this is a large
    /// value (24 hours) used as a practical stand-in for "no auto-deny"
    /// because the CLI hook protocol requires a finite integer; the
    /// PermissionServer treats any value above a sanity threshold as
    /// "effectively unlimited" and does not surface a countdown in
    /// the modal.
    public var seconds: Int {
        switch self {
        case .fiveMinutes:   return 5 * 60
        case .tenMinutes:    return 10 * 60
        case .thirtyMinutes: return 30 * 60
        case .never:         return 24 * 60 * 60
        }
    }

    /// True when the user opted out of auto-deny entirely. The modal
    /// omits the countdown when this is true.
    public var isUnlimited: Bool {
        self == .never
    }

    public var displayName: String {
        switch self {
        case .fiveMinutes:   return "5 minutes"
        case .tenMinutes:    return "10 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .never:         return "Don't auto-deny"
        }
    }
}
