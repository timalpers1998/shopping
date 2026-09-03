import SwiftUI
import SafariServices

/// In-app browser for merchant pages. SFSafariViewController keeps the user's cookies and is not subject to ATS.
struct ProductBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = .white
        vc.preferredBarTintColor = .black
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct ProductPickerSheet: View {
    let postId: UUID
    var body: some View {
        PlaceholderScreen(title: "Products")
    }
}
