import Foundation

/// Lexical path-containment utilities used by the permission system.
///
/// These helpers deliberately avoid any filesystem access and do not
/// resolve symbolic links. A symlink inside a project that points to a
/// location outside the project is still considered "inside" by
/// ``isInside(parent:child:)``; resolving symlinks at the project boundary
/// is intentionally deferred (it would require touching the filesystem
/// on every hook call).
public enum PathContainment {

    /// Returns `true` when `child` denotes a path inside `parent` (or
    /// is the same path). Both inputs are standardized lexically via
    /// `NSString.standardizingPath`, which collapses `//`, resolves
    /// `.`/`..` segments, and strips trailing slashes — without
    /// touching the filesystem.
    ///
    /// Examples:
    /// ```
    /// isInside(parent: "/Users/me/proj", child: "/Users/me/proj")              // true
    /// isInside(parent: "/Users/me/proj", child: "/Users/me/proj/foo.swift")   // true
    /// isInside(parent: "/Users/me/proj", child: "/Users/me/projbackup/x")      // false
    /// isInside(parent: "/Users/me/proj", child: "/Users/me/proj/../other/x")  // false
    /// ```
    public static func isInside(parent: String, child: String) -> Bool {
        guard !parent.isEmpty, !child.isEmpty else { return false }
        let p = (parent as NSString).standardizingPath
        let c = (child   as NSString).standardizingPath
        if p == c { return true }
        return c.hasPrefix(p + "/")
    }
}
