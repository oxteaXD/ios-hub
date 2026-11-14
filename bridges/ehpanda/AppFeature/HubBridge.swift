// 这个文件不属于 EhPanda 上游。
// 它由宿主工程的 scripts/prepare.py 在构建前复制进 AppFeature 模块，只新增接口，不改动上游代码。

import ComposableArchitecture
public import SwiftUI

extension AppDelegate {
    /// 把宿主观察到的场景阶段变化交给 EhPanda 处理。
    ///
    /// EhPanda 自己的界面挂载着的时候，由它的 `TabBarView` 上报场景阶段；界面没挂载时（用户正在
    /// 用别的模块）就没人上报，进入后台的通知到不了下载模块。宿主只在后一种情况下调用这个方法，
    /// 两边同时上报会让回到前台的处理执行两遍。
    public func hubForward(scenePhase: ScenePhase) {
        store.send(.onScenePhaseChange(scenePhase))
    }
}
