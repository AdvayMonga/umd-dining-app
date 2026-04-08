import SwiftUI

enum DietaryStyles {

    // MARK: - Tag Pills (Favorite, Trending, Recommended, High Protein)

    static func tagColor(for tag: String) -> Color {
        switch tag {
        case "Favorite":     return .pink
        case "Trending":     return .orange
        case "Recommended":  return .teal
        case "High Protein": return .blue
        default:             return .gray
        }
    }

    static func tagLabel(for tag: String) -> String {
        tag.replacingOccurrences(of: "HalalFriendly", with: "Halal")
           .replacingOccurrences(of: "Contains ", with: "")
    }

    static func tagIcon(for tag: String) -> String? {
        switch tag {
        case "Favorite":     return "heart.fill"
        case "Recommended":  return "star.fill"
        case "Trending":     return "flame.fill"
        case "High Protein": return "dumbbell.fill"
        default:             return nil
        }
    }

    // MARK: - Dietary Icon Pills (vegan, vegetarian, HalalFriendly, allergens)

    static func dietaryColor(for icon: String) -> Color {
        switch icon {
        case "vegan", "vegetarian": return .green
        case "HalalFriendly":       return .purple
        default:                    return .gray
        }
    }

    static func dietaryLabel(for icon: String) -> String {
        switch icon {
        case "HalalFriendly":       return "Halal"
        case "vegan":               return "V"
        case "vegetarian":          return "VG"
        case "Contains dairy":      return "Dairy"
        case "Contains egg":        return "Egg"
        case "Contains fish":       return "Fish"
        case "Contains gluten":     return "Gluten"
        case "Contains nuts":       return "Nuts"
        case "Contains Shellfish":  return "Shellfish"
        case "Contains sesame":     return "Sesame"
        case "Contains soy":       return "Soy"
        default:                    return icon
        }
    }

    /// Whether a dietary icon represents an allergen (not a lifestyle choice like vegan/vegetarian or halal)
    static func isAllergen(_ icon: String) -> Bool {
        switch icon {
        case "vegan", "vegetarian", "HalalFriendly":
            return false
        default:
            return true
        }
    }
}
