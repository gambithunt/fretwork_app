import SwiftUI

@main
struct FretworkApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .frame(minWidth: 1_120, minHeight: 720)
        }
    }
}
