import SwiftUI

struct ChipItem<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
    var accessibilityLabel: String?
}

/// Wrapping group of capsule chips. Multi-select by default; `allowsMultiple: false` makes it single-select.
/// Selection is shown by an outline, a tint and a check mark (never colour alone), and exposes the selected trait.
struct ChipGroup<ID: Hashable>: View {
    let items: [ChipItem<ID>]
    @Binding var selection: Set<ID>
    var allowsMultiple = true
    var onToggle: ((ID) -> Void)?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                Chip(label: item.label, isSelected: selection.contains(item.id)) { toggle(item.id) }
                    .accessibilityLabel(item.accessibilityLabel ?? item.label)
            }
        }
    }

    private func toggle(_ id: ID) {
        if selection.contains(id) {
            selection.remove(id)
        } else if allowsMultiple {
            selection.insert(id)
        } else {
            selection = [id]
        }
        onToggle?(id)
    }
}

private struct Chip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                Text(label).font(.subheadline)
            }
            .foregroundStyle(Color("ink"))
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(Capsule().fill(isSelected ? Color("accent").opacity(0.18) : Color("card")))
            .overlay(Capsule().strokeBorder(isSelected ? Color("accent") : Color("hairline"), lineWidth: 1.5))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Left-to-right flow that wraps onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in rows.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .init(frame.size))
        }
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> (
        frames: [CGRect], width: CGFloat, height: CGFloat
    ) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (frames, usedWidth, y + rowHeight)
    }
}
