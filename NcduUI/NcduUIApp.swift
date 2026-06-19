import SwiftUI

@main
struct NcduUIApp: App {
    @State private var model = ScanViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 480)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.refreshFullDiskAccessStatus()
                }
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            AppCommands(model: model)
        }
    }
}
