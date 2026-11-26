#!/bin/bash
# Xcode 构建阶段脚本（由 project.yml 挂在 Hub 目标上）：把 Pica 依赖的动态框架放进安装包的 Frameworks 目录。
#
# 这些框架由上游的 Pods 工程编译，产物在 ${BUILT_PRODUCTS_DIR}/<名字>/<名字>.framework，
# 不在 Xcode 默认去找的位置，所以用脚本拷，做的事和 CocoaPods 自己的「Embed Pods Frameworks」一样。
# 主程序不链接它们：它们由 PicaKit.framework 链接，第一次进入 Pica 时才被载入。
set -euo pipefail

DESTINATION="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "$DESTINATION"

# 这份名单要和 project.yml 里 PicaKit 目标的依赖保持一致。
for name in AFNetworking FMDB GYDataCenter JXPagingView MJRefresh QMUIKit SDWebImage SDWebImageVideoCoder SSZipArchive SocketRocket YTKNetwork YYModel; do
    source="${BUILT_PRODUCTS_DIR}/${name}/${name}.framework"
    if [ ! -d "$source" ]; then
        echo "error: 找不到 Pica 的依赖库 ${source}"
        exit 1
    fi

    # 头文件和模块描述只在编译时有用，不放进安装包。
    rsync -a --delete \
        --exclude Headers --exclude PrivateHeaders --exclude Modules \
        "$source" "$DESTINATION/"

    # 模拟器和真机调试时需要签名才能载入；云端打未签名安装包时不签，交给用户自己的签名工具。
    if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
        /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
            --preserve-metadata=identifier,entitlements \
            "${DESTINATION}/${name}.framework"
    fi
done
