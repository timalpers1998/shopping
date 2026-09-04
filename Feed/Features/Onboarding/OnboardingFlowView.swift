import SwiftUI
import NukeUI

/// Three quick screens that seed the taste vector. Skippable; can be reopened from Settings.
struct OnboardingFlowView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var answers = QuizAnswers()
    @State private var catalog: QuizCatalog?
    @State private var busy = false
    @State private var brandQuery = ""
    /// Called with `true` when answers were submitted, `false` when skipped.
    var onDone: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ProgressView(value: Double(page + 1), total: 3).tint(.white).frame(width: 120)
                Spacer()
                Button("Skip") { finish(submit: false) }.foregroundStyle(.secondary).accessibilityIdentifier("quiz-skip")
            }
            .padding(20)

            TabView(selection: $page) {
                audiencePage.tag(0)
                stylesPage.tag(1)
                brandsPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Button { advance() } label: {
                Group { if busy { ProgressView().tint(.black) } else { Text(page == 2 ? "Show me my feed" : "Continue").bold() } }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
            }
            .disabled(!canAdvance || busy)
            .padding(20)
            .accessibilityIdentifier("quiz-continue")
        }
        .background(Theme.background)
        .foregroundStyle(.white)
        .task { catalog = try? await env.tasteRepository.catalog() }
        .interactiveDismissDisabled()
    }

    private var canAdvance: Bool {
        switch page {
        case 1: answers.styles.count >= 3
        default: true
        }
    }

    private func advance() {
        if page < 2 { withAnimation { page += 1 } } else { finish(submit: true) }
    }

    private func finish(submit: Bool) {
        busy = true
        Task {
            if submit { try? await env.tasteRepository.submit(answers) }
            await env.refreshMe()
            UserDefaults.standard.set(true, forKey: "onboarding.shown")
            busy = false
            onDone(submit)
        }
    }

    // MARK: pages

    private var audiencePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header("Who are you shopping for?", "We'll only show what fits.")
                choiceRow(options: [("womens", "Women's"), ("mens", "Men's"), ("both", "Both")], selected: answers.audience) { answers.audience = $0 }
                header("What do you usually spend on a piece?", "A soft preference, not a hard filter.")
                VStack(spacing: 10) {
                    ForEach([("budget", "Under $50", "H&M, Old Navy, Uniqlo"), ("mid", "$50–150", "Aritzia, Madewell, Lululemon"), ("premium", "$150–500", "Reformation, COS, Arc'teryx"), ("luxury", "$500+", "The Row, Loewe, Prada")], id: \.0) { band, label, hint in
                        Button { answers.priceBand = band } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) { Text(label).bold(); Text(hint).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Image(systemName: answers.priceBand == band ? "checkmark.circle.fill" : "circle").foregroundStyle(answers.priceBand == band ? .white : .secondary)
                            }
                            .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("band-\(band)")
                    }
                }
            }
            .padding(20)
        }
    }

    private var stylesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("Pick your styles", "Choose 3 or more. \(answers.styles.count) picked.")
                if let catalog {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(catalog.styles) { style in
                            let on = answers.styles.contains(style.slug)
                            Button {
                                if on { answers.styles.remove(style.slug) } else { answers.styles.insert(style.slug) }
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    LazyImage(url: style.imageUrl) { state in
                                        if let image = state.image { image.resizable().scaledToFill() } else { Rectangle().fill(Theme.surface) }
                                    }
                                    .pipeline(.feed)
                                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                                    Text(style.label).font(.caption.bold()).padding(8)
                                    if on { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, .blue).padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing) }
                                }
                                .aspectRatio(3/4, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: on ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("style-\(style.slug)")
                        }
                    }
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
    }

    private var brandsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("Brands you already love", "Optional. Helps us on day one.")
                TextField("Search brands", text: $brandQuery).padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                if let catalog {
                    let shown = catalog.brands.filter { brandQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(brandQuery) }
                    FlowLayout(spacing: 8) {
                        ForEach(shown) { b in
                            let on = answers.brandIds.contains(b.id)
                            Button(b.name) { if on { answers.brandIds.remove(b.id) } else { answers.brandIds.insert(b.id) } }
                                .font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 9)
                                .background(on ? .white : Theme.surface, in: Capsule()).foregroundStyle(on ? .black : .white)
                                .accessibilityIdentifier("brand-\(b.name)")
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func choiceRow(options: [(String, String)], selected: String, pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { value, label in
                Button(label) { pick(value) }
                    .font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 44)
                    .background(selected == value ? .white : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(selected == value ? .black : .white)
                    .accessibilityIdentifier("audience-\(value)")
            }
        }
    }
}
