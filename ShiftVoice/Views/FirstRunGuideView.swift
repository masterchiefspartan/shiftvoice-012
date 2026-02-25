import SwiftUI

struct FirstRunGuideView: View {
    let onStartRecording: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: Int = 0
    @State private var animateIcon: Bool = false

    private let steps: [FirstRunStep] = [
        FirstRunStep(
            icon: "mic.fill",
            iconColor: Color(red: 29/255, green: 78/255, blue: 216/255),
            iconBackground: Color(red: 29/255, green: 78/255, blue: 216/255).opacity(0.1),
            title: "Just tap and talk",
            subtitle: "Record shift notes the natural way — describe what happened in your own words, without typing or filling out forms.",
            detail: "\"Fryer went down at 6pm, vendor called, should be fixed by open.\""
        ),
        FirstRunStep(
            icon: "wand.and.sparkles",
            iconColor: Color(red: 124/255, green: 58/255, blue: 237/255),
            iconBackground: Color(red: 124/255, green: 58/255, blue: 237/255).opacity(0.1),
            title: "AI structures everything",
            subtitle: "ShiftVoice automatically extracts action items, urgency levels, and categories from your voice — no manual tagging needed.",
            detail: "Equipment issue · Immediate · Assigned to kitchen team"
        ),
        FirstRunStep(
            icon: "person.2.fill",
            iconColor: Color(red: 22/255, green: 163/255, blue: 74/255),
            iconBackground: Color(red: 22/255, green: 163/255, blue: 74/255).opacity(0.1),
            title: "Your whole team stays in sync",
            subtitle: "Incoming shifts see exactly what happened. Action items carry forward until resolved. Nothing falls through the cracks.",
            detail: "3 open items · Last updated 2 min ago"
        )
    ]

    var body: some View {
        ZStack {
            SVTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                stepContent
                    .padding(.horizontal, 32)

                Spacer()

                bottomControls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.3).delay(0.2)) {
                animateIcon = true
            }
        }
    }

    private var stepContent: some View {
        let step = steps[currentStep]
        return VStack(spacing: 32) {
            iconView(step: step)

            VStack(spacing: 12) {
                Text(step.title)
                    .font(.system(.title, design: .serif, weight: .bold))
                    .foregroundStyle(SVTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .tracking(-0.3)

                Text(step.subtitle)
                    .font(.body)
                    .foregroundStyle(SVTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            detailPill(text: step.detail)
        }
        .id(currentStep)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private func iconView(step: FirstRunStep) -> some View {
        ZStack {
            Circle()
                .fill(step.iconBackground)
                .frame(width: 96, height: 96)
                .scaleEffect(animateIcon ? 1 : 0.6)
                .opacity(animateIcon ? 1 : 0)

            Image(systemName: step.icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(step.iconColor)
                .scaleEffect(animateIcon ? 1 : 0.4)
                .opacity(animateIcon ? 1 : 0)
        }
        .onChange(of: currentStep) { _, _ in
            animateIcon = false
            withAnimation(.spring(duration: 0.5, bounce: 0.4).delay(0.15)) {
                animateIcon = true
            }
        }
    }

    private func detailPill(text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(SVTheme.successGreen)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(SVTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SVTheme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(SVTheme.surfaceBorder, lineWidth: 1))
    }

    private var bottomControls: some View {
        VStack(spacing: 20) {
            stepIndicator

            if currentStep < steps.count - 1 {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        currentStep += 1
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Next")
                            .font(.body.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(SVTheme.textPrimary)
                    .clipShape(.rect(cornerRadius: 14))
                }
                .sensoryFeedback(.selection, trigger: currentStep)
            } else {
                Button {
                    onStartRecording()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.body.weight(.semibold))
                        Text("Record Your First Note")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(SVTheme.accent)
                    .clipShape(.rect(cornerRadius: 14))
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: true)
            }

            Button {
                dismiss()
            } label: {
                Text(currentStep < steps.count - 1 ? "Skip" : "Maybe later")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textTertiary)
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<steps.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentStep ? SVTheme.textPrimary : SVTheme.surfaceBorder)
                    .frame(width: index == currentStep ? 20 : 6, height: 6)
                    .animation(.spring(duration: 0.3), value: currentStep)
            }
        }
    }
}

private struct FirstRunStep {
    let icon: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let subtitle: String
    let detail: String
}
