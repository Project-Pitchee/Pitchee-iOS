//
//  RecordingExportView.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/26.
//

import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordingExportButton: View {
    let result: PitcheeAnalysisResult
    let volumeStatistics: RecordingVolumeStatistics?
    let preference: VoicePreference

    @State private var isPresented = false

    var body: some View {
        Button("export.entry.openExport", systemImage: "square.and.arrow.up") {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            RecordingExportView(
                result: result,
                volumeStatistics: volumeStatistics,
                preference: preference
            )
            .presentationDragIndicator(.visible)
        }
    }
}

struct RecordingExportView: View {
    let result: PitcheeAnalysisResult
    let volumeStatistics: RecordingVolumeStatistics?
    let preference: VoicePreference

    @State private var selectedItems = Set(ExportSelectionID.allCases)
    @State private var editMode: EditMode = .active
    @State private var previewPageIndex = 0
    @State private var exportFormat: ExportFormat = .pdf
    @State private var showsFileExporter = false
    @State private var exportDocument = ExportPDFDocument(data: Data())
    @State private var isSaving = false
    @State private var showsPhotoSaveSuccess = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List(selection: $selectedItems) {
                Section {
                    VStack(spacing: 20) {
                        previewSection

                        Picker("export.format.label", selection: $exportFormat) {
                            ForEach(ExportFormat.allCases) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
                }
                
                Section("export.selection.charts") {
                    ForEach(ExportChartOption.allCases) { option in
                        ExportSelectionListRow(
                            title: option.title,
                            detail: option.detail,
                            symbol: option.symbol
                        )
                        .tag(ExportSelectionID.chart(option))
                    }
                }
                
                ForEach(ExportMetricGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(ExportMetricOption.allCases.filter { $0.group == group }) { option in
                            ExportSelectionListRow(
                                title: option.title,
                                detail: option.detail,
                                symbol: option.symbol
                            )
                            .tag(ExportSelectionID.metric(option))
                        }
                    }
                }
            }
            .disabled(isSaving)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .environment(\.editMode, $editMode)
            .navigationTitle("export.sheet.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("export.sheet.saveReport", systemImage: "square.and.arrow.down") {
                        Task { await saveReport() }
                    }
                    .disabled(!hasExportContent || isSaving)
                }
            }
            .fileExporter(
                isPresented: $showsFileExporter,
                document: exportDocument,
                contentType: .pdf,
                defaultFilename: String(localized: "export.sheet.defaultFilename")
            ) { result in
                if case .failure = result {
                    exportError = String(localized: "export.error.reportSaveFailed.message")
                }
            }
            .alert("export.error.reportSaveFailed.title", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("common.action.ok", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? String(localized: "common.error.tryAgainLater"))
            }
            .alert("export.photos.saved.title", isPresented: $showsPhotoSaveSuccess) {
                Button("common.action.ok", role: .cancel) { }
            } message: {
                Text("export.photos.saved.message")
            }
            .interactiveDismissDisabled(isSaving)
            .onChange(of: selectedItems) { _, _ in
                normalizePreviewIndex()
            }
        }
    }

    private var hasExportContent: Bool {
        !selectedItems.isEmpty
    }

    private var pageModels: [ExportReportPageModel] {
        ExportReportPaginator.makePages(
            charts: orderedCharts,
            metrics: orderedMetrics
        )
    }

    private var orderedCharts: [ExportChartOption] {
        ExportChartOption.allCases.filter { selectedItems.contains(.chart($0)) }
    }

    private var orderedMetrics: [ExportMetricOption] {
        ExportMetricOption.allCases.filter { selectedItems.contains(.metric($0)) }
    }

    private var previewSection: some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("export.preview.heading")
                    .font(.title3.weight(.bold))
                Spacer(minLength: 12)
            }

            VStack(spacing: 8) {
                TabView(selection: $previewPageIndex) {
                    ForEach(Array(pageModels.enumerated()), id: \.element.id) { index, page in
                        ExportReportPagePreview(
                            page: page,
                            result: result,
                            volumeStatistics: volumeStatistics,
                            preference: preference
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, pageModels.count > 1 ? 32 : 0)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: pageModels.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(maxWidth: .infinity)
                .aspectRatio(ExportReportPage.a4AspectRatio, contentMode: .fit)
                .padding(.horizontal, 8)
                .animation(.easeInOut(duration: 0.2), value: previewPageIndex)
                .accessibilityLabel(
                    "export.preview.pageIndicator \(previewPageIndex + 1) \(pageModels.count)"
                )
            }
        }
    }

    private func normalizePreviewIndex() {
        previewPageIndex = min(previewPageIndex, max(0, pageModels.count - 1))
    }

    @MainActor
    private func saveReport() async {
        guard !isSaving else { return }
        guard hasExportContent else {
            exportError = String(localized: "export.error.nothingToExport")
            return
        }
        isSaving = true
        defer { isSaving = false }

        switch exportFormat {
        case .image:
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                exportError = String(localized: "export.error.photoLibraryAccessDenied.message")
                return
            }
            guard let images = makeImages() else {
                exportError = String(localized: "export.error.imageGenerationFailed")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges { @Sendable in
                    for data in images {
                        let request = PHAssetCreationRequest.forAsset()
                        request.addResource(with: .photo, data: data, options: nil)
                    }
                }
                showsPhotoSaveSuccess = true
            } catch {
                exportError = String(localized: "export.error.imageSaveFailed.message")
            }
        case .pdf:
            guard let data = makePDF() else {
                exportError = String(localized: "export.error.reportSaveFailed.message")
                return
            }
            exportDocument = ExportPDFDocument(data: data)
            showsFileExporter = true
        }
    }

    @MainActor
    private func makeImages() -> [Data]? {
        var images: [Data] = []

        for page in pageModels {
            guard let image = makePageImage(page, scale: 2),
                  let data = image.pngData() else { return nil }
            images.append(data)
        }
        return images
    }

    @MainActor
    private func makePageImage(_ page: ExportReportPageModel, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: ExportReportPage(
            page: page,
            result: result,
            volumeStatistics: volumeStatistics,
            preference: preference
        ))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    @MainActor
    private func makePDF() -> Data? {
        let pageSize = ExportReportPage.pageSize
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        var failed = false

        let data = renderer.pdfData { context in
            for page in pageModels {
                context.beginPage()
                guard let image = makePageImage(page, scale: 1) else {
                    failed = true
                    continue
                }
                image.draw(in: bounds)
            }
        }
        return failed ? nil : data
    }
}

private enum ExportFormat: CaseIterable, Identifiable {
    case image
    case pdf

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .image: "export.format.image"
        case .pdf: "export.format.pdf"
        }
    }

}

private enum ExportSelectionID: Hashable {
    case chart(ExportChartOption)
    case metric(ExportMetricOption)

    static var allCases: [Self] {
        ExportChartOption.allCases.map(Self.chart)
            + ExportMetricOption.allCases.map(Self.metric)
    }
}

private struct ExportSelectionListRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.pitcheeAccent)
        }
        .foregroundStyle(.primary)
        // Keep the system editing checkmark while removing UITableView's
        // selected-row gray fill. The card should keep the same surface when
        // an item is selected or deselected.
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

private enum ExportChartOption: String, CaseIterable, Hashable, Identifiable {
    case frequency
    case voiceLoudness
    case backgroundLoudness
    case result

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frequency: String(localized: "export.selection.frequencyCurve.title")
        case .voiceLoudness: String(localized: "export.selection.loudnessCurve.title")
        case .backgroundLoudness: String(localized: "export.selection.backgroundLoudnessCurve.title")
        case .result: String(localized: "export.selection.resultChart.title")
        }
    }

    var detail: String {
        switch self {
        case .frequency: String(localized: "export.selection.frequencyCurve.subtitle")
        case .voiceLoudness: String(localized: "export.selection.loudnessCurve.subtitle")
        case .backgroundLoudness: String(localized: "export.selection.backgroundLoudnessCurve.subtitle")
        case .result: String(localized: "export.selection.resultChart.subtitle")
        }
    }

    var symbol: String {
        switch self {
        case .frequency: "waveform.path"
        case .voiceLoudness: "speaker.wave.2"
        case .backgroundLoudness: "wind"
        case .result: "chart.bar.xaxis"
        }
    }
}

private enum ExportMetricGroup: String, CaseIterable, Identifiable {
    case recording
    case pitch
    case loudness
    case result

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: String(localized: "export.metricGroup.recording")
        case .pitch: String(localized: "export.metricGroup.pitch")
        case .loudness: String(localized: "export.metricGroup.loudness")
        case .result: String(localized: "export.metricGroup.result")
        }
    }
}

private enum ExportMetricOption: String, CaseIterable, Hashable, Identifiable {
    case inputDuration
    case analyzedDuration
    case speechDuration
    case sampleRate
    case channels
    case meanPitch
    case medianPitch
    case pitchStandardDeviation
    case pitchRange
    case voicedWindows
    case environmentLoudness
    case averageLoudness
    case medianLoudness
    case loudnessRange
    case finalScore
    case standardScore
    case naturalnessScore
    case baseScore

    var id: String { rawValue }

    var group: ExportMetricGroup {
        switch self {
        case .inputDuration, .analyzedDuration, .speechDuration, .sampleRate, .channels:
            .recording
        case .meanPitch, .medianPitch, .pitchStandardDeviation, .pitchRange, .voicedWindows:
            .pitch
        case .environmentLoudness, .averageLoudness, .medianLoudness, .loudnessRange:
            .loudness
        case .finalScore, .standardScore, .naturalnessScore, .baseScore:
            .result
        }
    }

    var title: String {
        switch self {
        case .inputDuration: String(localized: "export.metric.inputDuration.title")
        case .analyzedDuration: String(localized: "export.metric.analyzedDuration.title")
        case .speechDuration: String(localized: "common.metric.speechDuration.title")
        case .sampleRate: String(localized: "export.metric.sampleRate.title")
        case .channels: String(localized: "export.metric.channels.title")
        case .meanPitch: String(localized: "common.metric.meanPitch.title")
        case .medianPitch: String(localized: "common.metric.medianPitch.title")
        case .pitchStandardDeviation: String(localized: "export.metric.pitchStandardDeviation.title")
        case .pitchRange: String(localized: "common.metric.corePitchRange.title")
        case .voicedWindows: String(localized: "export.metric.voicedWindows.title")
        case .environmentLoudness: String(localized: "common.metric.environmentNoiseFloor.title")
        case .averageLoudness: String(localized: "export.metric.averageLoudness.title")
        case .medianLoudness: String(localized: "export.metric.medianLoudness.title")
        case .loudnessRange: String(localized: "export.metric.loudnessRange.title")
        case .finalScore: String(localized: "common.metric.compositeScore.title")
        case .standardScore: String(localized: "common.metric.standardScore.title")
        case .naturalnessScore: String(localized: "common.metric.naturalness.title")
        case .baseScore: String(localized: "export.metric.baseScore.title")
        }
    }

    var detail: String {
        switch self {
        case .inputDuration, .analyzedDuration, .speechDuration:
            String(localized: "export.metric.detail.timing")
        case .sampleRate, .channels:
            String(localized: "export.metric.detail.audioFormat")
        case .meanPitch, .medianPitch, .pitchStandardDeviation, .pitchRange, .voicedWindows:
            String(localized: "export.metric.detail.pitch")
        case .environmentLoudness, .averageLoudness, .medianLoudness, .loudnessRange:
            String(localized: "export.metric.detail.loudness")
        case .finalScore, .standardScore, .naturalnessScore, .baseScore:
            String(localized: "export.metric.detail.score")
        }
    }

    var symbol: String {
        switch self {
        case .inputDuration, .analyzedDuration, .speechDuration: "timer"
        case .sampleRate, .channels: "waveform"
        case .meanPitch, .medianPitch, .pitchStandardDeviation, .pitchRange, .voicedWindows: "waveform.path"
        case .environmentLoudness: "wind"
        case .averageLoudness, .medianLoudness, .loudnessRange: "speaker.wave.2"
        case .finalScore: "checkmark.seal"
        case .standardScore: "slider.horizontal.3"
        case .naturalnessScore: "leaf"
        case .baseScore: "function"
        }
    }

    func value(
        in result: PitcheeAnalysisResult,
        volumeStatistics: RecordingVolumeStatistics?,
        pitchStatistics: RecordingPitchStatistics,
        preference: VoicePreference
    ) -> ExportMetricValue {
        switch self {
        case .inputDuration:
            return ExportMetricValue(number(result.audio.inputSeconds), String(localized: "common.unit.seconds"))
        case .analyzedDuration:
            return ExportMetricValue(number(result.audio.analyzedSeconds), String(localized: "common.unit.seconds"))
        case .speechDuration:
            return ExportMetricValue(number(result.vad.speechSeconds), String(localized: "common.unit.seconds"))
        case .sampleRate:
            return ExportMetricValue(number(Double(result.audio.sourceSampleRate), fractionDigits: 0), String(localized: "common.unit.hertz"))
        case .channels:
            return ExportMetricValue(String(localized: "export.metric.channels.value \(result.audio.sourceChannels)"), "")
        case .meanPitch:
            return ExportMetricValue(number(pitchStatistics.averageHz), String(localized: "common.unit.hertz"))
        case .medianPitch:
            return ExportMetricValue(number(pitchStatistics.medianHz), String(localized: "common.unit.hertz"))
        case .pitchStandardDeviation:
            return ExportMetricValue(number(result.f0.standardDeviationHz), String(localized: "common.unit.hertz"))
        case .pitchRange:
            return ExportMetricValue(range(pitchStatistics.low5Hz, pitchStatistics.high95Hz), String(localized: "common.unit.hertzPercentileRange"))
        case .voicedWindows:
            return ExportMetricValue(String(localized: "export.metric.voicedWindows.value \(result.f0.voicedWindowCount)"), "")
        case .environmentLoudness:
            return ExportMetricValue(number(volumeStatistics?.environmentDBFS), String(localized: "common.unit.dbfs"))
        case .averageLoudness:
            return ExportMetricValue(number(volumeStatistics?.averageDBFS), String(localized: "common.unit.dbfs"))
        case .medianLoudness:
            return ExportMetricValue(number(volumeStatistics?.medianDBFS), String(localized: "common.unit.dbfs"))
        case .loudnessRange:
            return ExportMetricValue(
                range(volumeStatistics?.low5DBFS, volumeStatistics?.high95DBFS),
                String(localized: "common.unit.dbfsPercentileRange")
            )
        case .finalScore:
            let score = VoiceDirectionScore(preference: preference, result: result)
            return ExportMetricValue(number(score.finalScore, fractionDigits: 0), String(localized: "common.unit.pointsOutOf100"))
        case .standardScore:
            let score = VoiceDirectionScore(preference: preference, result: result)
            return ExportMetricValue(number(score.standardScore, fractionDigits: 0), String(localized: "common.unit.pointsOutOf100"))
        case .naturalnessScore:
            return ExportMetricValue(number(result.naturalness.score, fractionDigits: 0), String(localized: "common.unit.pointsOutOf100"))
        case .baseScore:
            return ExportMetricValue(number(result.composite.baseScore, fractionDigits: 0), String(localized: "common.unit.pointsOutOf100"))
        }
    }

    private func number(_ value: Double?, fractionDigits: Int = 1) -> String {
        guard let value, value.isFinite else { return String(localized: "common.placeholder.noValue") }
        return value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    private func range(_ low: Double?, _ high: Double?) -> String {
        guard let low, let high, low.isFinite, high.isFinite else { return String(localized: "common.placeholder.noValue") }
        return String(localized: "export.metric.valueRange \(number(low)) \(number(high))")
    }
}

private struct ExportMetricValue {
    let value: String
    let unit: String

    init(_ value: String, _ unit: String) {
        self.value = value
        self.unit = unit
    }
}

private struct ExportReportPageModel: Identifiable {
    let id: Int
    let charts: [ExportChartOption]
    let metrics: [ExportMetricOption]
    let pageNumber: Int
    let pageCount: Int
}

private enum ExportReportPaginator {
    // Reserve the header, page margins, and footer on the fixed A4 canvas.
    private static let availableBodyHeight: CGFloat =
        ExportReportPage.pageSize.height - 84 - 44 - 17 - 18 - 23

    static func makePages(
        charts: [ExportChartOption],
        metrics: [ExportMetricOption]
    ) -> [ExportReportPageModel] {
        var groups: [([ExportChartOption], [ExportMetricOption])] = []

        if charts.isEmpty {
            groups = metricGroups(for: metrics)
        } else if fitsOnPage(charts: charts, metrics: metrics) {
            groups = [(charts, metrics)]
        } else {
            let firstMetricCount = largestFittingMetricPrefix(
                charts: charts,
                metrics: metrics
            )
            let firstMetrics = Array(metrics.prefix(firstMetricCount))
            groups.append((charts, firstMetrics))
            groups.append(contentsOf: metricGroups(for: Array(metrics.dropFirst(firstMetricCount))))
        }

        if groups.isEmpty {
            groups = [([], [])]
        }

        let pageCount = groups.count
        return groups.enumerated().map { index, group in
            ExportReportPageModel(
                id: index,
                charts: group.0,
                metrics: group.1,
                pageNumber: index + 1,
                pageCount: pageCount
            )
        }
    }

    private static func metricGroups(
        for metrics: [ExportMetricOption]
    ) -> [([ExportChartOption], [ExportMetricOption])] {
        guard !metrics.isEmpty else { return [] }

        var groups: [([ExportChartOption], [ExportMetricOption])] = []
        var remaining = metrics
        while !remaining.isEmpty {
            let count = largestFittingMetricPrefix(charts: [], metrics: remaining)
            let pageMetrics = Array(remaining.prefix(max(1, count)))
            groups.append(([], pageMetrics))
            remaining.removeFirst(pageMetrics.count)
        }
        return groups
    }

    private static func largestFittingMetricPrefix(
        charts: [ExportChartOption],
        metrics: [ExportMetricOption]
    ) -> Int {
        guard !metrics.isEmpty else { return 0 }

        var fittingCount = 0
        for count in 1...metrics.count {
            guard fitsOnPage(charts: charts, metrics: Array(metrics.prefix(count))) else { break }
            fittingCount = count
        }
        return fittingCount
    }

    private static func fitsOnPage(
        charts: [ExportChartOption],
        metrics: [ExportMetricOption]
    ) -> Bool {
        estimatedBodyHeight(charts: charts, metrics: metrics) <= availableBodyHeight
    }

    private static func estimatedBodyHeight(
        charts: [ExportChartOption],
        metrics: [ExportMetricOption]
    ) -> CGFloat {
        var height: CGFloat = 0

        if !charts.isEmpty {
            height += 16 // Charts heading.
            if charts.contains(where: { $0 != .result }) {
                height += 216 // Curves chart, including its caption and padding.
            }
            if charts.contains(.result) {
                // PitchGenderScale has a 180-point track plus labels; it makes
                // VoiceProfileReferenceChart taller than the bubble's 150 points.
                height += 282
            }
            let chartCount = (charts.contains { $0 != .result } ? 1 : 0) + (charts.contains(.result) ? 1 : 0)
            height += CGFloat(chartCount) * 12 // Gaps after the heading and between charts.
        }

        guard !metrics.isEmpty else { return height }

        if !charts.isEmpty { height += 14 }
        height += 16 + 10 // Data heading and the first group gap.

        var groupCount = 0
        for group in ExportMetricGroup.allCases {
            let count = metrics.filter { $0.group == group }.count
            guard count > 0 else { continue }

            if groupCount > 0 { height += 6 }
            height += 12 + 6 // Group heading and heading-to-grid gap.
            let rowCount = CGFloat((count + 1) / 2)
            height += rowCount * 14 + max(0, rowCount - 1) * 5
            groupCount += 1
        }
        return height
    }
}

private struct ExportReportPagePreview: View {
    let page: ExportReportPageModel
    let result: PitcheeAnalysisResult
    let volumeStatistics: RecordingVolumeStatistics?
    let preference: VoicePreference

    var body: some View {
        GeometryReader { proxy in
            let pageSize = ExportReportPage.pageSize
            let scale = min(proxy.size.width / pageSize.width, proxy.size.height / pageSize.height)
            ExportReportPage(
                page: page,
                result: result,
                volumeStatistics: volumeStatistics,
                preference: preference
            )
            .frame(width: pageSize.width, height: pageSize.height)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(ExportReportPage.a4AspectRatio, contentMode: .fit)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    }
}

private struct ExportReportPage: View {
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let a4AspectRatio = pageSize.width / pageSize.height

    let page: ExportReportPageModel
    let result: PitcheeAnalysisResult
    let volumeStatistics: RecordingVolumeStatistics?
    let preference: VoicePreference

    private var pitchStatistics: RecordingPitchStatistics {
        RecordingPitchStatistics(pitch: result.f0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if page.pageNumber == 1 {
                header
                Divider()
                    .padding(.top, 16)
            }

            VStack(alignment: .leading, spacing: 14) {
                if !page.charts.isEmpty {
                    charts
                }
                if !page.metrics.isEmpty {
                    metrics
                }
                if page.charts.isEmpty && page.metrics.isEmpty {
                    emptyState
                }
            }
            .padding(.top, 18)

            Spacer(minLength: 0)

            HStack {
                Text("export.report.footer")
                Spacer()
                Text("export.report.pageNumber \(page.pageNumber) \(page.pageCount)")
            }
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(Color.black.opacity(0.42))
            .padding(.top, 12)
        }
        .padding(42)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .medium)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("export.report.header.title")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(.black)
                Text("export.report.header.subtitle")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.52))
            }

            Spacer(minLength: 12)

            HStack(spacing: 7) {
                Image("Default")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("export.report.brandName")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
            }
        }
    }

    private var charts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("export.report.charts")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)

            if page.charts.contains(where: { $0 != .result }) {
                ExportCurvesChart(
                    result: result,
                    volumeStatistics: volumeStatistics,
                    showsFrequency: page.charts.contains(.frequency),
                    showsVoiceLoudness: page.charts.contains(.voiceLoudness),
                    showsBackgroundLoudness: page.charts.contains(.backgroundLoudness)
                )
            }

            if page.charts.contains(.result) {
                ExportResultChart(result: result, pitchStatistics: pitchStatistics)
            }
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("export.report.data")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)

            ForEach(ExportMetricGroup.allCases) { group in
                let groupMetrics = page.metrics.filter { $0.group == group }
                if !groupMetrics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.58))

                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                            alignment: .leading,
                            spacing: 5
                        ) {
                            ForEach(groupMetrics) { metric in
                                ExportMetricValueRow(
                                    metric: metric,
                                    result: result,
                                    volumeStatistics: volumeStatistics,
                                    pitchStatistics: pitchStatistics,
                                    preference: preference
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("export.report.emptyState.title")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
            Text("export.report.emptyState.message")
                .font(.system(size: 11))
                .foregroundStyle(Color.black.opacity(0.56))
        }
    }
}

private struct ExportMetricValueRow: View {
    let metric: ExportMetricOption
    let result: PitcheeAnalysisResult
    let volumeStatistics: RecordingVolumeStatistics?
    let pitchStatistics: RecordingPitchStatistics
    let preference: VoicePreference

    var body: some View {
        let value = metric.value(
            in: result,
            volumeStatistics: volumeStatistics,
            pitchStatistics: pitchStatistics,
            preference: preference
        )
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(metric.title)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.black)
                .lineLimit(1)
            Text(value.value)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(.black.opacity(0.70))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if !value.unit.isEmpty {
                Text(value.unit)
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundStyle(.black.opacity(0.52))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExportCurvesChart: View {
    let result: PitcheeAnalysisResult
    let volumeStatistics: RecordingVolumeStatistics?
    let showsFrequency: Bool
    let showsVoiceLoudness: Bool
    let showsBackgroundLoudness: Bool

    private let pitchColor = Color(red: 0.13, green: 0.36, blue: 0.82)
    private let voiceColor = Color(red: 0.90, green: 0.30, blue: 0.20)
    private let backgroundColor = Color(red: 0.18, green: 0.60, blue: 0.40)

    private var duration: Double {
        max(
            result.audio.analyzedSeconds,
            volumeStatistics?.windows.last?.centerSeconds ?? 0,
            result.f0.windows.last?.endSeconds ?? 0
        )
    }

    private var pitchDomain: ClosedRange<Double> {
        let values = result.f0.windows.compactMap(\.f0Hz).filter { $0.isFinite && $0 > 0 }
        guard let minimum = values.min(), let maximum = values.max() else { return 50...400 }
        let lower = max(40, floor(minimum / 20) * 20)
        let upper = max(lower + 80, ceil(maximum / 20) * 20)
        return lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(curveTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                Spacer()
                Text("export.chart.timeAxis.label")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.black.opacity(0.48))
            }

            Canvas { context, size in
                let leftInset: CGFloat = 38
                let rightInset: CGFloat = (showsVoiceLoudness || showsBackgroundLoudness) ? 34 : 10
                let topInset: CGFloat = 8
                let bottomInset: CGFloat = 22
                let plot = CGRect(
                    x: leftInset,
                    y: topInset,
                    width: max(1, size.width - leftInset - rightInset),
                    height: max(1, size.height - topInset - bottomInset)
                )

                for index in 0...3 {
                    let fraction = CGFloat(index) / 3
                    let y = plot.minY + plot.height * fraction
                    var grid = Path()
                    grid.move(to: CGPoint(x: plot.minX, y: y))
                    grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                    context.stroke(grid, with: .color(.black.opacity(0.10)), lineWidth: 0.6)

                    if showsFrequency {
                        let value = pitchDomain.upperBound - (pitchDomain.upperBound - pitchDomain.lowerBound) * Double(fraction)
                        context.draw(
                            Text(verbatim: "\(Int(value))" )
                                .font(.system(size: 7.5).monospacedDigit())
                                .foregroundStyle(Color.black.opacity(0.55)),
                            at: CGPoint(x: plot.minX - 6, y: y),
                            anchor: .trailing
                        )
                    }

                    if showsVoiceLoudness || showsBackgroundLoudness {
                        let value = 0 - 120 * Double(fraction)
                        context.draw(
                            Text(verbatim: "\(Int(value))")
                                .font(.system(size: 7.5).monospacedDigit())
                                .foregroundStyle(Color.black.opacity(0.55)),
                            at: CGPoint(x: plot.maxX + 6, y: y),
                            anchor: .leading
                        )
                    }
                }

                for index in 0...3 {
                    let fraction = Double(index) / 3
                    let seconds = duration * fraction
                    context.draw(
                        Text(verbatim: seconds.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 7.5).monospacedDigit())
                            .foregroundStyle(Color.black.opacity(0.50)),
                        at: CGPoint(
                            x: plot.minX + plot.width * CGFloat(fraction),
                            y: plot.maxY + 11
                        ),
                        anchor: index == 0 ? .leading : (index == 3 ? .trailing : .center)
                    )
                }

                context.clip(to: Path(plot.insetBy(dx: 0, dy: -1)))
                if showsFrequency {
                    let points = result.f0.windows.map {
                        (time: ($0.startSeconds + $0.endSeconds) / 2, value: $0.f0Hz)
                    }
                    context.stroke(
                        linePath(points: points, domain: pitchDomain, plot: plot),
                        with: .color(pitchColor),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                }
                if showsVoiceLoudness || showsBackgroundLoudness {
                    let windows = volumeStatistics?.windows ?? []
                    if showsVoiceLoudness {
                        context.stroke(
                            linePath(
                                points: windows.map { (time: $0.centerSeconds, value: $0.voiceDBFS) },
                                domain: -120...0,
                                plot: plot
                            ),
                            with: .color(voiceColor),
                            style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                        )
                    }
                    if showsBackgroundLoudness {
                        let hasIndependentBackground = windows.contains { $0.backgroundDBFS != nil }
                        let backgroundPoints: [(time: Double, value: Double?)] = windows.map {
                            (
                                time: $0.centerSeconds,
                                value: hasIndependentBackground
                                    ? $0.backgroundDBFS
                                    : volumeStatistics?.environmentDBFS
                            )
                        }
                        context.stroke(
                            linePath(
                                points: backgroundPoints,
                                domain: -120...0,
                                plot: plot
                            ),
                            with: .color(backgroundColor),
                            style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round
                            )
                        )
                    }
                }
            }
            .frame(height: 132)
            .overlay(alignment: .leading) {
                if showsFrequency {
                    Text("common.unit.hertz")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(pitchColor)
                        .rotationEffect(.degrees(-90))
                        .offset(x: -10, y: -1)
                }
            }
            .overlay(alignment: .trailing) {
                if showsVoiceLoudness || showsBackgroundLoudness {
                    Text("common.unit.dbfs")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(voiceColor)
                        .rotationEffect(.degrees(90))
                        .offset(x: 11, y: -1)
                }
            }
            .environment(\.layoutDirection, .leftToRight)

            HStack(spacing: 12) {
                if showsFrequency { legend(String(localized: "export.chart.frequency.legend"), color: pitchColor) }
                if showsVoiceLoudness { legend(String(localized: "export.chart.voiceLoudness.legend"), color: voiceColor) }
                if showsBackgroundLoudness { legend(String(localized: "export.chart.backgroundLoudness.legend"), color: backgroundColor) }
            }
            .font(.system(size: 8.5))
            .foregroundStyle(Color.black.opacity(0.62))

            Text(description)
                .font(.system(size: 8.5))
                .foregroundStyle(Color.black.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var curveTitle: String {
        let selectedCount = [showsFrequency, showsVoiceLoudness, showsBackgroundLoudness].filter { $0 }.count
        return selectedCount > 1 ? String(localized: "export.chart.combinedCurves.title") : (showsFrequency ? String(localized: "export.chart.frequencyCurve.title") : (showsVoiceLoudness ? String(localized: "export.chart.loudnessCurve.title") : String(localized: "export.chart.backgroundLoudnessCurve.title")))
    }

    private var description: String {
        if showsFrequency && (showsVoiceLoudness || showsBackgroundLoudness) {
            return String(localized: "export.chart.multiCurveGap.note")
        }
        if showsFrequency { return String(localized: "export.chart.pitchGap.note") }
        if showsVoiceLoudness && showsBackgroundLoudness { return String(localized: "export.chart.loudnessScale.note") }
        if showsVoiceLoudness { return String(localized: "export.chart.voiceLoudness.note") }
        return String(localized: "export.chart.backgroundLoudness.note")
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(title)
        }
    }

    private func linePath(
        points: [(time: Double, value: Double?)],
        domain: ClosedRange<Double>,
        plot: CGRect
    ) -> Path {
        let safeDuration = max(duration, 0.001)
        let maxGap = max(0.35, safeDuration / 18)
        var path = Path()
        var previousTime: Double?

        for point in points {
            guard let value = point.value, value.isFinite else {
                previousTime = nil
                continue
            }
            let x = plot.minX + plot.width * CGFloat(min(max(point.time / safeDuration, 0), 1))
            let normalized = min(max((value - domain.lowerBound) / (domain.upperBound - domain.lowerBound), 0), 1)
            let y = plot.maxY - plot.height * CGFloat(normalized)
            let location = CGPoint(x: x, y: y)
            if let previousTime, point.time - previousTime <= maxGap {
                path.addLine(to: location)
            } else {
                path.move(to: location)
            }
            previousTime = point.time
        }
        return path
    }
}

private struct ExportResultChart: View {
    let result: PitcheeAnalysisResult
    let pitchStatistics: RecordingPitchStatistics

    private var pitchRangeHz: ClosedRange<Double>? {
        guard let low = pitchStatistics.low5Hz,
              let high = pitchStatistics.high95Hz else { return nil }
        return low...high
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VoiceProfileReferenceChart(
                femalePercentage: result.vfp.vfpStandardScore,
                meanPitchHz: result.f0.meanHz,
                medianPitchHz: pitchStatistics.medianHz,
                pitchRangeHz: pitchRangeHz
            )
            .frame(maxWidth: 360, alignment: .leading)

            Text("export.chart.result.caption")
                .font(.system(size: 8.5))
                .foregroundStyle(Color.black.opacity(0.56))
        }
    }
}

private struct ExportPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#if DEBUG
#Preview("Mock - Export Report") {
    RecordingExportView(
        result: DebugPreviewData.result,
        volumeStatistics: DebugPreviewData.volumeStatistics,
        preference: .feminine
    )
}

#Preview("Mock - Report Without Volume") {
    RecordingExportView(result: DebugPreviewData.result, volumeStatistics: nil, preference: .feminine)
}

#Preview("Debug - Export Button", traits: .sizeThatFitsLayout) {
    RecordingExportButton(
        result: DebugPreviewData.result,
        volumeStatistics: DebugPreviewData.volumeStatistics,
        preference: .feminine
    )
    .padding()
}
#endif
