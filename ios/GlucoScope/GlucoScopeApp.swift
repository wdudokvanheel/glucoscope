import SwiftUI

@main
struct GlucoScopeApp: App {
    public static let APP_NAME = "GlucoScope"
    public static let URL_LICENSE = "https://wdudokvanheel.github.io/glucoscope/license.html"
    public static let URL_PRIVACY = "https://wdudokvanheel.github.io/glucoscope/privacy.html"
    public static let URL_SOURCE = "https://github.com/wdudokvanheel/glucoscope/"
    

    @UIApplicationDelegateAdaptor(GlucoScopeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppView()
        }
    }
}

/// Construct the collector during launch, including Core Bluetooth restoration launches.
final class GlucoScopeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = LibreDiagnosticsCoordinator.shared
        return true
    }
}
