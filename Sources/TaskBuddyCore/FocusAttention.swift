import Foundation

public enum FocusStudyMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case screen
    case paper
    case hybrid

    public var id: String { rawValue }
}

public enum FocusDistractionReason: String, Equatable, Sendable {
    case faceMissing = "FACE NOT FOUND"
    case headTurned = "LOOK FORWARD"
    case gazeAway = "EYES OFF SCREEN"
    case eyesClosed = "EYES CLOSED"
    case phoneUse = "PHONE-LIKE POSTURE"
}

public struct FaceAttentionSignals: Equatable, Sendable {
    public let facePresent: Bool
    public let yawRadians: Double?
    public let eyesClosed: Bool
    public let gazeAway: Bool
    public let gazeDown: Bool
    public let phoneDetected: Bool
    public let handsTogether: Bool

    public init(
        facePresent: Bool,
        yawRadians: Double? = nil,
        eyesClosed: Bool = false,
        gazeAway: Bool = false,
        gazeDown: Bool = false,
        phoneDetected: Bool = false,
        handsTogether: Bool = false
    ) {
        self.facePresent = facePresent
        self.yawRadians = yawRadians
        self.eyesClosed = eyesClosed
        self.gazeAway = gazeAway
        self.gazeDown = gazeDown
        self.phoneDetected = phoneDetected
        self.handsTogether = handsTogether
    }
}

public enum FocusAttentionClassifier {
    public static func distractionReason(
        for signals: FaceAttentionSignals,
        mode: FocusStudyMode
    ) -> FocusDistractionReason? {
        guard signals.facePresent else { return .faceMissing }
        let sidewaysLimit: Double = switch mode {
        case .screen: 0.32
        case .paper: 0.48
        case .hybrid: 0.42
        }
        if let yaw = signals.yawRadians, abs(yaw) > sidewaysLimit { return .headTurned }
        if signals.eyesClosed { return .eyesClosed }
        if mode != .screen, signals.phoneDetected || (signals.gazeDown && signals.handsTogether) {
            return .phoneUse
        }
        if mode == .screen, signals.gazeAway { return .gazeAway }
        return nil
    }
}

public enum FocusPostureCalibration {
    public static let requiredSamples = 30

    public static func neutralYaw(from samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    public static func calibratedYaw(_ yaw: Double?, neutralYaw: Double) -> Double? {
        yaw.map { $0 - neutralYaw }
    }
}
