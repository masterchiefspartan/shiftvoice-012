import SwiftUI

struct SVSegmentedControl<ID: Hashable>: View {
    let items: [(id: ID, label: String, icon: String?)]
    @Binding var selection: ID

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.id) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selection = item.id
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = item.icon {
                            Image(systemName: icon)
                                .font(.caption2.weight(.semibold))
                        }
                        Text(item.label)
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selection == item.id ? SVTheme.chipSelectedText : SVTheme.textSecondary)
                    .background(selection == item.id ? SVTheme.chipSelected : Color.clear)
                    .clipShape(.rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(SVTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }
}

struct SVChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    var selectedColor: Color? = nil
    let action: () -> Void

    private var resolvedSelectedColor: Color {
        selectedColor ?? SVTheme.chipSelected
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.medium))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, SVTheme.Sizing.chipHorizontalPadding)
            .padding(.vertical, SVTheme.Sizing.chipVerticalPadding)
            .background(isSelected ? resolvedSelectedColor : SVTheme.surface)
            .foregroundStyle(isSelected ? (selectedColor != nil ? .white : SVTheme.chipSelectedText) : SVTheme.textSecondary)
            .clipShape(.rect(cornerRadius: SVTheme.Sizing.chipCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SVTheme.Sizing.chipCornerRadius)
                    .stroke(isSelected ? Color.clear : SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SVSmallChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    var selectedColor: Color? = nil
    let action: () -> Void

    private var resolvedSelectedColor: Color {
        selectedColor ?? SVTheme.chipSelected
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                }
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? resolvedSelectedColor : SVTheme.surface)
            .foregroundStyle(isSelected ? (selectedColor != nil ? .white : SVTheme.chipSelectedText) : SVTheme.textSecondary)
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.clear : SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SVPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.body.weight(.semibold))
                    }
                    Text(title)
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: SVTheme.Sizing.buttonHeight)
            .background(isDisabled ? SVTheme.accent.opacity(0.5) : SVTheme.accent)
            .clipShape(.rect(cornerRadius: SVTheme.Sizing.buttonCornerRadius))
        }
        .disabled(isDisabled || isLoading)
    }
}

struct SVSecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.medium))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(SVTheme.textSecondary)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(SVTheme.surface)
            .clipShape(.rect(cornerRadius: SVTheme.Sizing.chipCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SVTheme.Sizing.chipCornerRadius)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }
}

struct SVCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: SVTheme.Sizing.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SVTheme.Sizing.cardCornerRadius)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
    }
}
