import UIKit
import CloudKit

/// Exists for one reason: SwiftUI's `App` protocol has no hook for CKShare
/// acceptance. Tapping a household-share invite link hands control to the
/// scene, not the app, so this brings in a thin UIKit app/scene delegate
/// pair purely to catch that callback and forward it to
/// `HouseholdShareManager`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            do {
                try await HouseholdShareManager.acceptShare(metadata: cloudKitShareMetadata)
                await SharedListStore.shared.refresh()
            } catch {
                SharedListStore.shared.errorMessage = "Couldn't join the household list: \(error.localizedDescription)"
            }
        }
    }
}
