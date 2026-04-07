import SwiftUI

struct DiningHallSurveyView: View {
    var onComplete: () -> Void
    var isOnboarding: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var showAllergens = false

    private let halls: [(id: String, name: String)] = [
        ("19", "Yahentamitsi"),
        ("51", "251 North"),
        ("16", "South Campus Diner"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            Text("Which dining halls do you go to most?")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.umdRed)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("We'll prioritize food from your favorite halls")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer().frame(height: 24)

            VStack(spacing: 12) {
                ForEach(halls, id: \.id) { hall in
                    hallCard(id: hall.id, name: hall.name)
                }
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    UserPreferences.shared.preferredDiningHalls = selected
                    if isOnboarding { showAllergens = true } else { onComplete(); dismiss() }
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

                Button {
                    UserPreferences.shared.preferredDiningHalls = []
                    if isOnboarding { showAllergens = true } else { onComplete(); dismiss() }
                } label: {
                    Text("No Preference")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            selected = UserPreferences.shared.preferredDiningHalls
        }
        .fullScreenCover(isPresented: $showAllergens) {
            AllergenSurveyView {
                onComplete()
                dismiss()
            }
        }
    }

    private func hallCard(id: String, name: String) -> some View {
        let isSelected = selected.contains(id)
        return Button {
            if isSelected {
                selected.remove(id)
            } else {
                selected.insert(id)
            }
        } label: {
            Text(name)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
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
    DiningHallSurveyView(onComplete: {})
}
