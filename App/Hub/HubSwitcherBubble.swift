import SwiftUI

/// 模块界面上的悬浮按钮：轻点回到启动页，长按直接切到别的模块，按住拖动可以挪位置。
///
/// 它和模块界面在同一个视图层级里，所以模块弹出的面板和全屏页面会盖住它，
/// 也就是说只有在模块没有弹出任何东西时才能切换，不会把弹到一半的界面留在后面。
struct HubSwitcherBubble: View {
    let state: HubState

    /// 停靠位置，用 0...1 的相对值保存，换屏幕尺寸或旋转后依然有效。
    @AppStorage("hub.bubble.x") private var storedX = 1.0
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
                            let dropped = CGPoint(
                                x: rest.x + value.translation.width,
                                y: rest.y + value.translation.height
                            )
                            withAnimation(.snappy) {
                                settle(at: dropped, in: area)
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
            .accessibilityLabel("回到启动页")
            .accessibilityAddTraits(.isButton)
    }

    private func restingCenter(in area: CGSize) -> CGPoint {
        let spanX = max(area.width - diameter - margin * 2, 0)
        let spanY = max(area.height - diameter - margin * 2, 0)
        let unitX = CGFloat(min(max(storedX, 0), 1))
        let unitY = CGFloat(min(max(storedY, 0), 1))
        return CGPoint(
            x: margin + diameter / 2 + spanX * unitX,
            y: margin + diameter / 2 + spanY * unitY
        )
    }

    /// 松手后吸附到左右两侧中较近的一边，纵向位置保留。
    private func settle(at point: CGPoint, in area: CGSize) {
        let spanY = max(area.height - diameter - margin * 2, 1)
        let unitY = (point.y - margin - diameter / 2) / spanY
        storedX = point.x < area.width / 2 ? 0 : 1
        storedY = Double(min(max(unitY, 0), 1))
    }
}
