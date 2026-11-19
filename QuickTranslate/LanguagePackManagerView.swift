import SwiftUI
import Translation

struct LanguagePackManagerView: View {
    @Binding var selectedSourceLanguage: String
    let targetLanguage: String

    @Environment(\.dismiss) private var dismiss
    @State private var supportedLanguages: [Locale.Language] = []
    @State private var searchText = ""
    @State private var showingRemovalHelp = false
    @State private var isLoading = true

    private var filteredLanguages: [Locale.Language] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return supportedLanguages }
        return supportedLanguages.filter { language in
            let identifier = language.minimalIdentifier
            let name = Locale(identifier: "en").localizedString(forIdentifier: identifier) ?? identifier
            return name.localizedCaseInsensitiveContains(query)
                || identifier.localizedCaseInsensitiveContains(query)
                || (language.languageCode?.identifier.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a source language to download its offline translation pair with English. Downloads are provided and managed by iOS.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Finding supported languages…")
                        Spacer()
                    }
                } else {
                    Section("Supported languages") {
                        ForEach(filteredLanguages, id: \.minimalIdentifier) { language in
                            LanguagePackRow(
                                language: language,
                                targetLanguage: targetLanguage,
                                isSelected: selectedSourceLanguage == language.minimalIdentifier,
                                onSelect: { selectedSourceLanguage = language.minimalIdentifier }
                            )
                        }
                    }
                }

                Section {
                    Button {
                        showingRemovalHelp = true
                    } label: {
                        Label("Manage or delete downloaded packs", systemImage: "trash")
                    }
                    Text("iOS does not let third-party apps delete Apple Translation downloads directly. You can remove them in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $searchText, prompt: "Search languages")
            .navigationTitle("Language packs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete downloaded languages", isPresented: $showingRemovalHelp) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Open Settings → Apps → Translate → Downloaded Languages. Select a language and remove its download there. iOS manages these language files for all apps.")
            }
            .task {
                supportedLanguages = await LanguageAvailability().supportedLanguages
                supportedLanguages.sort {
                    displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
                }
                isLoading = false
            }
        }
    }

    private func displayName(for language: Locale.Language) -> String {
        let identifier = language.minimalIdentifier
        return Locale(identifier: "en").localizedString(forIdentifier: identifier)
            ?? language.languageCode?.identifier
            ?? identifier
    }
}

private struct LanguagePackRow: View {
    let language: Locale.Language
    let targetLanguage: String
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var isPreparing = false
    @State private var isInstalled = false
    @State private var isSupported = false
    @State private var message = "Checking…"

    private var identifier: String { language.minimalIdentifier }
    private var name: String {
        Locale(identifier: "en").localizedString(forIdentifier: identifier)
            ?? language.languageCode?.identifier
            ?? identifier
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .foregroundStyle(.primary)
                    Text(identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(isInstalled ? .green : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }

            if isPreparing {
                ProgressView()
            } else if isInstalled {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
            } else if isSupported {
                Button {
                    isPreparing = true
                    message = "Preparing download…"
                    configuration = TranslationSession.Configuration(
                        source: language,
                        target: Locale.Language(identifier: targetLanguage)
                    )
                    configuration?.invalidate()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Download \(name) language pack")
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .task { await refreshStatus() }
        .translationTask(configuration) { session in
            guard isPreparing else { return }
            do {
                try await session.prepareTranslation()
                await refreshStatus()
                if isInstalled {
                    message = "Downloaded and ready"
                } else {
                    message = "Download not completed"
                }
            } catch {
                message = error.localizedDescription
            }
            isPreparing = false
        }
    }

    @MainActor
    private func refreshStatus() async {
        let status = await LanguageAvailability().status(
            from: language,
            to: Locale.Language(identifier: targetLanguage)
        )
        switch status {
        case .installed:
            isInstalled = true
            isSupported = true
            message = "Downloaded and ready"
        case .supported:
            isInstalled = false
            isSupported = true
            message = "Available to download"
        case .unsupported:
            isInstalled = false
            isSupported = false
            message = "Not available with English"
        @unknown default:
            isInstalled = false
            isSupported = false
            message = "Availability unknown"
        }
    }
}
