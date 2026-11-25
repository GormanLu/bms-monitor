import Foundation
import AVFoundation

// 语音：导航转弯、每公里播报、低电量和高温提醒都用它。说话时把别的 app（音乐、高德）的声音调小，说完还回去。
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    var hold = false          // 声浪开着时说完话不要把音频关掉

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ s: String) {
        guard !s.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        if !hold { try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]) }
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: s)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.52
        synth.speak(u)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking && !hold {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
