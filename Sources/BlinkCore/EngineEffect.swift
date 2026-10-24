import Foundation

/// One-shot events. Everything the interface shows persistently comes from `EngineSnapshot`.
public enum EngineEffect: Equatable, Sendable {
    /// Show a silent blink cue on the display containing the pointer. Never queued: a cue
    /// that falls during a prompt, break, quiet period or absence is discarded, not deferred.
    case blink
    /// A break timer finished. The adapter consults `settings.completionSoundEnabled`
    /// before playing the chime; the engine suppresses this entirely while unavailable
    /// and never replays it on wake.
    case breakCompleted(BreakKind)
}
