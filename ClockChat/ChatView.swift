import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var draft = ""
    @State private var settings = false
    @State private var history = false
    @FocusState private var typing: Bool
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.teal.opacity(0.09), Color(uiColor: .systemBackground)],
                               startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            if store.current?.messages.isEmpty != false { welcome }
                            ForEach(store.current?.messages ?? []) { message in
                                MessageView(message: message)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: store.current?.messages.last?.content) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    .onChange(of: store.selectedID) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .navigationTitle("ClockChat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { history = true } label: { Image(systemName: "sidebar.left") }
                        .accessibilityLabel("Gesprekken").disabled(store.busy)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { store.newChat(); draft = "" } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Nieuw gesprek").disabled(store.busy)
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Instellingen").disabled(store.busy)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .sheet(isPresented: $settings) { SettingsView().environmentObject(store) }
            .sheet(isPresented: $history) { historyView }
            .alert("Even controleren", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    Image(systemName: "clock")
                    Text(context.date, style: .time).monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 44)).foregroundStyle(.teal).padding(.top, 28)
            Text("Ruimte voor\nje volgende idee.").font(.largeTitle.bold())
            Text("Jouw gesprek. Jouw model.\nKies een verbinding en begin.")
                .foregroundStyle(.secondary)
            Button { settings = true } label: { Label("Verbinding instellen", systemImage: "network") }
                .buttonStyle(.borderedProminent).controlSize(.large)
            VStack(alignment: .leading, spacing: 10) {
                suggestion("Leg iets ingewikkelds eenvoudig uit")
                suggestion("Help me mijn eerste app te bouwen")
                suggestion("Denk mee over een nieuw idee")
            }.padding(.top)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 24)
    }
    private func suggestion(_ text: String) -> some View {
        Button { draft = text; typing = true } label: {
            HStack { Text(text).font(.subheadline); Spacer(); Image(systemName: "arrow.up.left") }
                .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
    private var composer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(store.busy ? .orange : .teal).frame(width: 6, height: 6)
                Text(store.busy ? "Antwoord wordt ontvangen…" : store.connection.provider.rawValue)
                if !store.connection.model.isEmpty { Text("· " + store.connection.model).lineLimit(1) }
                Spacer()
            }.font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Stel je vraag…", text: $draft, axis: .vertical)
                    .lineLimit(1...6).focused($typing).padding(.vertical, 10)
                if store.busy {
                    Button { store.stop() } label: { Image(systemName: "stop.fill").frame(width: 40, height: 40) }
                        .buttonStyle(.bordered).buttonBorderShape(.circle).accessibilityLabel("Antwoord stoppen")
                } else {
                    Button {
                        if store.send(draft) { draft = ""; typing = false }
                    } label: { Image(systemName: "arrow.up").font(.headline).frame(width: 40, height: 40) }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Versturen")
                }
            }.padding(8).padding(.leading, 8)
                .background(.background, in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(.primary.opacity(0.08)))
        }.padding(.horizontal, 16).padding(.vertical, 12).background(.ultraThinMaterial)
    }
    private var historyView: some View {
        NavigationStack {
            List {
                if store.state.conversations.isEmpty { Text("Je gesprekken verschijnen hier.").foregroundStyle(.secondary) }
                ForEach(store.state.conversations) { chat in
                    Button { store.selectedID = chat.id; draft = ""; history = false } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(chat.title).foregroundStyle(.primary).lineLimit(1)
                            Text(chat.updated, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Verwijderen", role: .destructive) { store.delete(chat.id) }
                    }
                }
            }.navigationTitle("Gesprekken")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Gereed") { history = false } } }
        }
    }
}

private struct MessageView: View {
    let message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message.role == "user" ? "Jij" : "Assistent", systemImage: message.role == "user" ? "person.crop.circle" : "sparkles")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if message.content.isEmpty {
                Text(message.interrupted ? "Wachten op antwoord / onderbroken" : "Geen tekst")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(.init(message.content)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if message.interrupted && !message.content.isEmpty {
                Text("Antwoord bezig of onderbroken").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == "user" ? Color.teal.opacity(0.11) : Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22))
    }
}
