import Foundation
import AVFoundation
import Observation

/// Records voice notes as .m4a files in the app's media directory.
@Observable
final class VoiceNoteRecorder {
    enum Phase: Equatable {
        case idle
        case denied
        case recording
        case recorded
    }

    var phase: Phase = .idle
    var elapsed: TimeInterval = 0
    private(set) var fileURL: URL?

    private var recorder: AVAudioRecorder?
    private var ticker: Task<Void, Never>?

    /// Asks for microphone permission (first time) and starts recording.
    func requestAndStart() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            phase = .denied
            return
        }
        start()
    }

    private func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let url = MediaStore.mediaDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let newRecorder = try? AVAudioRecorder(url: url, settings: settings) else { return }

        recorder = newRecorder
        fileURL = url
        elapsed = 0
        newRecorder.record()
        phase = .recording

        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.phase == .recording, let recorder = self.recorder else { return }
                self.elapsed = recorder.currentTime
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        if let recorder {
            elapsed = recorder.currentTime
            recorder.stop()
        }
        self.recorder = nil
        phase = fileURL == nil ? .idle : .recorded
    }

    /// Stops and deletes the take, ready to start over.
    func discard() {
        ticker?.cancel()
        ticker = nil
        recorder?.stop()
        recorder = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        elapsed = 0
        phase = .idle
    }
}

/// Plays voice notes one at a time, downloading remote ones on demand.
@Observable
final class VoiceNotePlayer {
    static let shared = VoiceNotePlayer()

    private(set) var activeNoteID: UUID?
    private(set) var loadingNoteID: UUID?

    private var player: AVAudioPlayer?
    private let delegate = VoiceNotePlayerDelegate()

    func toggle(_ note: VoiceNote) async {
        if activeNoteID == note.id {
            stop()
            return
        }
        stop()
        guard let url = URL(string: note.audioURL) else { return }

        loadingNoteID = note.id
        defer { loadingNoteID = nil }

        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                (data, _) = try await URLSession.shared.data(from: url)
            }
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback)
            try? session.setActive(true)

            let newPlayer = try AVAudioPlayer(data: data)
            newPlayer.delegate = delegate
            player = newPlayer
            newPlayer.play()
            activeNoteID = note.id
        } catch {
            activeNoteID = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        activeNoteID = nil
    }

    fileprivate func playbackFinished() {
        player = nil
        activeNoteID = nil
    }
}

/// Bounces the finish callback from the audio thread back to the main actor.
nonisolated final class VoiceNotePlayerDelegate: NSObject, AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            VoiceNotePlayer.shared.playbackFinished()
        }
    }
}

/// "0:42" style duration text shared by the recorder and note rows.
nonisolated enum VoiceNoteFormat {
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
