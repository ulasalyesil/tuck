import AppKit
import SwiftUI
import os

/// One motion vocabulary for the whole app. Pointer actions animate; keyboard
/// actions never do, since they repeat too often to wait for.
enum Motion {
    /// Strong ease-out: moves at once, settles softly.
    static let curve = (0.23, 1.0, 0.32, 1.0)

    static let enter = Animation.timingCurve(curve.0, curve.1, curve.2, curve.3, duration: 0.18)
    static let exit = Animation.timingCurve(curve.0, curve.1, curve.2, curve.3, duration: 0.12)
    static let swap = Animation.timingCurve(curve.0, curve.1, curve.2, curve.3, duration: 0.16)

    static let resizeDuration: TimeInterval = 0.2
    static let resizeTiming = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)

    /// Reduce Motion keeps fades and drops scale and slide.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static var hiddenScale: CGFloat { reduced ? 1 : 0.96 }
    static var levelSlide: CGFloat { reduced ? 0 : 8 }

    /// `log stream --predicate 'subsystem == "com.ulasalyesil.tuck"' --level debug`
    static let log = Logger(subsystem: "com.ulasalyesil.tuck", category: "motion")
}
