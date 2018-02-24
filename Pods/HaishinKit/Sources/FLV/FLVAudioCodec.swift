import Foundation
import AVFoundation

public enum FLVAudioCodec: UInt8 {
    case pcm           = 0
    case adpcm         = 1
    case mp3           = 2
    case pcmle         = 3
    case nellymoser16K = 4
    case nellymoser8K  = 5
    case nellymoser    = 6
    case g711A         = 7
    case g711MU        = 8
    case aac           = 10
    case speex         = 11
    case mp3_8k        = 14
    case unknown       = 0xFF

    var isSupported: Bool {
        switch self {
        case .pcm:
            return false
        case .adpcm:
            return false
        case .mp3:
            return false
        case .pcmle:
            return false
        case .nellymoser16K:
            return false
        case .nellymoser8K:
            return false
        case .nellymoser:
            return false
        case .g711A:
            return false
        case .g711MU:
            return false
        case .aac:
            return true
        case .speex:
            return false
        case .mp3_8k:
            return false
        case .unknown:
            return false
        }
    }

    var formatID: AudioFormatID {
        switch self {
        case .pcm:
            return kAudioFormatLinearPCM
        case .mp3:
            return kAudioFormatMPEGLayer3
        case .pcmle:
            return kAudioFormatLinearPCM
        case .aac:
            return kAudioFormatMPEG4AAC
        case .mp3_8k:
            return kAudioFormatMPEGLayer3
        default:
            return 0
        }
    }

    var headerSize: Int {
        switch self {
        case .aac:
            return 2
        default:
            return 1
        }
    }
}
