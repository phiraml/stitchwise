import XCTest

/// Agent-driven journey. Every step captures a screenshot *and* the element tree, so a
/// developer on a machine without Xcode can read exactly what the app did.
///
/// Elements are addressed by accessibility identifier, never by coordinate, so the same
/// journey runs unchanged across the device matrix in CI.
/// `@MainActor` because XCUIElement is main-actor isolated under Swift 6; without it,
/// touching `.exists` from a test method is a warning today and an error tomorrow.
@MainActor
final class JourneyTests: XCTestCase {

    private var app: XCUIApplication!
    private var step = 0

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-state"]
        app.launch()
    }

    /// A NavigationLink inside a List surfaces as a cell on some size classes and a button
    /// on others, so match the identifier across any element type.
    private func projectRow(_ name: String) -> XCUIElement {
        let element = app.descendants(matching: .any)
            .matching(identifier: "projectRow-\(name)").firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Row for \(name) never appeared")
        return element
    }

    private func snap(_ name: String) {
        step += 1
        let label = String(format: "%02d-%@", step, name)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = label
        shot.lifetime = .keepAlways
        add(shot)

        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(label)-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    func testCreateProjectAndCount() {
        snap("launch")

        // Empty state -> new project
        let newProject = app.buttons["emptyStateNewProjectButton"].exists
            ? app.buttons["emptyStateNewProjectButton"]
            : app.buttons["newProjectButton"]
        XCTAssertTrue(newProject.waitForExistence(timeout: 10), "No way to create a project")
        newProject.tap()
        snap("new-project-sheet")

        let nameField = app.textFields["projectNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Test Scarf")

        app.buttons["confirmAddProjectButton"].tap()
        snap("project-created")

        // Open it
        projectRow("Test Scarf").tap()
        snap("counter-screen")

        // Count ten rows
        let increment = app.buttons["incrementButton"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        for _ in 0..<10 { increment.tap() }
        snap("after-ten-rows")

        let value = app.staticTexts["primaryCounterValue"]
        XCTAssertTrue(value.exists)
        XCTAssertEqual(value.label, "11", "Counter should read 11 after ten taps from 1")

        // Undo three times
        let undo = app.buttons["undoButton"]
        for _ in 0..<3 { undo.tap() }
        snap("after-undo")
        XCTAssertEqual(app.staticTexts["primaryCounterValue"].label, "8")
    }

    /// The promise in the paywall copy must actually be on screen.
    func testPaywallStatesNoContentIsHeldHostage() {
        let unlock = app.buttons["unlockButton"]
        if unlock.waitForExistence(timeout: 5) {
            unlock.tap()
            snap("paywall")
            XCTAssertTrue(
                app.staticTexts["noHostageCopy"].exists,
                "Paywall must state that existing content is never locked"
            )
        }
    }

    func testCounterSurvivesRelaunch() {
        let newProject = app.buttons["emptyStateNewProjectButton"].exists
            ? app.buttons["emptyStateNewProjectButton"]
            : app.buttons["newProjectButton"]
        XCTAssertTrue(newProject.waitForExistence(timeout: 10))
        newProject.tap()

        let nameField = app.textFields["projectNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Durability")
        app.buttons["confirmAddProjectButton"].tap()

        projectRow("Durability").tap()
        let increment = app.buttons["incrementButton"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        for _ in 0..<7 { increment.tap() }
        snap("before-relaunch")

        // Relaunch without the reset flag: state must still be there.
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        snap("after-relaunch")

        projectRow("Durability").tap()
        XCTAssertEqual(
            app.staticTexts["primaryCounterValue"].label, "8",
            "Rows counted before a relaunch must survive it"
        )
        snap("relaunch-counter")
    }
}
