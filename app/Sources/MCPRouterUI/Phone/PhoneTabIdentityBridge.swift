#if os(iOS)
    import SwiftUI
    import UIKit

    /// Scope the UIKit fallback to this shell's own enclosing tab controller.
    struct PhoneTabIdentityBridge: UIViewControllerRepresentable {
        let titles: [String]
        let identifiers: [String]

        func makeUIViewController(context: Context) -> Controller {
            Controller(titles: titles, identifiers: identifiers)
        }

        func updateUIViewController(_ controller: Controller, context: Context) {
            controller.titles = titles
            controller.identifiers = identifiers
            controller.applyIdentifiers()
        }

        final class Controller: UIViewController {
            var titles: [String]
            var identifiers: [String]

            init(titles: [String], identifiers: [String]) {
                self.titles = titles
                self.identifiers = identifiers
                super.init(nibName: nil, bundle: nil)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                fatalError("init(coder:) is unavailable")
            }

            override func loadView() {
                view = UIView(frame: .zero)
                view.isUserInteractionEnabled = false
                view.accessibilityElementsHidden = true
            }

            override func didMove(toParent parent: UIViewController?) {
                super.didMove(toParent: parent)
                applyIdentifiers()
            }

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                applyIdentifiers()
            }

            override func viewDidLayoutSubviews() {
                super.viewDidLayoutSubviews()
                applyIdentifiers()
            }

            func applyIdentifiers() {
                guard titles.count == 5, identifiers.count == 5, Set(identifiers).count == 5 else { return }
                var ancestor = parent
                while let controller = ancestor {
                    if let tabController = controller as? UITabBarController {
                        guard let items = tabController.tabBar.items, items.count == titles.count,
                              items.map({ $0.title ?? "" }) == titles else { return }
                        for (item, identifier) in zip(items, identifiers)
                            where item.accessibilityIdentifier != identifier
                        {
                            item.accessibilityIdentifier = identifier
                        }
                        return
                    }
                    ancestor = controller.parent
                }
            }
        }
    }
#endif
