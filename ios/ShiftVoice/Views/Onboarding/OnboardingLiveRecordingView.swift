import SwiftUI

struct OnboardingLiveRecordingView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            waveform

            Text(formattedTime)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(SVTheme.textPrimary)

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    viewModel.continueFromLiveRecording()
                }
            } label: {
                Text("Stop")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 160, height: 52)
                    .background(SVTheme.urgentRed)
                    .clipShape(.rect(cornerRadius: 12))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear {
            pulse = true
        }
        .task {
            while viewModel.currentStep == 5 {
                try? await Task.sleep(for: .seconds(1))
                guard viewModel.currentStep == 5 else { return }
                viewModel.recordingSeconds += 1
            }
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(SVTheme.accent.opacity(0.9))
                    .frame(width: 8, height: pulse ? CGFloat(20 + (index % 5) * 12) : 18)
                    .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(index) * 0.05), value: pulse)
            }
        }
        .frame(height: 92)
    }

    private var formattedTime: String {
        let minutes: Int = viewModel.recordingSeconds / 60
        let seconds: Int = viewModel.recordingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
