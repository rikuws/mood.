import SwiftUI
import UIKit

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let model = ShareComposerModel()
    private var hostingController: UIHostingController<ShareComposerView>?
    private var isFinishing = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 420, height: 620)

        let rootView = ShareComposerView(
            model: model,
            onCancel: { [weak self] in self?.cancel() },
            onComplete: { [weak self] in self?.complete() }
        )
        let host = UIHostingController(rootView: rootView)
        hostingController = host

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { [weak self] in
            guard let self else { return }
            await model.load(items: items)
        }
    }

    private func complete() {
        guard !isFinishing else { return }
        isFinishing = true
        view.endEditing(true)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        guard !isFinishing else { return }
        isFinishing = true
        view.endEditing(true)
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError,
            userInfo: [NSLocalizedDescriptionKey: "The Pinax save was cancelled."]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
