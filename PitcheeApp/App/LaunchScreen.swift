import SwiftUI

// Adapted from Kavsoft's ASplashScreen.zip: ASplashScreen/ASplashScreen/Helpers/LaunchScreen.swift.
struct OnboardingLaunchView<Content: View>: View {
    let phase: LaunchPhase
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            let revealed = phase != .initial
            let iconSize: CGFloat = geometry.size.height < 600 ? 64 : 120
            let showingContent = phase == .revealed || phase == .finished

            ZStack {
                ZStack {
                    RoundedRectangle(cornerRadius: revealed ? iconSize * 0.3 : 0)
                        .fill(Color("LaunchBackground"))

                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: revealed ? iconSize * 0.72 : 150,
                               height: revealed ? iconSize * 0.72 : 150)
                }
                .frame(width: revealed ? iconSize : nil, height: revealed ? iconSize : nil)
                .frame(maxWidth: .infinity, maxHeight: revealed ? nil : .infinity)
                .padding(.vertical, revealed ? 12 : 0)
                .scaleEffect(phase == .contracted ? 0.95 : 1)
                .offset(y: phase == .contracted ? 32 : 0)
                .opacity(showingContent ? 0 : 1)
                .zIndex(1)
                .geometryGroup()
                .ignoresSafeArea(edges: revealed ? [] : .all)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                content
                    .compositingGroup()
                    .visualEffect { content, proxy in
                        content
                            .blur(radius: showingContent ? 0 : 15)
                            .opacity(showingContent ? 1 : 0)
                            .offset(y: showingContent ? 0 : proxy.size.height)
                    }
            }
        }
    }
}

struct ReturningLaunchView: View {
    let phase: LaunchPhase

    var body: some View {
        GeometryReader { geometry in
            let revealing = phase == .revealed || phase == .finished
            let scale = max(geometry.size.width, geometry.size.height) * 4 / 150

            Color("LaunchBackground")
                .mask {
                    Rectangle()
                        .overlay {
                            logo
                                .scaleEffect(phase == .initial ? 1 : 0.8)
                                .scaleEffect(revealing ? scale : 1)
                                .opacity(revealing ? 1 : 0)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .overlay {
                    logo
                        .scaleEffect(phase == .initial ? 1 : 0.8)
                        .scaleEffect(revealing ? scale : 1)
                        .opacity(revealing ? 0 : 1)
                }
                // The lettering has transparent gaps even at full scale.
                .opacity(revealing ? 0 : 1)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var logo: some View {
        Image("LaunchLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 150, height: 150)
    }
}
