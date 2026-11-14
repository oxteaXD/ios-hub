# 第三方声明

本仓库把下面两个开源项目整合进同一个 App。它们的源码以 git 子模块的形式放在 `upstream/` 下，
子模块里是上游的原样代码；本仓库对它们做的全部改动都列在 [README](README.md#对上游的改动) 里，
并在改动处用 `[Hub]` 标出。

整合后的整体按 [GNU AGPL-3.0](LICENSE) 发布。

## Pixiv-SwiftUI

- 仓库：https://github.com/Eslzzyl/Pixiv-SwiftUI
- 许可证：GNU Affero General Public License v3.0（全文见 [LICENSE](LICENSE)）
- 构建时还会从它的发行包里取出标签翻译数据 `tags.json`，随 App 一起打包。

## EhPanda

- 仓库：https://github.com/EhPanda-Team/EhPanda
- 许可证：MIT

```
MIT License

Copyright (c) 2023 EhPanda Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 其余依赖

两个上游项目各自依赖的 Swift 包（Kingfisher、Kanna、The Composable Architecture、SDWebImage 等）
在构建时由 Swift Package Manager 拉取，各自的许可证见它们的仓库。
