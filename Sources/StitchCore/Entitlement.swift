import Foundation

/// What the user has paid for. One non-consumable purchase, forever. No subscription,
/// no trial countdown, no server check.
public enum Entitlement: String, Codable, Sendable {
    case free
    case lifetime
}

/// Features that can be gated.
public enum Feature: String, Sendable, CaseIterable {
    case unlimitedProjects
    case patternAnnotation
    case timeTracking
    case gaugeCalculators
}

/// The gating rule.
///
/// The competitor failure this is written against is content disappearing when a trial
/// ends. The rule here is deliberately one-directional: paying unlocks *creating* new
/// things, and nothing a user has already made can ever become unreadable. A knitter who
/// never pays keeps full access to every project, counter, pattern and annotation they
/// already have — the free tier limits growth, never retention.
public struct Entitlements: Sendable, Equatable {
    public static let freeProjectLimit = 2

    public var entitlement: Entitlement

    public init(entitlement: Entitlement = .free) {
        self.entitlement = entitlement
    }

    public var isPaid: Bool { entitlement == .lifetime }

    /// Whether a *new* project may be created given how many already exist.
    public func canCreateProject(existingCount: Int) -> Bool {
        isPaid || existingCount < Self.freeProjectLimit
    }

    /// Whether a feature may be *used to create or modify* content.
    public func canUse(_ feature: Feature) -> Bool {
        switch feature {
        case .unlimitedProjects, .patternAnnotation:
            return isPaid
        case .timeTracking, .gaugeCalculators:
            return true      // never gated; they are why the free tier is worth using
        }
    }

    /// Whether existing content remains readable. Always true, by design.
    ///
    /// This is a function rather than a constant so the intent is greppable and so any
    /// future change to it fails the test that pins it.
    public func canAccessExistingContent(_ project: Project) -> Bool {
        _ = project
        return true
    }
}
