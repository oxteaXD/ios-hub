import SwiftUI

/// 模块界面上的悬浮按钮：轻点回到启动页，长按直接切到别的模块，按住可以上下拖动。
///
/// 它只停靠在屏幕右边缘。左边缘要留给系统的侧滑返回手势：按钮如果停在左边，
/// 它所在高度的那一小段就没法从边缘右滑返回了。
///
/// 它和模块界面在同一个视图层级里，所以模块弹出的面板和全屏页面会盖住它，
/// 也就是说只有在模块没有弹出任何东西时才能切换，不会把弹到一半的界面留在后面。
struct HubSwitcherBubble: View {
    let state: HubState

    /// 纵向停靠位置，用 0...1 的相对值保存，换屏幕尺寸或旋转后依然有效。
    @AppStorage("hub.bubble.y") private var storedY = 0.7
    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging = false

    private let diameter: CGFloat = 46
    private let margin: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let area = proxy.size
            let rest = restingCenter(in: area)

            bubble
                .opacity(isDragging ? 1 : 0.55)
                // 手势加在定位之前，命中范围才只是按钮本身；用全局坐标，按钮跟着手指移动时位移量不会抖。
                .gesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .global)
                        .onChanged { value in
                            isDragging = true
                            dragTranslation = value.translation
                        }
                        .onEnded { value in
                            let droppedY = rest.y + value.translation.height
                            withAnimation(.snappy) {
                                settle(atY: droppedY, in: area)
                                dragTranslation = .zero
                                isDragging = false
                            }
                        }
                )
                .position(x: rest.x + dragTranslation.width, y: rest.y + dragTranslation.height)
        }
    }

    private var bubble: some View {
        Image(systemName: "square.grid.2x2.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: diameter, height: diameter)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
            .contentShape(Circle())
            .contentShape(.contextMenuPreview, Circle())
            .onTapGesture {
                state.goHome()
            }
            .contextMenu {
                ForEach(state.modules) { module in
                    if module.id != state.activeModuleID {
                        Button {
                            state.activate(module)
                        } label: {
                            Label(module.title, systemImage: module.systemImage)
                        }
                    }
                }
                Button {
                    state.goHome()
                } label: {
                    Label("回到启动页", systemImage: "square.grid.2x2")
                }
            }
            // 对辅助功能来说它是一个按钮：名字是「回到启动页」，值是当前所在的应用。
            // 界面测试也靠这里的标识和值来判断当前显示的是哪个应用。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("回到启动页")
            .accessibilityValue(state.activeModule?.title ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                state.goHome()
            }
            .accessibilityIdentifier("hub.switcher")
    }

    /// 停靠位置：横向固定在右边缘，纵向取保存的相对位置。
    private func restingCenter(in area: CGSize) -> CGPoint {
        let spanY = max(area.height - diameter - margin * 2, 0)
        let unitY = CGFloat(min(max(storedY, 0), 1))
        return CGPoint(
            x: area.width - margin - diameter / 2,
            y: margin + diameter / 2 + spanY * unitY
        )
    }

    /// 松手后回到右边缘，只记下纵向位置。拖动过程中按钮可以跟着手指到任何地方。
    private func settle(atY droppedY: CGFloat, in area: CGSize) {
        let spanY = max(area.height - diameter - margin * 2, 1)
        let unitY = (droppedY - margin - diameter / 2) / spanY
        storedY = Double(min(max(unitY, 0), 1))
    }
}
