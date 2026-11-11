import Foundation

public enum FocusTime {
    public static func formatted(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    public static func remaining(totalSeconds: Int, elapsed: TimeInterval) -> Int {
        max(0, totalSeconds - Int(elapsed.rounded(.down)))
    }
}
