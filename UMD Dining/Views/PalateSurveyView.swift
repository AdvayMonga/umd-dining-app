import SwiftUI

struct CuisineOption: Identifiable {
    let id: String
    let label: String
    let description: String
}

struct CuisineCategory: Identifiable {
    let id = UUID()
    let title: String
    let options: [CuisineOption]
}

private let cuisineCategories: [CuisineCategory] = [
    CuisineCategory(title: "Global Palette", options: [
        CuisineOption(id: "asian",         label: "Asian",               description: "Stir fry, rice bowls, noodles"),
        CuisineOption(id: "mexican",       label: "Mexican/Latin",       description: "Burritos, tacos, quesadillas"),
        CuisineOption(id: "italian",       label: "Italian/Mediterranean", description: "Pasta, pizza, salads"),
        CuisineOption(id: "indian",        label: "Indian",              description: "Curry, tikka, biryani"),
    ]),
    CuisineCategory(title: "Comfort & Classic", options: [
        CuisineOption(id: "comfort",   label: "American/Comfort", description: "Burgers, fries, mac & cheese"),
        CuisineOption(id: "southern",  label: "Southern/Soul",    description: "Fried chicken, cornbread, BBQ"),
        CuisineOption(id: "breakfast", label: "Breakfast/Brunch", description: "Pancakes, eggs, waffles"),
        CuisineOption(id: "healthy",   label: "Healthy/Fresh",    description: "Salads, grain bowls, smoothies"),
    ]),
]

struct PalateSurveyView: View {
    var onComplete: () -> Void
    var isOnboarding: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var showNextScreen = false

    var body: some View {
        if isOnboarding {
            onboardingLayout
        } else {
            profileLayout
        }
    }

    // MARK: - Profile layout (nav-pushed page)

    private var profileLayout: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerImage

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(cuisineCategories) { category in
                        categorySection(category)
                    }
                    applyButton
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.umdRed)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                Spacer()
                Text("Cuisine Preferences")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
                    .padding(.trailing, 8)
            }
            .frame(height: 44)
            .background(Color(.systemBackground))
            .overlay(alignment: .bottom) { Divider() }
        }
        .onAppear {
            selected = Set(UserPreferences.shared.cuisinePrefs)
        }
    }

    // MARK: - Header image

    private var headerImage: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.07, blue: 0.07), Color(red: 0.35, green: 0.10, blue: 0.10)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .overlay {
                ZStack {
                    Circle()
                        .fill(Color.umdRed.opacity(0.18))
                        .frame(width: 200, height: 200)
                        .offset(x: 90, y: -20)
                    Circle()
                        .fill(Color.umdRed.opacity(0.10))
                        .frame(width: 130, height: 130)
                        .offset(x: -50, y: 35)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.07))
                        .offset(x: 100, y: -5)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Your Taste Profile")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                    .kerning(0.5)
                Text("Cuisine Preferences")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .clipped()
    }

    // MARK: - Onboarding layout

    private var onboardingLayout: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 24)

            Text("What do you like to eat?")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.umdRed)

            Text("Pick your favorite cuisines to personalize your feed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            Spacer().frame(height: 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(cuisineCategories) { category in
                        categorySection(category)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Spacer()

            VStack(spacing: 12) {
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
                .animation(.easeInOut(duration: 0.25), value: selected.isEmpty)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selected.removeAll()
                    }
                } label: {
                    Text("Clear All")
                        .font(.headline)
                        .foregroundStyle(selected.isEmpty ? Color.gray.opacity(0.4) : Color.umdRed)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selected.isEmpty ? Color.gray.opacity(0.2) : Color.umdRed.opacity(0.5), lineWidth: 1.5)
                        )
                }
                .disabled(selected.isEmpty)
                .animation(.easeInOut(duration: 0.25), value: selected.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
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

    // MARK: - Category section

    private func categorySection(_ category: CuisineCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.umdRed)
                    .frame(width: 3, height: 16)
                    .clipShape(Capsule())
                Text(category.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .padding(.leading, 8)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(category.options) { option in
                    cuisineCard(option)
                }
            }
        }
    }

    // MARK: - Cuisine card

    private func cuisineCard(_ option: CuisineOption) -> some View {
        let isSelected = selected.contains(option.id)
        return Button {
            if isSelected {
                selected.remove(option.id)
            } else {
                selected.insert(option.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? Color.umdRed : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(option.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.vertical, 13)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.umdRed.opacity(0.08) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.umdRed : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Apply button

    private var applyButton: some View {
        Button {
            UserPreferences.shared.cuisinePrefs = Array(selected)
            onComplete()
            dismiss()
        } label: {
            Text("Save & Continue")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.umdRed)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        PalateSurveyView(onComplete: {}, isOnboarding: false)
    }
}
