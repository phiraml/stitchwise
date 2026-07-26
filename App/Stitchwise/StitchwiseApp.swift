import SwiftUI
import StitchCore

@main
struct StitchwiseApp: App {
    @State private var state = AppState.makeDefault()
    @State private var purchases = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environment(state)
                .environment(purchases)
                .task {
                    await purchases.start()
                    state.setEntitlement(purchases.entitlement)
                }
                .onChange(of: purchases.entitlement) { _, new in
                    state.setEntitlement(new)
                }
        }
    }
}
