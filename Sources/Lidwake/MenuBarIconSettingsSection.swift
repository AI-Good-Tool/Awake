import SwiftUI

struct MenuBarIconSettingsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Section("菜单栏图标") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    styleButton(style)
                }
            }
            .padding(.vertical, 6)

            Toggle("运行时使用彩色图标", isOn: $appState.menuBarIconUsesActiveColor)
            ColorPicker("运行颜色", selection: Binding(
                get: { Color(nsColor: BrandImages.activeStatusColor(hex: appState.menuBarIconColorHex)) },
                set: { appState.menuBarIconColorHex = NSColor($0).hexString }
            ), supportsOpacity: false)
            .disabled(!appState.menuBarIconUsesActiveColor)

            Button("恢复默认蓝色") {
                appState.menuBarIconColorHex = Brand.defaultActiveColorHex
            }
            .disabled(!appState.menuBarIconUsesActiveColor || appState.menuBarIconColorHex == Brand.defaultActiveColorHex)

            HStack(spacing: 12) {
                Text("预览").foregroundStyle(.secondary)
                icon(appState.menuBarIconStyle, active: true)
                Text("运行").foregroundStyle(.secondary)
                icon(appState.menuBarIconStyle, active: false)
                Text("关闭 / 暂停").foregroundStyle(.secondary)
            }
            Text("点选样式立即生效，下次启动保留选择。运行时实心，关闭或暂停时空心。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func icon(_ style: MenuBarIconStyle, active: Bool) -> some View {
        Image(nsImage: BrandImages.statusBarCoffeeCupSymbol(
            mode: active ? .keepDisplayOn : .off,
            usesActiveColor: appState.menuBarIconUsesActiveColor,
            activeColorHex: appState.menuBarIconColorHex,
            style: style
        ))
        .frame(width: 25, height: 18)
        .accessibilityHidden(true)
    }

    private func styleButton(_ style: MenuBarIconStyle) -> some View {
        let selected = appState.menuBarIconStyle == style
        return Button {
            appState.menuBarIconStyle = style
        } label: {
            HStack(spacing: 10) {
                icon(style, active: true)
                Text(style.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityValue(selected ? "已选中" : "未选中")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
