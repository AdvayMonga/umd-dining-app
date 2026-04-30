import SwiftUI

enum DietaryStyles {

    // MARK: - Tag Pills (smart tags from item.tags)

    static func tagColor(for tag: String) -> Color {
        return Color(red: 107/255, green: 114/255, blue: 128/255)
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
        case "vegetarian", "vegan", "HalalFriendly": return Color.umdRed
        default: return Color(red: 180/255, green: 83/255, blue: 9/255) // amber-700
        }
    }

    static func dietaryBgColor(for icon: String) -> Color {
        switch icon {
        case "vegetarian", "vegan", "HalalFriendly": return Color.umdRed.opacity(0.08)
        default: return Color(red: 255/255, green: 251/255, blue: 235/255) // amber-50
        }
    }

    static func dietaryLabel(for icon: String) -> String {
        switch icon {
        case "HalalFriendly":       return "Halal"
        case "vegan":               return "VG"
        case "vegetarian":          return "V"
        case "Contains dairy":      return "Dairy"
        case "Contains egg":        return "Egg"
        case "Contains fish":       return "Fish"
        case "Contains gluten":     return "Gluten"
        case "Contains nuts":       return "Nuts"
        case "Contains Shellfish":  return "Shellfish"
        case "Contains sesame":     return "Sesame"
        case "Contains soy":        return "Soy"
        default:                    return icon
        }
    }

    /// Whether a dietary icon represents an allergen (not a lifestyle choice)
    static func isAllergen(_ icon: String) -> Bool {
        switch icon {
        case "vegan", "vegetarian", "HalalFriendly":
            return false
        default:
            return true
        }
    }

    // MARK: - Compact Badge Labels

    static func dietaryShortLabel(for icon: String) -> String {
        switch icon {
        case "vegan":         return "VG"
        case "vegetarian":    return "V"
        case "HalalFriendly": return "HF"
        default:              return icon
        }
    }

    static func allergenAbbrev(for icon: String) -> String {
        switch icon {
        case "Contains dairy":     return "Dairy"
        case "Contains egg":       return "Egg"
        case "Contains fish":      return "Fish"
        case "Contains gluten":    return "GF"
        case "Contains nuts":      return "Nuts"
        case "Contains Shellfish": return "Shellfish"
        case "Contains sesame":    return "Sesame"
        case "Contains soy":       return "Soy"
        default:                   return icon.replacingOccurrences(of: "Contains ", with: "")
        }
    }
}
