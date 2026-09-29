import SwiftUI
import UIKit

/// UIKit handles the interactive swipe. Programmatic jumps move only one page,
/// even when the destination is several tabs away.
struct PagePager: UIViewControllerRepresentable {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        controller.view.backgroundColor = .clear
        let coordinator = context.coordinator
        coordinator.nav = nav
        coordinator.pages = (0..<5).map { index in
            let host = UIHostingController(rootView: PageView(index: index)
                .environmentObject(store).environmentObject(nav))
            host.view.backgroundColor = .clear
            return host
        }
        coordinator.visibleIndex = nav.page
        coordinator.requestedIndex = nav.page
        controller.dataSource = coordinator
        controller.delegate = coordinator
        controller.setViewControllers([coordinator.pages[nav.page]], direction: .forward, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.requestedIndex = nav.page
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.applySelection(to: controller)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        weak var nav: Nav?
        var pages: [UIViewController] = []
        var visibleIndex = 2
        var requestedIndex = 2
        var reduceMotion = false
        private var transitioning = false
        private var swipeStartRequest = 2

        func applySelection(to controller: UIPageViewController) {
            guard !transitioning, requestedIndex != visibleIndex,
                  pages.indices.contains(requestedIndex) else { return }
            let target = requestedIndex
            let direction: UIPageViewController.NavigationDirection = target > visibleIndex ? .forward : .reverse
            transitioning = true
            controller.view.endEditing(true)
            controller.setViewControllers([pages[target]], direction: direction,
                                          animated: !reduceMotion && controller.view.window != nil) { [weak self, weak controller] _ in
                guard let self = self, let controller = controller else { return }
                self.visibleIndex = target
                self.transitioning = false
                // Coalesce rapid taps instead of starting overlapping page animations.
                self.applySelection(to: controller)
            }
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = pages.firstIndex(of: viewController), index > 0 else { return nil }
            return pages[index - 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = pages.firstIndex(of: viewController), index + 1 < pages.count else { return nil }
            return pages[index + 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                willTransitionTo pendingViewControllers: [UIViewController]) {
            transitioning = true
            pageViewController.view.endEditing(true)
            swipeStartRequest = requestedIndex
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if let view = pageViewController.viewControllers?.first, let index = pages.firstIndex(of: view) {
                visibleIndex = index
            }
            transitioning = false
            if requestedIndex == swipeStartRequest {
                requestedIndex = visibleIndex
                nav?.page = visibleIndex
            }
            applySelection(to: pageViewController)
        }
    }
}
