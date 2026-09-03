import Foundation

enum ImageError: LocalizedError {
    case unreadable
    case storeUnavailable
    case storeLocked
    case tooLarge(Int)

    /// Well beyond what a sticky note needs, and a guard against a stray
    /// multi-gigabyte file being pulled into memory.
    static let maximumSourceBytes = 60 * 1024 * 1024

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "That file isn't an image Stick Pad can read."
        case .storeUnavailable:
            return "Stick Pad hasn't finished unlocking your notes yet."
        case .storeLocked:
            return "Your notes are locked, so images can't be added right now."
        case .tooLarge(let bytes):
            let mb = bytes / (1024 * 1024)
            return "That image is \(mb) MB, which is too large to add to a note."
        }
    }
}
