import AppKit

/// Stable IDs are persisted; display names can change without losing a choice.
enum PetCharacter: String, CaseIterable {
    case deepseek, gpt, claude, gemini

    var displayName: String {
        switch self {
        case .deepseek: return "蓝色大肥鱼"
        case .gpt: return "GPT龙娘"
        case .claude: return "大小姐Claude"
        case .gemini: return "北美猫娘Gemini"
        }
    }

    var resourceName: String {
        self == .deepseek ? "sprite.png" : "sprite-\(rawValue).png"
    }

    /// Safe text corners measured in each 1536 × 1024 PNG, from the upper-left.
    /// All text stays inside the screen and clear of the bezel and fingers.
    var tabletCorners: (topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint) {
        switch self {
        case .deepseek, .gpt, .claude:
            return (CGPoint(x: 1060, y: 699), CGPoint(x: 1413, y: 644), CGPoint(x: 1090, y: 889))
        case .gemini:
            // Gemini's right fingers reach farther into the screen.
            return (CGPoint(x: 1065, y: 699), CGPoint(x: 1400, y: 646), CGPoint(x: 1095, y: 889))
        }
    }
}
