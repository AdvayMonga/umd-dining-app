import SwiftUI

struct CuisineOption: Identifiable {
    let id: String
    let label: String
    let icon: String
    let description: String
}

struct PalateSurveyView: View {
    var onComplete: () -> Void
    var isOnboarding: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var showNextScreen = false

    private let cuisines: [CuisineOption] = [
        CuisineOption(id: "comfort", label: "American/Comfort", icon: "🍔", description: "Burgers, fries, mac & cheese"),
        CuisineOption(id: "asian", label: "Asian", icon: "🍜", description: "Stir fry, rice bowls, noodles"),
        CuisineOption(id: "mexican", label: "Mexican/Latin", icon: "🌮", description: "Burritos, tacos, quesadillas"),
        CuisineOption(id: "italian", label: "Italian/Mediterranean", icon: "🍝", description: "Pasta, pizza, salads"),
        CuisineOption(id: "indian", label: "Indian", icon: "🍛", description: "Curry, tikka, biryani"),
        CuisineOption(id: "southern", label: "Southern/Soul", icon: "🍗", description: "Fried chicken, cornbread, BBQ"),
        CuisineOption(id: "breakfast", label: "Breakfast/Brunch", icon: "🥞", description: "Pancakes, eggs, waffles"),
        CuisineOption(id: "healthy", label: "Healthy/Fresh", icon: "🥗", description: "Salads, grain bowls, smoothies"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            Text("What do you like to eat?")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.umdRed)

            Text("Pick your favorite cuisines to personalize your feed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer().frame(height: 24)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(cuisines) { cuisine in
                        cuisineCard(cuisine)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            Button {
                UserPreferences.shared.cuisinePrefs = Array(selected)
                if isOnboarding {
                    showNextScreen = true
                } else {
                    onComplete()
                    dismiss()
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(selected.isEmpty ? Color.gray : Color.umdRed)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selected.isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            selected = Set(UserPreferences.shared.cuisinePrefs)
        }
        .fullScreenCover(isPresented: $showNextScreen) {
            DiningHallSurveyView {
                onComplete()
                dismiss()
            }
        }
    }

    private func cuisineCard(_ cuisine: CuisineOption) -> some View {
        let isSelected = selected.contains(cuisine.id)
        return Button {
            if isSelected {
                selected.remove(cuisine.id)
            } else {
                selected.insert(cuisine.id)
            }
        } label: {
            VStack(spacing: 8) {
                Text(cuisine.icon)
                    .font(.system(size: 36))
                Text(cuisine.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(cuisine.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.umdRed.opacity(0.12) : Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.umdRed : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PalateSurveyView(onComplete: {})
}
