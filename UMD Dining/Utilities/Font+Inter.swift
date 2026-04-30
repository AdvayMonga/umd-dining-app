import SwiftUI

extension Font {
    static func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black:
            name = "Inter18pt-Bold"
        case .semibold:
            name = "Inter18pt-SemiBold"
        case .medium:
            name = "Inter18pt-Medium"
        default:
            name = "Inter18pt-Regular"
        }
        return .custom(name, size: size)
    }
}
