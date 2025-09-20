import SwiftUI
import UIKit

@MainActor
struct ShareSheet: UIViewControllerRepresentable {
    let journal: Journal

    func makeUIViewController(context: Context) -> UIViewController {
        ShareController.shared().sharingController(for: journal)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // no-op
    }
}
