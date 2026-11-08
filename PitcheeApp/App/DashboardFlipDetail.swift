import SwiftData
import SwiftUI

// Measure outside the legacy card's UIHostingController so both drag paths use window coordinates.
struct DashboardFlipSource: ViewModifier {
    let isHidden: Bool
    let onFrameChange: (CGRect) -> Void

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrameChange($0) }
            .opacity(isHidden ? 0 : 1)
    }
}

struct DashboardFlipDetail: View {
    let component: DashboardComponent
    let size: DashboardComponentSize
    let sourceFrame: CGRect?
    let snapshot: DashboardSnapshot
    let preference: VoicePreference
    let palette: AppThemePalette
    let range: InsightsRange
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0
    @State private var isReady = false

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.6, extraBounce: 0)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(560, geometry.size.width - 32)
            let height = min(geometry.size.height - 32, max(440, width * 1.2))
            let bounds = CGRect(
                x: (geometry.size.width - width) / 2,
                y: (geometry.size.height - height) / 2,
                width: width, height: height
            )
            let origin = geometry.frame(in: .global).origin
            let source = sourceFrame?.offsetBy(dx: -origin.x, dy: -origin.y) ?? bounds
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.12 * progress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                DashboardCard(
                    component: component, size: size, snapshot: snapshot,
                    preference: preference, palette: palette, isEditing: false
                )
                .modifier(DashboardFlipFace(
                    progress: progress, source: source, destination: bounds,
                    isFront: true, reduceMotion: reduceMotion || sourceFrame == nil
                ))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                VStack(spacing: 0) {
                    header
                    detail
                }
                .background(.regularMaterial)
                .modifier(DashboardFlipFace(
                    progress: progress, source: source, destination: bounds,
                    isFront: false, reduceMotion: reduceMotion || sourceFrame == nil
                ))
                .allowsHitTesting(isReady)
                .accessibilityHidden(!isReady)
                .accessibilityAction(.escape, close)
            }
        }
        .interactiveDismissDisabled()
        .task {
            withAnimation(animation, completionCriteria: .removed) {
                progress = 1
            } completion: {
                isReady = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label {
                Text(component == .compositeScore ? preference.scoreTitle : LocalizedStringKey(component.titleKey))
            } icon: {
                Image(systemName: component.symbol)
                    .foregroundStyle(palette.accent)
            }
            .font(.headline)
            .foregroundStyle(palette.primaryText)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button("common.action.close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.detail.close")
                .disabled(!isReady)
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var detail: some View {
        switch component {
        case .analysisCount:
            NavigationStack {
                RecordingHistoryView(range: range, now: snapshot.referenceDate)
                    .toolbar(.hidden, for: .navigationBar)
            }
        case .openedDays: InsightsActivityView(range: range, now: snapshot.referenceDate)
        case .compositeScore: InsightsMetricDetailView(metric: .composite, range: range, now: snapshot.referenceDate)
        case .naturalness: InsightsMetricDetailView(metric: .naturalness, range: range, now: snapshot.referenceDate)
        case .meanPitch: InsightsMetricDetailView(metric: .pitch, range: range, now: snapshot.referenceDate)
        }
    }

    private func close() {
        guard isReady else { return }
        isReady = false
        withAnimation(animation, completionCriteria: .removed) {
            progress = 0
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dismiss() }
        }
    }
}

private struct DashboardFlipFace: AnimatableModifier {
    var progress: Double
    let source: CGRect
    let destination: CGRect
    let isFront: Bool
    let reduceMotion: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let flip = DashboardFlipGeometry(progress: progress, source: source, destination: destination)
        let frame = reduceMotion ? destination : flip.frame
        let visible = isFront ? flip.showsFront : !flip.showsFront
        content
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 20 + 8 * flip.progress))
            .contentShape(RoundedRectangle(cornerRadius: 20 + 8 * flip.progress))
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : (isFront ? flip.frontAngle : flip.backAngle)),
                axis: (x: 0, y: 1, z: 0), perspective: 0.3
            )
            .opacity(reduceMotion ? (isFront ? 0 : flip.progress) : (visible ? 1 : 0))
            .position(x: frame.midX, y: frame.midY)
    }
}

#if DEBUG
#Preview("Dashboard flip hero") {
    @Previewable @State var range = InsightsRange.sevenDays
    if let container = DebugPreviewStore.makeContainer(withHistory: true) {
        NavigationStack { TrendsView(range: $range, showsRangePicker: false) }
            .safeAreaInset(edge: .bottom) {
                InsightsRangeTabBar(selection: $range)
                    .background(.regularMaterial)
            }
            .modelContainer(container)
            .defaultAppStorage(DebugPreviewDefaults.store)
    }
}
#endif
