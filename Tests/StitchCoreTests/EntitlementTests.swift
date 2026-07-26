import Testing
import Foundation
@testable import StitchCore

@Suite("Entitlements")
struct EntitlementTests {

    @Test("free tier can create up to the limit")
    func freeLimit() {
        let e = Entitlements(entitlement: .free)
        #expect(e.canCreateProject(existingCount: 0))
        #expect(e.canCreateProject(existingCount: 1))
        #expect(!e.canCreateProject(existingCount: 2))
    }

    @Test("paid tier has no project limit")
    func paidUnlimited() {
        let e = Entitlements(entitlement: .lifetime)
        #expect(e.canCreateProject(existingCount: 0))
        #expect(e.canCreateProject(existingCount: 500))
    }

    /// The rule the whole pitch rests on. If this ever fails, the app has become the
    /// thing it was built to replace.
    @Test("existing content stays readable on the free tier, always")
    func neverLocksExistingContent() {
        let free = Entitlements(entitlement: .free)
        var pattern = PatternRef(filename: "a.pdf", displayName: "Aran", pageCount: 12)
        pattern.moveRowHighlighter(onPage: 4, toY: 0.3)

        var project = Project(name: "Half-finished jumper")
        project.pattern = pattern

        #expect(free.canAccessExistingContent(project))
        // Even with far more projects than the free tier allows creating.
        for _ in 0..<10 {
            #expect(free.canAccessExistingContent(Project(name: "Another")))
        }
    }

    @Test("core knitting utility is never paywalled")
    func coreFeaturesFree() {
        let free = Entitlements(entitlement: .free)
        #expect(free.canUse(.timeTracking))
        #expect(free.canUse(.gaugeCalculators))
    }

    @Test("annotation and unlimited projects are the paid features")
    func paidFeatures() {
        let free = Entitlements(entitlement: .free)
        let paid = Entitlements(entitlement: .lifetime)
        #expect(!free.canUse(.patternAnnotation))
        #expect(!free.canUse(.unlimitedProjects))
        #expect(paid.canUse(.patternAnnotation))
        #expect(paid.canUse(.unlimitedProjects))
    }
}
