//
//  FoldAwareArrangementView.swift
//  Pitchee
//
//  Created by Ryo on 2026/9/19.
//
//  Keeps the regular layout for phones and fully-open displays, and switches
//  to the system arrangement container when iPhone Duo reports an active fold
//  division. ArrangementView knows how to place the panes on either side of
//  the fold and keeps both panes reachable while the device changes pose.
//

import SwiftUI

struct FoldAwareArrangementView<Primary: View, Secondary: View, Regular: View>: View {
    private let primary: () -> Primary
    private let secondary: () -> Secondary
    private let regular: () -> Regular

    init(
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary,
        @ViewBuilder regular: @escaping () -> Regular
    ) {
        self.primary = primary
        self.secondary = secondary
        self.regular = regular
    }

    var body: some View {
        if #available(iOS 27.1, *) {
            GeometryReader { proxy in
                if proxy.reservedRegions(kind: .division).contains(where: \.isActive) {
                    ArrangementView {
                        primary()
                    } secondary: {
                        secondary()
                    }
                    .arrangementViewStyle(.split)
                } else {
                    regular()
                }
            }
        } else {
            regular()
        }
    }
}

#if DEBUG
#Preview("Debug - Adaptive Layout") {
    FoldAwareArrangementView(
        primary: {
            Text(verbatim: "Primary pane")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.blue.opacity(0.08))
        },
        secondary: {
            Text(verbatim: "Secondary pane")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.purple.opacity(0.08))
        },
        regular: {
            VStack(spacing: 24) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.largeTitle)
                Text(verbatim: "Regular layout")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.blue.opacity(0.08))
        }
    )
}
#endif
