import ObjectiveC
import SwiftUI
import UIKit

/// Keeps the native iOS edge-swipe back gesture available across SwiftUI
/// NavigationStack screens, including pages that customize or hide nav chrome.
private var globalSwipeBackDelegateKey: UInt8 = 0
private var globalEdgePopWindowPanKey: UInt8 = 0

private final class GlobalSwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        UIApplication.shared.fc_dismissKeyboard()
        guard let navigationController else { return false }
        return navigationController.viewControllers.count > 1 && navigationController.transitionCoordinator == nil
    }
}

private final class GlobalEdgePopPanHandler: NSObject, UIGestureRecognizerDelegate {
    weak var window: UIWindow?
    private var didPop = false

    init(window: UIWindow) {
        self.window = window
    }

    @objc func handleEdgePan(_ gestureRecognizer: UIScreenEdgePanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            didPop = false
            UIApplication.shared.fc_dismissKeyboard()
            guard !didPop,
                  let window,
                  let navigationController = window.fc_topNavigationController(),
                  navigationController.viewControllers.count > 1,
                  navigationController.transitionCoordinator == nil
            else { return }
            didPop = true
            navigationController.popViewController(animated: true)
        case .ended:
            didPop = false
        case .cancelled, .failed:
            didPop = false
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let edgePan = gestureRecognizer as? UIScreenEdgePanGestureRecognizer,
              let window,
              let navigationController = window.fc_topNavigationController(),
              navigationController.viewControllers.count > 1,
              navigationController.transitionCoordinator == nil
        else { return false }

        let velocity = edgePan.velocity(in: window)
        return velocity.x > abs(velocity.y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

private final class GlobalSwipeBackInstallerController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installSwipeBackIfPossible()
        DispatchQueue.main.async { [weak self] in
            self?.installSwipeBackIfPossible()
        }
    }

    private func installSwipeBackIfPossible() {
        guard let rootViewController = view.window?.rootViewController else { return }
        view.window?.fc_installEdgePopPan()
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
        // Installation is event-driven from viewDidAppear. Forcing layout here
        // made every SwiftUI state update recursively walk the controller tree.
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

private extension UIWindow {
    func fc_installEdgePopPan() {
        if objc_getAssociatedObject(self, &globalEdgePopWindowPanKey) != nil {
            return
        }

        let handler = GlobalEdgePopPanHandler(window: self)
        let panGesture = UIScreenEdgePanGestureRecognizer(target: handler, action: #selector(GlobalEdgePopPanHandler.handleEdgePan(_:)))
        panGesture.edges = .left
        panGesture.cancelsTouchesInView = false
        panGesture.delaysTouchesBegan = false
        panGesture.delaysTouchesEnded = false
        panGesture.delegate = handler
        addGestureRecognizer(panGesture)

        objc_setAssociatedObject(
            self,
            &globalEdgePopWindowPanKey,
            handler,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    func fc_topNavigationController() -> UINavigationController? {
        rootViewController?.fc_topNavigationController()
    }
}

extension UIApplication {
    func fc_dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private extension UIApplication {
    func fc_installSwipeBackOnVisibleNavigationControllers() {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { window in
                window.fc_installEdgePopPan()
                if let rootViewController = window.rootViewController {
                    fc_installSwipeBack(in: rootViewController)
                }
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

private extension UIViewController {
    func fc_topNavigationController() -> UINavigationController? {
        if let navigationController = self as? UINavigationController {
            if let visibleViewController = navigationController.visibleViewController {
                return visibleViewController.fc_topNavigationController() ?? navigationController
            }
            return navigationController
        }

        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.fc_topNavigationController()
        }

        if let presentedViewController {
            return presentedViewController.fc_topNavigationController()
        }

        for child in children.reversed() {
            if let navigationController = child.fc_topNavigationController() {
                return navigationController
            }
        }

        return navigationController
    }
}
