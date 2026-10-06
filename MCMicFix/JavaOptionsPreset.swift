import Foundation

enum JavaOptionsPreset: String, CaseIterable, Identifiable {
    case none
    case coreAudioMixer
    case opengl
    case coreAudioAndOpenGL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .coreAudioMixer: return "javax.sound → Apple CoreAudio (legacy)"
        case .opengl: return "Java2D OpenGL (legacy)"
        case .coreAudioAndOpenGL: return "CoreAudio + OpenGL (legacy)"
        }
    }

    /// Values applied only when the Advanced Java-options toggle is on.
    /// These are optional and are NOT required for the mic fix.
    var jvmFlags: String? {
        switch self {
        case .none:
            return nil
        case .coreAudioMixer:
            return "-Djava.sound.mixer=Apple CoreAudio"
        case .opengl:
            return "-Dsun.java2d.opengl=true"
        case .coreAudioAndOpenGL:
            return "-Djava.sound.mixer=Apple CoreAudio -Dsun.java2d.opengl=true"
        }
    }
}
