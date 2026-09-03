import SwiftUI

struct CategoryChipsBar: View {
    let selected: FeedCategory
    let onSelect: (FeedCategory) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(FeedCategory.allCases) { cat in
                    Button { onSelect(cat) } label: {
                        VStack(spacing: 5) {
                            Text(cat.title)
                                .font(.system(size: 16, weight: cat == selected ? .bold : .semibold))
                                .foregroundStyle(cat == selected ? Theme.chipSelected : Theme.chipUnselected)
                                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                            Capsule().fill(.white).frame(width: 22, height: 2.5).opacity(cat == selected ? 1 : 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
        .animation(.snappy(duration: 0.2), value: selected)
    }
}
