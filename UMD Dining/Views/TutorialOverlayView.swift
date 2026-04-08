import SwiftUI

struct TutorialOverlayView: View {
    @Binding var isShowing: Bool
    @State private var step = 0
    @AppStorage("isDarkMode") private var isDarkMode = true

    var body: some View {
        ZStack {
            // Dark scrim
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            if step == 0 {
                foodCardStep
                    .transition(.opacity)
            } else {
                tabBarStep
                    .transition(.opacity)
            }

            // "Tap anywhere to continue" hint
            Text("Tap anywhere to continue")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .offset(y: 40)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                if step == 0 {
                    step = 1
                } else {
                    isShowing = false
                }
            }
        }
    }

    // MARK: - Frame 1: Food Card

    private var foodCardStep: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 80)

            // Mock food card
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cheese Pizza")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        mockTag("Recommended", color: .teal)
                        mockTag("High Protein", color: .purple)
                    }

                    Text("Ciao Pizza \u{00B7} 251 North")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        dietaryPill("Gluten", color: .gray)
                        dietaryPill("Dairy", color: .gray)
                        dietaryPill("Egg", color: .gray)
                        dietaryPill("V", color: .green)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.umdRed)
                        .font(.title3)
                    Image(systemName: "heart")
                        .foregroundStyle(.gray)
                        .font(.title3)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .shadow(color: .gray.opacity(0.15), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 24)

            // Explanation
            VStack(spacing: 14) {
                tutorialBullet(icon: "hand.tap", text: "Tap for nutrition info")
                tutorialBullet(icon: "plus.circle", text: "Log what you eat")
                tutorialBullet(icon: "heart", text: "Double tap to favorite")
            }
            .padding(24)
            .background(Color(.systemBackground).opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Frame 2: Tab Bar

    private var tabBarStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Explanation
            VStack(spacing: 14) {
                tutorialBullet(icon: "chart.bar.fill", text: "Track logged foods")
                tutorialBullet(icon: "person", text: "Edit taste & dietary preferences")
            }
            .padding(24)
            .background(Color(.systemBackground).opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            // Mock tab bar
            HStack {
                mockTab(icon: "fork.knife", label: "Home", isSelected: true)
                Spacer()
                mockTab(icon: "chart.bar.fill", label: "Tracker", isSelected: false)
                Spacer()
                mockTab(icon: "person", label: "Profile", isSelected: false)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Helper Views

    private func tutorialBullet(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.umdRed)
                .frame(width: 28)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func mockTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func dietaryPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func mockTab(icon: String, label: String, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(isSelected ? Color.umdRed : .secondary)
    }
}

#Preview("Step 1 — Food Card") {
    TutorialOverlayView(isShowing: .constant(true))
}

#Preview("Step 2 — Tab Bar") {
    TutorialOverlayView(isShowing: .constant(true))
        .onAppear {} // Note: tap once in preview to advance to step 2
}
