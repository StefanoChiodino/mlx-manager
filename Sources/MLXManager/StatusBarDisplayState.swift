import Foundation

/// The typed display state passed from StatusBarController to the status bar view.
public enum StatusBarDisplayState: Equatable {
    case offline
    case idle
    case processing(fraction: Double)   // fraction in [0, 1]
}
