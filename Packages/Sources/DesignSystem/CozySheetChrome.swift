import SwiftUI

extension View {
    /// Title and actions of a sheet, in the same place on every platform: leading action
    /// (Cancel / Done / Close) top-left, title or `principal` centred, `trailing` top-right.
    ///
    /// iOS and iPadOS use the navigation bar. macOS draws its own header instead, because AppKit
    /// moves a sheet's toolbar items into a button row at the bottom and drops the `.principal`
    /// item altogether. Apply it to the root view inside the sheet's `NavigationStack`.
    public func cozySheetToolbar<Leading: View, Principal: View, Trailing: View>(
        title: String = "",
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder principal: () -> Principal = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(CozySheetToolbar(title: title, leading: leading(), principal: principal(), trailing: trailing()))
    }

    /// Makes a `Menu` show only its custom pill label on macOS (no system bezel or extra
    /// chevron). No change on iOS and iPadOS.
    @ViewBuilder
    public func cozyMenuPill() -> some View {
        #if os(macOS)
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        #else
        self
        #endif
    }
}

private struct CozySheetToolbar<Leading: View, Principal: View, Trailing: View>: ViewModifier {
    let title: String
    let leading: Leading
    let principal: Principal
    let trailing: Trailing

    private var hasPrincipal: Bool { Principal.self != EmptyView.self }
    private var hasTrailing: Bool { Trailing.self != EmptyView.self }

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            // Sheet fields draw their own background; drop AppKit's bezel and blue focus ring.
            .textFieldStyle(.plain)
            .safeAreaInset(edge: .top, spacing: 0) { header }
        #else
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { leading }
                if hasPrincipal {
                    ToolbarItem(placement: .principal) { principal }
                }
                if hasTrailing {
                    ToolbarItemGroup(placement: .primaryAction) { trailing }
                }
            }
        #endif
    }

    #if os(macOS)
    private var header: some View {
        ZStack {
            if hasPrincipal {
                principal
            } else {
                Text(title)
                    .font(.appHeading)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 84)
            }
            HStack(spacing: 14) {
                // Esc triggers the leading action, as it did for the system Cancel button.
                leading.keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                trailing
            }
            .buttonStyle(.plain)
            .font(.appControl)
            .foregroundStyle(Color.accent)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }
    #endif
}
