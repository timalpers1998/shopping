import SwiftUI
import NukeUI

/// Chat-style onboarding: large assistant text, user replies as bubbles, one input control at a time.
struct ConversationalOnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: OnboardingChatModel?
    var onDone: () -> Void

    var body: some View {
        ZStack {
            OnboardingBackdrop()
            if let model {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            Color.clear.frame(height: 56)
                            ForEach(model.items) { item in
                                itemView(item, model: model)
                                    .id(item.id)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            Color.clear.frame(height: 24).id("bottom")
                        }
                        .padding(.horizontal, 24)
                        .animation(.easeOut(duration: 0.35), value: model.items)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: model.items) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.25), Color(red: 0.16, green: 0.19, blue: 0.25).opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 110).ignoresSafeArea().allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    if !model.finished {
                        Button("Skip") { model.finish(); onDone() }
                            .font(.subheadline).foregroundStyle(.white.opacity(0.55)).padding(20)
                            .accessibilityIdentifier("quiz-skip")
                    }
                }
                .onChange(of: model.finished) { _, done in if done { onDone() } }
            }
        }
        .foregroundStyle(.white)
        .task {
            if model == nil {
                let m = OnboardingChatModel(environment: env)
                model = m
                await m.start()
            }
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func itemView(_ item: OnboardingChatModel.Item, model: OnboardingChatModel) -> some View {
        switch item {
        case .assistant(_, let text): AssistantText(text: text)
        case .user(_, let text): UserBubble(text: text)
        case .typing: TypingDots()
        case .thinking(_, let text): ThinkingChip(text: text)
        case .profile(_, let summary): TasteProfileCard(summary: summary)
        case .input(_, let input): InputView(input: input, model: model)
        }
    }
}

// MARK: - Message pieces

private struct AssistantText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 27, weight: .regular))
            .lineSpacing(5)
            .foregroundStyle(.white.opacity(0.94))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct UserBubble: View {
    let text: String
    var body: some View {
        HStack { Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 21))
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(Color(white: 0.13).opacity(0.95), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityIdentifier("chat-user-bubble")
        }
    }
}

private struct TypingDots: View {
    @State private var phase = 0
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(.white.opacity(phase == i ? 0.9 : 0.35)).frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
        .task { while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(300)); phase = (phase + 1) % 3 } }
    }
}

private struct ThinkingChip: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.white.opacity(0.14), in: Capsule())
            Circle().fill(.white.opacity(0.14)).frame(width: 8, height: 8).padding(.leading, 4)
        }
        .accessibilityIdentifier("chat-thinking")
    }
}

private struct TasteProfileCard: View {
    let summary: OnboardingChatModel.TasteSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color(red: 0.98, green: 0.82, blue: 0.2)).frame(height: 18)
            VStack(alignment: .leading, spacing: 10) {
                Text("\(summary.name) taste").font(.title2.bold())
                Text(line).font(.body).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                if summary.importedItems > 0 {
                    Text("From your inbox: \(summary.importedItems) past orders from \(summary.importedBrands.prefix(4).joined(separator: ", "))\(summary.importedBrands.count > 4 ? " and more" : "").")
                        .font(.body).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("taste-profile-card")
    }
    private var line: String {
        let who = ["womens": "women's", "mens": "men's"][summary.audience] ?? "everything"
        var s = "You shop \(who), usually \(summary.band). You lean \(summary.styles.joined(separator: ", "))."
        if !summary.brands.isEmpty { s += " Brands you already like: \(summary.brands.joined(separator: ", "))." }
        return s
    }
}

// MARK: - Inputs (one per question)

private struct InputView: View {
    let input: OnboardingChatModel.Input
    @Bindable var model: OnboardingChatModel

    var body: some View {
        switch input {
        case .name:
            HStack(spacing: 10) {
                TextField("Your first name", text: $model.name)
                    .textContentType(.givenName).submitLabel(.done)
                    .onSubmit { model.submitName() }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(.white.opacity(0.12), in: Capsule())
                    .accessibilityIdentifier("onboarding-name")
                Button { model.submitName() } label: { Image(systemName: "arrow.up").font(.headline).padding(14).background(.white, in: Circle()).foregroundStyle(.black) }
                    .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("onboarding-name-send")
            }
        case .audience:
            ChoiceRow(options: [("womens", "Women's"), ("mens", "Men's"), ("both", "Both")], idPrefix: "audience") { model.submitAudience($0, label: $1) }
        case .budget:
            VStack(spacing: 8) {
                ForEach([("budget", "Under $50", "H&M, Uniqlo, Old Navy"), ("mid", "$50–150", "Aritzia, Madewell, Lululemon"), ("premium", "$150–500", "Reformation, COS, Arc'teryx"), ("luxury", "$500+", "The Row, Loewe, Prada")], id: \.0) { v, label, hint in
                    Button { model.submitBudget(v, label: label) } label: {
                        HStack { Text(label).font(.headline); Spacer(); Text(hint).font(.caption).foregroundStyle(.white.opacity(0.55)) }
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("band-\(v)")
                }
            }
        case .styles:
            VStack(spacing: 12) {
                if let catalog = model.catalog {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(catalog.styles) { style in
                            let on = model.answers.styles.contains(style.slug)
                            Button { model.toggleStyle(style.slug) } label: {
                                ZStack(alignment: .bottomLeading) {
                                    LazyImage(url: style.imageUrl) { state in
                                        if let image = state.image { image.resizable().scaledToFill() } else { Rectangle().fill(.white.opacity(0.1)) }
                                    }
                                    .pipeline(.feed)
                                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                                    Text(style.label).font(.caption.bold()).padding(8)
                                    if on { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, .blue).padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing) }
                                }
                                .aspectRatio(3/4, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: on ? 2 : 0))
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("style-\(style.slug)")
                        }
                    }
                } else { ProgressView().tint(.white) }
                if model.answers.styles.count >= 3 {
                    PrimaryButton(title: "That's me") { model.submitStyles() }.accessibilityIdentifier("quiz-continue")
                } else {
                    Text("\(model.answers.styles.count) of 3 picked").font(.footnote).foregroundStyle(.white.opacity(0.55))
                }
            }
        case .brands:
            VStack(alignment: .leading, spacing: 12) {
                if let catalog = model.catalog {
                    FlowLayout(spacing: 8) {
                        ForEach(catalog.brands) { b in
                            let on = model.answers.brandIds.contains(b.id)
                            Button(b.name) { model.toggleBrand(b.id) }
                                .font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 9)
                                .background(on ? .white : .white.opacity(0.12), in: Capsule()).foregroundStyle(on ? .black : .white)
                                .accessibilityIdentifier("brand-\(b.name)")
                        }
                    }
                }
                PrimaryButton(title: model.answers.brandIds.isEmpty ? "None jump out" : "These") { model.submitBrands() }.accessibilityIdentifier("brands-continue")
            }
        case .inbox:
            VStack(spacing: 10) {
                ForEach(Array(model.purchases.providers.enumerated()), id: \.offset) { _, provider in
                    Button { model.connect(provider) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "envelope.fill").font(.title3).frame(width: 34, height: 34).background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                            Text(provider.kind == .gmail ? "Gmail" : provider.kind == .outlook ? "Outlook" : "Sample inbox").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("import-connect-\(provider.kind.rawValue)")
                }
                Button("Not now") { model.skipInbox() }.font(.subheadline).foregroundStyle(.white.opacity(0.6)).padding(.top, 4).accessibilityIdentifier("import-skip")
            }
        case .review:
            PurchaseReviewCard(model: model)
        case .finish:
            PrimaryButton(title: "Show me my feed") { model.finish() }.accessibilityIdentifier("onboarding-finish")
        }
    }
}

private struct ChoiceRow: View {
    let options: [(String, String)]
    let idPrefix: String
    let pick: (String, String) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { v, label in
                Button(label) { pick(v, label) }
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 48)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("\(idPrefix)-\(v)")
            }
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).bold().frame(maxWidth: .infinity).frame(height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 26)).foregroundStyle(.black)
        }
    }
}

private struct PurchaseReviewCard: View {
    @Bindable var model: OnboardingChatModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(model.purchases.groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(group.name).font(.headline)
                        Text("\(group.includedCount) of \(group.items.count)").font(.caption).foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Toggle("", isOn: Binding(get: { group.includedCount > 0 }, set: { model.purchases.toggleBrand(group.name, on: $0) })).labelsHidden().tint(.green)
                            .accessibilityIdentifier("import-brand-\(group.name)")
                    }
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(group.items) { item in
                            PurchaseTile(item: item).onTapGesture { model.purchases.toggleItem(item.id) }
                        }
                    }
                }
            }
            if let band = model.purchases.priceBandLabel {
                Toggle(isOn: $model.purchases.setPriceBand) { Text("Set my price range to \(band)").font(.subheadline) }.tint(.green)
            }
            Toggle(isOn: $model.purchases.followBrands) { Text("Follow these brands").font(.subheadline) }.tint(.green)
            PrimaryButton(title: "Add \(model.purchases.includedItemCount) items to my taste") { model.applyPurchases() }
                .disabled(model.purchases.includedItemCount == 0)
                .accessibilityIdentifier("import-apply")
            Button("Skip these") { model.skipPurchases() }.font(.subheadline).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Soft slate-to-teal gradient with a couple of blurred blobs, like the reference.
struct OnboardingBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.25), Color(red: 0.2, green: 0.3, blue: 0.38), Color(red: 0.24, green: 0.5, blue: 0.58)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(red: 0.55, green: 0.8, blue: 0.85).opacity(0.35)).frame(width: 420).blur(radius: 90).offset(x: 120, y: 380)
            Circle().fill(Color.white.opacity(0.12)).frame(width: 320).blur(radius: 80).offset(x: -160, y: -260)
        }
        .ignoresSafeArea()
    }
}
