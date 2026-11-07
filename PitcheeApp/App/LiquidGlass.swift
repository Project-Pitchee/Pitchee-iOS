//
//  LiquidGlass.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import SwiftUI

private struct LiquidGlassModifier: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat
    var interactive = false
    var highlight = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            let effect = interactive
                ? Glass.regular.tint(tint).interactive()
                : Glass.regular.tint(tint)
            content
                .glassEffect(effect, in: shape)
                .overlay {
                    if highlight {
                        shape
                            .stroke(.white.opacity(0.18), lineWidth: 0.75)
                    }
                }
        } else {
            content
                .background(.thinMaterial, in: shape)
                .overlay {
                    shape
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

extension View {
    func liquidGlass(
        tint: Color,
        cornerRadius: CGFloat,
        interactive: Bool = false,
        highlight: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                tint: tint,
                cornerRadius: cornerRadius,
                interactive: interactive,
                highlight: highlight
            )
        )
    }
}

