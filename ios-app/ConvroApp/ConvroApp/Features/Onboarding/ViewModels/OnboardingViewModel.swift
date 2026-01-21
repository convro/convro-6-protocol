import SwiftUI

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var isLoading: Bool = false

    func nextStep() {
        switch currentStep {
        case .welcome: currentStep = .permissions
        case .permissions: currentStep = .deviceSetup
        case .deviceSetup: break // Complete
        }
    }
}

enum OnboardingStep {
    case welcome
    case permissions
    case deviceSetup
}
