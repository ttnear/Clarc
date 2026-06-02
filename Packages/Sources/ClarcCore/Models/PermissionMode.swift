// Modifications Copyright 2026 dttxorg (MiniClarc).
// SPDX-License-Identifier: Apache-2.0
//
// Originally: Clarc (https://github.com/ttnear/Clarc), Apache License 2.0.
// See ../../NOTICE in the repository root for the full modification history.

import Foundation

/// Mirrors Claude Code CLI's `--permission-mode` values, plus a Clarc-side
/// convenience mode that fully pre-approves every tool.
///
/// See https://code.claude.com/docs/en/permission-modes for semantics.
public enum PermissionMode: String, CaseIterable, Sendable, Codable {
    case `default`
    case acceptEdits
    case plan
    case auto
    case bypassPermissions
    /// Clarc-specific: bypass the permission modal AND pre-approve every tool
    /// so no tool call ever blocks. Mapped to `--permission-mode bypassPermissions`
    /// + `--allowedTools "*"` at the CLI layer. See `ClaudeService.buildArguments`.
    case fullAccess

    public var displayName: String {
        switch self {
        case .default: return "Ask"
        case .acceptEdits: return "Accept Edits"
        case .plan: return "Plan"
        case .auto: return "Auto"
        case .bypassPermissions: return "Bypass"
        case .fullAccess: return "Full Access"
        }
    }

    public var systemImage: String {
        switch self {
        case .default: return "bolt.shield"
        case .acceptEdits: return "checkmark.shield"
        case .plan: return "eye"
        case .auto: return "wand.and.sparkles"
        case .bypassPermissions: return "bolt.shield.fill"
        case .fullAccess: return "lock.open"
        }
    }

    /// When true, skip writing the PreToolUse hook settings and skip
    /// the `--allowedTools` pre-approval list — bypassPermissions mode
    /// disables the entire permission pipeline.
    ///
    /// `fullAccess` also skips the hook pipeline (it never wants the
    /// permission modal to appear), but unlike `bypassPermissions` it
    /// DOES add a wildcard `--allowedTools "*"` so every tool is
    /// pre-approved at the CLI layer — see `usesWildcardAllowedTools`.
    public var skipsHookPipeline: Bool {
        switch self {
        case .bypassPermissions, .fullAccess:
            return true
        default:
            return false
        }
    }

    /// When true, emit `--allowedTools "*"` instead of the curated safe-tools
    /// list. Only `fullAccess` opts into this — it explicitly means "all
    /// tools pre-approved, no questions asked".
    public var usesWildcardAllowedTools: Bool {
        self == .fullAccess
    }

    /// The CLI `--permission-mode` value to emit. `fullAccess` maps to
    /// `bypassPermissions` at the wire level (CLI has no "fullAccess"
    /// token) plus the wildcard allowedTools list above.
    public var cliPermissionModeValue: String {
        switch self {
        case .fullAccess: return PermissionMode.bypassPermissions.rawValue
        default:          return rawValue
        }
    }
}
