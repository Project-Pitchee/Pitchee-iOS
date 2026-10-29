//
//  PitcheeAndroidFont.swift
//  Pitchee
//
//  Android uses Roboto for primary text and Noto Sans CJK for Chinese.
//  Keep that pairing available without relying on the iOS system UI font.
//

import CoreText
import SwiftUI
import UIKit

enum PitcheeAndroidFont {
    static func registerBundledFonts() {
        for name in [
            "Roboto-Regular",
            "Roboto-Medium",
            "Roboto-Bold",
            "Roboto-Black",
            "NotoSansSC"
        ] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func font(size: CGFloat, weight: UIFont.Weight = .regular) -> Font {
        let robotoName: String = switch weight {
        case .black, .heavy:
            "Roboto-Black"
        case .bold:
            "Roboto-Bold"
        case .medium, .semibold:
            "Roboto-Medium"
        default:
            "Roboto-Regular"
        }
        let notoName: String = switch weight {
        case .black, .heavy:
            "NotoSansSCThin-Black"
        case .bold:
            "NotoSansSCThin-Bold"
        case .medium, .semibold:
            "NotoSansSCThin-Medium"
        default:
            "NotoSansSCThin-Regular"
        }

        guard let roboto = UIFont(name: robotoName, size: size) else {
            return .system(size: size, weight: fontWeight(weight))
        }

        var attributes: [UIFontDescriptor.AttributeName: Any] = [:]
        if let noto = UIFont(name: notoName, size: size) {
            attributes[.cascadeList] = [noto.fontDescriptor]
        }
        let descriptor = roboto.fontDescriptor.addingAttributes(attributes)
        return Font(UIFont(descriptor: descriptor, size: size))
    }

    private static func fontWeight(_ weight: UIFont.Weight) -> Font.Weight {
        switch weight {
        case .black, .heavy:
            .black
        case .bold:
            .bold
        case .medium, .semibold:
            .medium
        default:
            .regular
        }
    }
}
