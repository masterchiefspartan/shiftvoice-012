import SwiftUI

struct OnboardingAIRevealView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var revealed: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Text("AI Structuring Reveal")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(SVTheme.textPrimary)

                Text("Your voice update transforms into clean, actionable handoff items.")
                    .font(.system(size: 15))
                    .foregroundStyle(SVTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                transcriptCard
                Image(systemName: "arrow.down")
                    .foregroundStyle(SVTheme.textTertiary)
                    .opacity(revealed ? 1 : 0)
                structuredCard
            }

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    viewModel.continueFromAIReveal()
                }
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(SVTheme.accent)
                    .clipShape(.rect(cornerRadius: 12))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45).delay(0.3)) {
                revealed = true
            }
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw transcript")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SVTheme.textTertiary)
            Text("\"Night shift had two call-outs. Fridge temp is drifting high. Need maintenance before morning handoff.\"")
                .font(.system(size: 14))
                .foregroundStyle(SVTheme.textSecondary)
        }
        .padding(14)
        .background(SVTheme.surface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SVTheme.surfaceBorder, lineWidth: 1))
        .opacity(revealed ? 0.35 : 1)
        .scaleEffect(revealed ? 0.98 : 1)
    }

    private var structuredCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Structured output")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SVTheme.textTertiary)
            Label("Staffing: 2 call-outs on night shift", systemImage: "person.2.fill")
            Label("Urgent: Fridge temperature drifting high", systemImage: "thermometer.high")
            Label("Action: Assign maintenance before morning", systemImage: "checkmark.circle.fill")
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(SVTheme.textPrimary)
        .padding(14)
        .background(SVTheme.accent.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SVTheme.accent.opacity(0.35), lineWidth: 1))
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 18)
    }
}
