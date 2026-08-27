import SwiftUI

struct ReaderView: View {
    @State private var model: ReaderViewModel
    @State private var showTOC = false
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss

    init(book: AppBookDetail, bookURL: URL, client: GrimmoryClient) {
        _model = State(wrappedValue: ReaderViewModel(book: book, bookURL: bookURL, client: client))
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            ReaderWebView(
                bookURL: model.bookURL,
                startCFI: model.startCFI,
                settings: model.settings,
                onMessage: model.handle,
                commands: model.commands
            )
            .ignoresSafeArea(edges: .bottom)
            .opacity(model.phase == .reading ? 1 : 0)

            switch model.phase {
            case .loading:
                ProgressView("Opening…")
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't open this book", systemImage: "book.closed")
                } description: {
                    Text(message)
                } actions: {
                    Button("Close") { dismiss() }
                }
            case .reading:
                EmptyView()
            }
        }
        .statusBarHidden(!model.showChrome)
        .toolbar(model.showChrome ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle(model.book.title ?? "Reading")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    Task {
                        await model.flushProgress()
                        dismiss()
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showTOC = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .disabled(model.toc.isEmpty)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.showChrome, model.phase == .reading {
                footer
            }
        }
        .sheet(isPresented: $showTOC) {
            TOCSheet(entries: model.toc) { model.goTo($0) }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(settings: $model.settings)
        }
        .animation(.easeInOut(duration: 0.2), value: model.showChrome)
        .task {
            // Reading is the one screen where the screen dimming mid-page is
            // actively annoying.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if let syncError = model.syncError {
                Label(syncError, systemImage: "arrow.triangle.2.circlepath.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Slider(
                value: Binding(
                    get: { model.progressFraction },
                    set: { model.scrub(to: $0) }
                ),
                in: 0 ... 1
            )

            Text(model.progressLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var backgroundColor: Color {
        switch model.settings.theme {
        case .light: Color.white
        case .sepia: Color(red: 0.957, green: 0.925, blue: 0.847)
        case .dark: Color(red: 0.063, green: 0.063, blue: 0.078)
        }
    }
}

struct TOCSheet: View {
    let entries: [TOCEntry]
    let onSelect: (TOCEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    onSelect(entry)
                    dismiss()
                } label: {
                    Text(entry.label)
                        .padding(.leading, CGFloat(entry.depth) * 16)
                        .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ReaderSettingsSheet: View {
    @Binding var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(ReaderSettings.Theme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Layout") {
                    Picker("Flow", selection: $settings.flow) {
                        ForEach(ReaderSettings.Flow.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Stepper("Text size: \(settings.fontSize)%", value: $settings.fontSize, in: 70 ... 220, step: 10)
                    Stepper("Margins: \(settings.margin)%", value: $settings.margin, in: 0 ... 16, step: 2)

                    VStack(alignment: .leading) {
                        Text("Line spacing: \(settings.lineHeight, specifier: "%.1f")")
                        Slider(value: $settings.lineHeight, in: 1.0 ... 2.4, step: 0.1)
                    }
                }

                Section("Text") {
                    Toggle("Justify", isOn: $settings.justify)
                    Toggle("Hyphenate", isOn: $settings.hyphenate)
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
