import ObjectiveC
import SwiftUI
import UIKit

/// Keeps the native iOS edge-swipe back gesture available across SwiftUI
/// NavigationStack screens, including pages that customize or hide nav chrome.
private var globalSwipeBackDelegateKey: UInt8 = 0

private final class GlobalSwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        return navigationController.viewControllers.count > 1 && navigationController.transitionCoordinator == nil
    }
}

private final class GlobalSwipeBackInstallerController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installSwipeBackIfPossible()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installSwipeBackIfPossible()
    }

    private func installSwipeBackIfPossible() {
        guard let rootViewController = view.window?.rootViewController else { return }
        installSwipeBack(in: rootViewController)
    }

    private func installSwipeBack(in viewController: UIViewController) {
        if let navigationController = viewController as? UINavigationController {
            navigationController.fc_installSwipeBackDelegate()
        }

        viewController.children.forEach(installSwipeBack)

        if let presentedViewController = viewController.presentedViewController {
            installSwipeBack(in: presentedViewController)
        }
    }
}

struct GlobalSwipeBackInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        GlobalSwipeBackInstallerController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        uiViewController.view.setNeedsLayout()
    }
}

extension UINavigationController {
    static func enableGlobalSwipeBack() {
        DispatchQueue.main.async {
            UIApplication.shared.fc_installSwipeBackOnVisibleNavigationControllers()
        }
    }

    fileprivate func fc_installSwipeBackDelegate() {
        if objc_getAssociatedObject(self, &globalSwipeBackDelegateKey) == nil {
            let delegate = GlobalSwipeBackDelegate(navigationController: self)
            objc_setAssociatedObject(
                self,
                &globalSwipeBackDelegateKey,
                delegate,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }

        interactivePopGestureRecognizer?.delegate = objc_getAssociatedObject(
            self,
            &globalSwipeBackDelegateKey
        ) as? UIGestureRecognizerDelegate
        interactivePopGestureRecognizer?.isEnabled = true
    }
}

private extension UIApplication {
    func fc_installSwipeBackOnVisibleNavigationControllers() {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .compactMap(\.rootViewController)
            .forEach { rootViewController in
                fc_installSwipeBack(in: rootViewController)
            }
    }

    func fc_installSwipeBack(in viewController: UIViewController) {
        if let navigationController = viewController as? UINavigationController {
            navigationController.fc_installSwipeBackDelegate()
        }

        viewController.children.forEach(fc_installSwipeBack)

        if let presentedViewController = viewController.presentedViewController {
            fc_installSwipeBack(in: presentedViewController)
        }
    }
}
