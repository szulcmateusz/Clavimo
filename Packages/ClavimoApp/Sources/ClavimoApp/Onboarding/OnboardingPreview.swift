import SwiftUI

/// Shows one onboarding step, for screenshots.
struct OnboardingPreview: View {
    let agent: AgentController
    let editor: ConfigEditor
    let step: OnboardingView.Step

    var body: some View {
        OnboardingView(agent: agent, editor: editor, finish: {}, step: step)
    }
}
