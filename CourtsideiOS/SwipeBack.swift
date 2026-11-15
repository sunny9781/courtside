import UIKit

/// Keeps "swipe from the left edge to go back" working on screens that hide the navigation bar (the game screen).
/// UIKit turns the gesture off when the bar is hidden; this turns it back on whenever there's a screen to go back to.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
