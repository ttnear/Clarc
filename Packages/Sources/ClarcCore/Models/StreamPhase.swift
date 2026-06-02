// Modifications Copyright 2026 dttxorg (MiniClarc).
// SPDX-License-Identifier: Apache-2.0
//
// Originally: Clarc (https://github.com/ttnear/Clarc), Apache License 2.0.
// See ../../NOTICE in the repository root for the full modification history.

import Foundation

/// A single phase of an assistant turn in the streaming pipeline.
///
/// Mirrors the order in which Anthropic's `--include-partial-messages` stream
/// emits `content_block_start` events. Used by the UI to mark completed
/// non-text phases (thinking / tool use / tool result) for auto-collapse,
/// while the final `.text` phase is always rendered expanded.
public enum StreamPhase: String, Codable, Sendable, Equatable, CaseIterable {
    case thinking
    case text
    case toolUse
    case toolResult
}
