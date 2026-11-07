//
//  DashboardAddComponentsView.swift
//  Pitchee
//
//  Created by Ryo on 2026/10/7.
//

import SwiftUI

struct DashboardAddComponentsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let components: [DashboardComponent]
    let theme: AppThemeOption
    let onSelect: (DashboardComponent) -> Void
    @State private var hasSelected = false

    private var appearance: GradientAppearance { colorScheme == .dark ? .dark : .light }
    private var palette: AppThemePalette {
        theme.dashboardPalette(for: appearance, contrast: colorSchemeContrast)
    }

    var body: some View {
        NavigationStack {
            List {
                if components.isEmpty {
                    ContentUnavailableView {
                        Label("insights.dashboard.editor.title", systemImage: "checkmark.circle")
                            .foregroundStyle(palette.primaryText)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(components) { component in
                            Button { select(component) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: component.symbol)
                                        .foregroundStyle(palette.accent)
                                        .frame(width: 28)
                                    Text(LocalizedStringKey(component.titleKey))
                                        .foregroundStyle(palette.primaryText)
                                    Spacer(minLength: 8)
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(palette.accent)
                                        .accessibilityHidden(true)
                                }
                                .font(.body.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .liquidGlass(tint: .clear, cornerRadius: 16)
                            }
                            .buttonStyle(.plain)
                            .disabled(hasSelected)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text("insights.dashboard.available.title")
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background {
                ThemeBackground(theme: theme, appearance: appearance, intensity: colorScheme == .dark ? 0.94 : 0.78)
            }
            .navigationTitle("insights.dashboard.editor.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.action.done") { dismiss() }
                        .tint(palette.primaryText)
                }
            }
        }
    }

    private func select(_ component: DashboardComponent) {
        guard !hasSelected else { return }
        hasSelected = true
        onSelect(component)
        dismiss()
    }
}
