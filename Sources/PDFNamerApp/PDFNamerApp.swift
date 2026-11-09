import SwiftUI

@main
struct PDFNamerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environment(model)
        } label: {
            Image(systemName: model.isBusy ? "arrow.triangle.2.circlepath" : "doc.text.magnifyingglass")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model)
        }
    }
}
