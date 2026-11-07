import SwiftUI

/// The welcome page owns the final position, including Dynamic Type and scrolling.
struct OnboardingLaunchIconAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct OnboardingBrandIcon: View {
    static let size: CGFloat = 136

    var body: some View {
        Image("Default")
            .resizable()
            .scaledToFit()
            .frame(width: Self.size, height: Self.size)
            .clipShape(RoundedRectangle(cornerRadius: Self.size * 0.23, style: .continuous))
    }
}

// Adapted from Kavsoft's ASplashScreen.zip: ASplashScreen/ASplashScreen/Helpers/LaunchScreen.swift.
struct OnboardingLaunchView<Content: View>: View {
    let phase: LaunchPhase
    @ViewBuilder var content: Content

    var body: some View {
        let showingContent = phase == .revealed || phase == .finished
        content
            .opacity(showingContent ? 1 : 0)
            .overlayPreferenceValue(OnboardingLaunchIconAnchorKey.self) { anchor in
                if phase != .finished {
                    GeometryReader { geometry in
                        if let anchor {
                            launchIcon(in: geometry.size, target: geometry[anchor])
                        } else {
                            // Standalone previews of later pages still have a launch transition.
                            launchIcon(in: geometry.size, target: CGRect(
                                x: (geometry.size.width - OnboardingBrandIcon.size) / 2,
                                y: (geometry.size.height - OnboardingBrandIcon.size) / 2,
                                width: OnboardingBrandIcon.size, height: OnboardingBrandIcon.size
                            ))
                            .opacity(showingContent ? 0 : 1)
                        }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }

    private func launchIcon(in size: CGSize, target: CGRect) -> some View {
        let expanded = phase == .initial
        let showsAppIcon = phase == .revealed || phase == .finished

        return ZStack {
            Color("LaunchBackground")
                .opacity(showsAppIcon ? 0 : 1)
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: expanded ? 150 : target.width * 0.9,
                       height: expanded ? 150 : target.height * 0.9)
                .opacity(showsAppIcon ? 0 : 1)
            OnboardingBrandIcon()
                .opacity(showsAppIcon ? 1 : 0)
        }
        .frame(width: expanded ? size.width : target.width,
               height: expanded ? size.height : target.height)
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : target.width * 0.23,
                                    style: .continuous))
        .position(x: expanded ? size.width / 2 : target.midX,
                  y: expanded ? size.height / 2 : target.midY)
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
