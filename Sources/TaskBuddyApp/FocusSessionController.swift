import AVFoundation
import AppKit
import SwiftUI
import TaskBuddyCore
import Vision

extension FocusStudyMode {
    var title: String {
        switch self {
        case .screen: "SCREEN"
        case .paper: "PAPER"
        case .hybrid: "HYBRID"
        }
    }

    var detail: String {
        switch self {
        case .screen:
            "Stricter face, head, and gaze checks for work on this Mac."
        case .paper:
            "Allows paper gaze while checking for a visible phone or close two-hand phone posture."
        case .hybrid:
            "Allows switching between questions on screen and paper while still checking phone-like posture."
        }
    }
}

@MainActor
final class FocusSessionController: ObservableObject {
    enum CameraState: Equatable {
        case idle
        case requesting
        case ready
        case denied
        case failed(String)
    }

    enum AttentionState: Equatable {
        case waiting
        case calibrating(Int)
        case focused
        case distracted(FocusDistractionReason)
        case alerted(FocusDistractionReason)

        var title: String {
            switch self {
            case .waiting: "FINDING FACE"
            case .calibrating: "LEARNING YOUR FOCUS"
            case .focused: "LOCKED IN"
            case .distracted: "GET BACK ON TRACK"
            case .alerted: "NOT LOCKED IN"
            }
        }

        var detail: String? {
            switch self {
            case .calibrating(let samples): "LOOK AT YOUR WORK • \(samples)/\(FocusPostureCalibration.requiredSamples)"
            case .distracted(let reason), .alerted(let reason): reason.rawValue
            default: nil
            }
        }
    }

    @Published var selectedTaskID = ""
    @Published var studyMode: FocusStudyMode = .screen
    @Published var durationMinutes = 25
    @Published private(set) var remainingSeconds = 25 * 60
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var completed = false
    @Published private(set) var cameraState: CameraState = .idle
    @Published private(set) var attentionState: AttentionState = .waiting
    @Published private(set) var alertCount = 0
    @Published private(set) var isNudgeVisible = false
    @Published private(set) var calibrationSampleCount = 0

    let cameraSession = AVCaptureSession()
    var onLockStateChanged: ((Bool) -> Void)?

    private var timerTask: Task<Void, Never>?
    private var angerReleaseTask: Task<Void, Never>?
    private var endDate: Date?
    private var pausedAt: Date?
    private var cameraConfigured = false
    private var distractionBeganAt: Date?
    private var focusRecoveryBeganAt: Date?
    private var alertedThisEpisode = false
    private var isCurrentlyDistracted = false
    private var isAngryAnimationActive = false
    private var angryAnimationBeganAt: Date?
    private var calibrationYawSamples: [Double] = []
    private var neutralYaw = 0.0
    private let faceMonitor = FaceAttentionMonitor()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let alertSound = FocusAlertSound()
    private let distractionGrace: TimeInterval = 2.5
    private let focusRecoveryTime: TimeInterval = 0.6
    private let minimumAngryDuration: TimeInterval = 5

    init() {
        faceMonitor.onResult = { [weak self] signals in
            Task { @MainActor in self?.handleFaceSignals(signals) }
        }
    }

    var progress: Double {
        let total = max(1, durationMinutes * 60)
        return min(1, max(0, Double(total - remainingSeconds) / Double(total)))
    }

    var cameraStatus: String {
        switch cameraState {
        case .idle: "CAMERA OFF"
        case .requesting: "STARTING CAMERA..."
        case .ready: "LOCAL PREVIEW"
        case .denied: "CAMERA BLOCKED"
        case .failed(let message): message.uppercased()
        }
    }

    func select(_ task: TaskItem?) {
        selectedTaskID = task?.id ?? ""
    }

    func setDuration(_ minutes: Int) {
        guard !isRunning else { return }
        durationMinutes = minutes
        remainingSeconds = minutes * 60
        completed = false
    }

    func prepareCamera() {
        guard cameraState != .requesting, !cameraSession.isRunning else { return }
        cameraState = .requesting
        Task {
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                granted = true
            case .notDetermined:
                granted = await AVCaptureDevice.requestAccess(for: .video)
            default:
                granted = false
            }

            guard granted else {
                cameraState = .denied
                return
            }
            configureAndStartCamera()
        }
    }

    func start() {
        guard !selectedTaskID.isEmpty else { return }
        completed = false
        isRunning = true
        isPaused = false
        pausedAt = nil
        remainingSeconds = durationMinutes * 60
        alertCount = 0
        resetCalibration()
        resetAttention()
        endDate = nil
        prepareCamera()
        startTicker()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        pausedAt = .now
        resetAttention()
    }

    func resume() {
        guard isRunning, isPaused, let pausedAt else { return }
        endDate = endDate?.addingTimeInterval(Date().timeIntervalSince(pausedAt))
        self.pausedAt = nil
        isPaused = false
        attentionState = .waiting
    }

    func recalibrate() {
        guard isRunning else { return }
        endDate = nil
        resetCalibration()
        resetAttention()
    }

    func end() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
        isPaused = false
        completed = false
        pausedAt = nil
        endDate = nil
        remainingSeconds = durationMinutes * 60
        resetCalibration()
        resetAttention()
        stopCamera()
    }

    func close() {
        end()
        selectedTaskID = ""
    }

    func interfaceDidHide() {
        if !isRunning { stopCamera() }
    }

    private func startTicker() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !isPaused, let endDate {
                    remainingSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
                    if remainingSeconds == 0 {
                        timerTask = nil
                        isRunning = false
                        completed = true
                        resetAttention()
                        stopCamera()
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func configureAndStartCamera() {
        do {
            if !cameraConfigured {
                cameraSession.beginConfiguration()
                cameraSession.sessionPreset = .medium
                guard let device = AVCaptureDevice.default(for: .video) else {
                    cameraSession.commitConfiguration()
                    cameraState = .failed("No camera found")
                    return
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard cameraSession.canAddInput(input) else {
                    cameraSession.commitConfiguration()
                    cameraState = .failed("Camera unavailable")
                    return
                }
                cameraSession.addInput(input)
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                videoOutput.setSampleBufferDelegate(faceMonitor, queue: faceMonitor.queue)
                guard cameraSession.canAddOutput(videoOutput) else {
                    cameraSession.commitConfiguration()
                    cameraState = .failed("Face scanner unavailable")
                    return
                }
                cameraSession.addOutput(videoOutput)
                cameraSession.commitConfiguration()
                cameraConfigured = true
            }
            cameraSession.startRunning()
            cameraState = .ready
        } catch {
            if cameraSession.isRunning { cameraSession.stopRunning() }
            cameraState = .failed(error.localizedDescription)
        }
    }

    private func stopCamera() {
        if cameraSession.isRunning { cameraSession.stopRunning() }
        if cameraState == .ready { cameraState = .idle }
    }

    private func handleFaceSignals(_ signals: FaceAttentionSignals) {
        guard isRunning, !isPaused else { return }
        if calibrationSampleCount < FocusPostureCalibration.requiredSamples {
            guard signals.facePresent, !signals.eyesClosed, !signals.phoneDetected else {
                attentionState = .calibrating(calibrationSampleCount)
                return
            }
            let yaw = signals.yawRadians ?? 0
            guard abs(yaw) < 0.65 else {
                attentionState = .calibrating(calibrationSampleCount)
                return
            }
            calibrationYawSamples.append(yaw)
            calibrationSampleCount = calibrationYawSamples.count
            attentionState = .calibrating(calibrationSampleCount)
            if calibrationSampleCount == FocusPostureCalibration.requiredSamples {
                neutralYaw = FocusPostureCalibration.neutralYaw(from: calibrationYawSamples)
                attentionState = .focused
                endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            }
            return
        }

        let calibratedSignals = FaceAttentionSignals(
            facePresent: signals.facePresent,
            yawRadians: FocusPostureCalibration.calibratedYaw(signals.yawRadians, neutralYaw: neutralYaw),
            eyesClosed: signals.eyesClosed,
            gazeAway: signals.gazeAway,
            gazeDown: signals.gazeDown,
            phoneDetected: signals.phoneDetected,
            handsTogether: signals.handsTogether
        )
        guard let reason = FocusAttentionClassifier.distractionReason(for: calibratedSignals, mode: studyMode) else {
            if distractionBeganAt != nil {
                if focusRecoveryBeganAt == nil { focusRecoveryBeganAt = .now }
                guard let focusRecoveryBeganAt,
                      Date().timeIntervalSince(focusRecoveryBeganAt) >= focusRecoveryTime else { return }
            }
            distractionBeganAt = nil
            focusRecoveryBeganAt = nil
            alertedThisEpisode = false
            isCurrentlyDistracted = false
            attentionState = .focused
            releaseAngryAnimationWhenAllowed()
            return
        }

        isCurrentlyDistracted = true
        focusRecoveryBeganAt = nil
        if distractionBeganAt == nil { distractionBeganAt = .now }
        guard let distractionBeganAt else { return }
        if Date().timeIntervalSince(distractionBeganAt) < distractionGrace {
            attentionState = .distracted(reason)
            return
        }

        attentionState = .alerted(reason)
        guard !alertedThisEpisode else { return }
        alertedThisEpisode = true
        alertCount += 1
        activateAngryAnimation()
        playAlertSound()
    }

    private func resetAttention() {
        distractionBeganAt = nil
        focusRecoveryBeganAt = nil
        alertedThisEpisode = false
        isCurrentlyDistracted = false
        attentionState = .waiting
        angerReleaseTask?.cancel()
        angerReleaseTask = nil
        alertSound.stop()
        deactivateAngryAnimation()
    }

    private func resetCalibration() {
        calibrationYawSamples = []
        calibrationSampleCount = 0
        neutralYaw = 0
    }

    private func playAlertSound() {
        alertSound.play()
    }

    private func activateAngryAnimation() {
        guard !isAngryAnimationActive else { return }
        isAngryAnimationActive = true
        isNudgeVisible = true
        angryAnimationBeganAt = .now
        onLockStateChanged?(true)
        angerReleaseTask?.cancel()
        angerReleaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            angerReleaseTask = nil
            if !isCurrentlyDistracted { deactivateAngryAnimation() }
        }
    }

    private func releaseAngryAnimationWhenAllowed() {
        guard isAngryAnimationActive, let angryAnimationBeganAt else { return }
        if Date().timeIntervalSince(angryAnimationBeganAt) >= minimumAngryDuration {
            deactivateAngryAnimation()
        }
    }

    private func deactivateAngryAnimation() {
        guard isAngryAnimationActive else { return }
        isAngryAnimationActive = false
        isNudgeVisible = false
        angryAnimationBeganAt = nil
        onLockStateChanged?(false)
    }
}

private final class FocusAlertSound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var configured = false

    func play() {
        let sampleRate = 44_100.0
        let segmentDuration = 0.15
        let toneDuration = 0.12
        let frequencies = [720.0, 1_020.0, 720.0, 1_020.0, 840.0, 1_180.0]
        let frameCount = AVAudioFrameCount(sampleRate * segmentDuration * Double(frequencies.count))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return }

        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let segment = min(frequencies.count - 1, Int(time / segmentDuration))
            let localTime = time - Double(segment) * segmentDuration
            guard localTime < toneDuration else {
                samples[frame] = 0
                continue
            }
            let attack = min(1, localTime / 0.008)
            let release = min(1, (toneDuration - localTime) / 0.025)
            let frequency = frequencies[segment]
            let carrier = sin(2 * .pi * frequency * localTime)
            let metallicHarmonic = 0.32 * sin(2 * .pi * frequency * 2.02 * localTime)
            let roboticGate = sin(2 * .pi * 24 * localTime) > -0.15 ? 1.0 : 0.48
            samples[frame] = Float(0.25 * attack * release * roboticGate * (carrier + metallicHarmonic))
        }

        if !configured {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            configured = true
        }
        do {
            if !engine.isRunning { try engine.start() }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        } catch {
            NSSound.beep()
        }
    }

    func stop() {
        player.stop()
        engine.pause()
    }
}

private final class FaceAttentionMonitor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "TaskBuddy.FaceAttention", qos: .userInitiated)
    var onResult: ((FaceAttentionSignals) -> Void)?

    private let request = VNDetectFaceLandmarksRequest()
    private let classificationRequest: VNClassifyImageRequest = {
        let request = VNClassifyImageRequest()
        request.regionOfInterest = CGRect(x: 0.08, y: 0, width: 0.84, height: 0.72)
        return request
    }()
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()
    private var lastAnalysisTime: Double = 0
    private var lastClassificationTime: Double = -.infinity
    private var lastHandAnalysisTime: Double = -.infinity
    private var phoneEvidenceUntil: Double = 0
    private var handsTogetherUntil: Double = 0

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard timestamp - lastAnalysisTime >= 0.09 else { return }
        lastAnalysisTime = timestamp
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        do {
            var requests: [VNRequest] = [request]
            let classifyImage = timestamp - lastClassificationTime >= 0.8
            let detectHands = timestamp - lastHandAnalysisTime >= 0.27
            if classifyImage {
                lastClassificationTime = timestamp
                requests.append(classificationRequest)
            }
            if detectHands {
                lastHandAnalysisTime = timestamp
                requests.append(handRequest)
            }
            try VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up).perform(requests)

            if classifyImage, Self.containsPhone(classificationRequest.results) {
                phoneEvidenceUntil = timestamp + 1.4
            }
            if detectHands, Self.handsAreTogether(handRequest.results) {
                handsTogetherUntil = timestamp + 0.55
            }

            guard let face = request.results?.first else {
                onResult?(FaceAttentionSignals(facePresent: false))
                return
            }

            let landmarks = face.landmarks
            let eyeRatios = [landmarks?.leftEye, landmarks?.rightEye].compactMap(Self.eyeOpenness)
            let eyesClosed = eyeRatios.count == 2 && eyeRatios.reduce(0, +) / 2 < 0.12
            let gazePositions = [
                Self.pupilPosition(landmarks?.leftPupil, in: landmarks?.leftEye),
                Self.pupilPosition(landmarks?.rightPupil, in: landmarks?.rightEye)
            ].compactMap { $0 }
            let gazeAway = !gazePositions.isEmpty && gazePositions.contains { $0 < 0.18 || $0 > 0.82 }
            let verticalGazePositions = [
                Self.pupilVerticalPosition(landmarks?.leftPupil, in: landmarks?.leftEye),
                Self.pupilVerticalPosition(landmarks?.rightPupil, in: landmarks?.rightEye)
            ].compactMap { $0 }
            let gazeDown = verticalGazePositions.count == 2
                && verticalGazePositions.reduce(0, +) / 2 < 0.34

            onResult?(FaceAttentionSignals(
                facePresent: true,
                yawRadians: face.yaw?.doubleValue,
                eyesClosed: eyesClosed,
                gazeAway: gazeAway,
                gazeDown: gazeDown,
                phoneDetected: timestamp < phoneEvidenceUntil,
                handsTogether: timestamp < handsTogetherUntil
            ))
        } catch {
            onResult?(FaceAttentionSignals(facePresent: false))
        }
    }

    private static func eyeOpenness(_ region: VNFaceLandmarkRegion2D?) -> CGFloat? {
        guard let points = points(in: region), points.count >= 4 else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX > minX else { return nil }
        return (maxY - minY) / (maxX - minX)
    }

    private static func pupilPosition(
        _ pupil: VNFaceLandmarkRegion2D?,
        in eye: VNFaceLandmarkRegion2D?
    ) -> CGFloat? {
        guard let pupilPoints = points(in: pupil), let eyePoints = points(in: eye), !pupilPoints.isEmpty else { return nil }
        let eyeXs = eyePoints.map(\.x)
        guard let minX = eyeXs.min(), let maxX = eyeXs.max(), maxX > minX else { return nil }
        let pupilX = pupilPoints.map(\.x).reduce(0, +) / CGFloat(pupilPoints.count)
        return (pupilX - minX) / (maxX - minX)
    }

    private static func pupilVerticalPosition(
        _ pupil: VNFaceLandmarkRegion2D?,
        in eye: VNFaceLandmarkRegion2D?
    ) -> CGFloat? {
        guard let pupilPoints = points(in: pupil), let eyePoints = points(in: eye), !pupilPoints.isEmpty else { return nil }
        let eyeYs = eyePoints.map(\.y)
        guard let minY = eyeYs.min(), let maxY = eyeYs.max(), maxY > minY else { return nil }
        let pupilY = pupilPoints.map(\.y).reduce(0, +) / CGFloat(pupilPoints.count)
        return (pupilY - minY) / (maxY - minY)
    }

    private static func containsPhone(_ observations: [VNClassificationObservation]?) -> Bool {
        observations?.contains { observation in
            guard observation.confidence >= 0.12 else { return false }
            let name = observation.identifier.lowercased()
            return name.contains("cellular phone")
                || name.contains("cellular telephone")
                || name.contains("cellphone")
                || name.contains("mobile phone")
                || name.contains("smartphone")
        } ?? false
    }

    private static func handsAreTogether(_ observations: [VNHumanHandPoseObservation]?) -> Bool {
        guard let observations, observations.count >= 2 else { return false }
        let wrists = observations.prefix(2).compactMap { observation -> CGPoint? in
            guard let point = try? observation.recognizedPoint(.wrist), point.confidence >= 0.3 else { return nil }
            return point.location
        }
        guard wrists.count == 2 else { return false }
        let distance = hypot(wrists[0].x - wrists[1].x, wrists[0].y - wrists[1].y)
        let midpoint = CGPoint(x: (wrists[0].x + wrists[1].x) / 2, y: (wrists[0].y + wrists[1].y) / 2)
        return distance < 0.30 && (0.22...0.78).contains(midpoint.x) && midpoint.y < 0.68
    }

    private static func points(in region: VNFaceLandmarkRegion2D?) -> [CGPoint]? {
        guard let region else { return nil }
        return region.normalizedPoints
    }
}

struct FocusCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> FocusCameraView {
        FocusCameraView(session: session)
    }

    func updateNSView(_ nsView: FocusCameraView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class FocusCameraView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
