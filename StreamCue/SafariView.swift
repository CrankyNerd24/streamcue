import SwiftUI
import SafariServices

/// Wraps SFSafariViewController so a web fallback (JustWatch, when no
/// installed app claims the title) opens in a sheet instead of kicking you
/// out to Safari — one tap back into StreamCue, no app switch.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
