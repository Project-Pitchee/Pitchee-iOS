//
//  PracticeHubView.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/4.
//

import SwiftUI

enum PracticeRoute: Hashable {
    case scoring
    case analysis
    case pitch
    case spectrum
    case spectrogram
    #if DEBUG
    case screenshotArticles
    #endif
}

/// Live tools and library topics share one native, searchable navigation list.
struct PracticeHubView: View {
    @State private var searchText = ""
    @ObservedObject private var library = VoiceTrainingLibraryLoader.shared
    private var store: VoiceTrainingLibraryStore { library.store }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let results = isSearching ? store.search(query: searchText) : []
        List {
            if isSearching {
                ForEach(results) { article in
                    NavigationLink {
                        VoiceArticleContentView(article: article)
                    } label: {
                        Text(article.title)
                            .font(.body)
                    }
                }
            } else {
                Section("practice.hub.live.title") {
                    NavigationLink(value: PracticeRoute.scoring) {
                        Label("recording.screen.title", systemImage: "checkmark.seal")
                    }
                    .accessibilityIdentifier("practice.openScoring")
                    NavigationLink(value: PracticeRoute.pitch) {
                        Label(LocalizedStringKey(MonitorKind.pitch.titleKey), systemImage: MonitorKind.pitch.symbol)
                    }
                    .accessibilityIdentifier("monitor.openPitch")
                    NavigationLink(value: PracticeRoute.spectrum) {
                        Label(LocalizedStringKey(MonitorKind.spectrum.titleKey), systemImage: MonitorKind.spectrum.symbol)
                    }
                    .accessibilityIdentifier("monitor.openSpectrum")
                    NavigationLink(value: PracticeRoute.spectrogram) {
                        Label("practice.spectrum.title", systemImage: "waveform.badge.magnifyingglass")
                    }
                    .accessibilityIdentifier("practice.openSpectrogram")
                }
                Section("voiceLibrary.title") {
                    if store.articles.isEmpty {
                        VoiceTrainingLibraryLoadStatusView(loader: library)
                    }
                    ForEach(store.categories, id: \.id) { category in
                        NavigationLink {
                            VoiceTrainingLibraryContentView(initialCategory: category.id)
                        } label: {
                            Text(category.title)
                        }
                        .accessibilityIdentifier("practice.category.\(category.id)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("practice.hub.tab")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("practice.hub.search"))
        .task { await library.load() }
        .overlay {
            if isSearching && store.articles.isEmpty {
                VoiceTrainingLibraryLoadStatusView(loader: library)
            } else if isSearching && results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}
