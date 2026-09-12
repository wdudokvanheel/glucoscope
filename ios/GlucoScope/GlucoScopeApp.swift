import SwiftUI

@main
struct GlucoScopeApp: App {
    public static let APP_NAME = "GlucoScope"
    public static let URL_LICENSE = "https://wdudokvanheel.github.io/glucoscope/license.html"
    public static let URL_PRIVACY = "https://wdudokvanheel.github.io/glucoscope/privacy.html"
    public static let URL_SOURCE = "https://github.com/wdudokvanheel/glucoscope/"
    

    @UIApplicationDelegateAdaptor(GlucoScopeAppDelegate.self) private var appDelegate
    @StateObject private var runtime: AppRuntime

    init() {
        Self.gateCollectorForPersistedMode()
        _runtime = StateObject(wrappedValue: AppRuntime())
    }

    static func gateCollectorForPersistedMode() {
        let mode = UserDefaults.standard.data(forKey: GlucoScopePreferenceKey.appMode.rawValue)
            .flatMap { try? JSONDecoder().decode(AppMode?.self, from: $0) } ?? nil
        if mode != .standalone {
            UserDefaults.standard.set(false, forKey: "libre2.collectionEnabled")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppView(runtime: runtime)
                .environmentObject(runtime)
                .environmentObject(runtime.preferences)
                .environmentObject(runtime.viewerDataSource)
                .environmentObject(runtime.viewerRealtime)
        }
    }
}

/// Construct the collector during launch, including Core Bluetooth restoration launches.
final class GlucoScopeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Core Bluetooth restoration can construct the collector before SwiftUI.
        // Gate it from the persisted product mode first so Viewer never resumes
        // standalone collection or recording during launch.
        GlucoScopeApp.gateCollectorForPersistedMode()
        _ = LibreDiagnosticsCoordinator.shared
        return true
    }
}
