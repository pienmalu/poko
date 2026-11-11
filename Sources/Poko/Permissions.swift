import AVFoundation
import AppKit
import ApplicationServices

/// 要る許可は2つだけ。
/// - アクセシビリティ: どのアプリでもキーの押し離しを受け取り、⌘V を送るため
/// - マイク: 押している間に録るため
@MainActor
enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }

    static var microphone: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    /// まだ許可されていなければ、システムの案内を出す。
    static func askForAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func askForMicrophone() async -> Bool {
        switch microphone {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private static func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}
