import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack {
            if page == 0 {
                PalateSurveyView(onComplete: { nextPage() }, isOnboarding: false)
                    .transition(.opacity)
            } else if page == 1 {
                DiningHallSurveyView(onComplete: { nextPage() }, isOnboarding: false)
                    .transition(.opacity)
            } else {
                AllergenSurveyView(onComplete: { onComplete() })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: page)
    }

    private func nextPage() {
        page += 1
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
