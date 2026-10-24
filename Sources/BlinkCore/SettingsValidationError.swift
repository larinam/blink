import Foundation

/// Reports every invalid timing field at once so a settings form can mark them all inline,
/// rather than making the user fix one value per attempt.
public struct SettingsValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Field: String, CaseIterable, Sendable, Equatable {
        case shortInterval
        case shortDuration
        case longInterval
        case longDuration
        case blinkInterval
        case movementInterval
        case movementDuration

        /// Sentence-case name for use in UI error text.
        public var displayName: String {
            switch self {
            case .shortInterval: "Short break interval"
            case .shortDuration: "Short break length"
            case .longInterval: "Long break interval"
            case .longDuration: "Long break length"
            case .blinkInterval: "Blink reminder interval"
            case .movementInterval: "Movement break interval"
            case .movementDuration: "Movement break length"
            }
        }
    }

    public enum Reason: Equatable, Sendable {
        case notPositive
        case notFinite
    }

    public struct Issue: Equatable, Sendable, CustomStringConvertible {
        public let field: Field
        public let reason: Reason

        public init(field: Field, reason: Reason) {
            self.field = field
            self.reason = reason
        }

        /// Ready to show next to the offending control.
        public var message: String {
            switch reason {
            case .notPositive: "\(field.displayName) must be longer than zero."
            case .notFinite: "\(field.displayName) must be a number."
            }
        }

        public var description: String { message }
    }

    public let issues: [Issue]

    public init(issues: [Issue]) {
        self.issues = issues
    }

    public var fields: [Field] { issues.map(\.field) }

    public func message(for field: Field) -> String? {
        issues.first { $0.field == field }?.message
    }

    public var description: String {
        issues.map(\.message).joined(separator: " ")
    }
}

extension SettingsValidationError: LocalizedError {
    public var errorDescription: String? { description }
}
