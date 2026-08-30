import SwiftUI

@main
struct Climb3DApp: App {
    @StateObject private var model = Climb3DModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
