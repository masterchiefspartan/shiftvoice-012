import SwiftUI

struct OnboardingAIRevealView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var revealed: Bool = false
    @State private var visibleSampleItemCount: Int = 0

    private let sampleItems: [(icon: String, text: String)] = [
        ("thermometer.high", "Cooler temp peaked at 43°F after delivery unload"),
        ("fish", "Salmon pan needs a date label before service"),
        ("person.crop.circle.badge.checkmark", "Sarah training: shadow expo for first hour")
    ]

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
                Text(viewModel.usedSamplePath ? "Start my free trial" : "Continue")
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
        .task {
            withAnimation(.easeOut(duration: 0.45).delay(0.3)) {
                revealed = true
            }
            guard viewModel.usedSamplePath else { return }
            for index in sampleItems.indices {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.spring(duration: 0.45)) {
                    visibleSampleItemCount = index + 1
                }
            }
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw transcript")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SVTheme.textTertiary)
            Text("\"Cooler temp hit 43 after delivery. The salmon pan still needs a date label. Sarah should shadow expo before dinner.\"")
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

            if viewModel.usedSamplePath {
                ForEach(Array(sampleItems.prefix(visibleSampleItemCount).enumerated()), id: \.offset) { _, item in
                    Label(item.text, systemImage: item.icon)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                Label("Staffing: 2 call-outs on night shift", systemImage: "person.2.fill")
                Label("Urgent: Fridge temperature drifting high", systemImage: "thermometer.high")
                Label("Action: Assign maintenance before morning", systemImage: "checkmark.circle.fill")
            }
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
