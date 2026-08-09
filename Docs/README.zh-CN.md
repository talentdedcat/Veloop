<div align="center">
  <img src="Assets/VeloopLogo.png" alt="Veloop 图标" width="104"><br>
  <strong>Veloop</strong><br>
  <sub>让本地剪贴板历史自然出现在当前输入位置。</sub>
  <p>
    <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-30343f?style=flat&logo=apple&logoColor=white">
    <img alt="Universal arm64 与 x86_64" src="https://img.shields.io/badge/Universal-arm64_%2B_x86__64-30343f?style=flat&logo=apple&logoColor=white">
    <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-f05237?style=flat&logo=swift&logoColor=white">
    <img alt="版本 v0.1.0" src="https://img.shields.io/badge/release-v0.1.0-1683c7?style=flat">
    <img alt="MIT 许可证" src="https://img.shields.io/badge/license-MIT-5b9d2f?style=flat">
  </p>
  <p><a href="../README.md">English</a> · 简体中文</p>
  <img src="Assets/README/focus-stack-depth-push.gif" alt="Veloop 在当前文本光标旁切换剪贴板历史" width="720">
  <p><code>⌘V</code> 打开 · <code>⌘↑</code> 更旧 · <code>⌘↓</code> 更新 · 松开 <code>⌘</code> 粘贴</p>
</div>

Veloop 是一款原生 macOS 剪贴板历史应用。它完整保存可物化读取的 pasteboard 快照，在当前文本光标旁呈现历史，并让捕获、存储、预览与恢复全部留在本机。

## 亮点

- **在输入位置工作：** 非激活式 Focus Stack 出现在真实文本插入光标旁，不会抢走当前应用的焦点。
- **忠实保存剪贴板：** 只要数据可以物化读取，就会保留 item 顺序、并行表示、自定义 UTType、富文本、图片、媒体字节、文件与文件夹。
- **本地优先：** Veloop 没有云同步、分析、崩溃上传、网络监听或自动远程下载。
- **安静驻留后台：** Agent 没有 Dock 图标、菜单栏项目、通知或常驻浮层。
- **容量有界且行为可预期：** 历史默认保留 100 条、100 MB，并通过持久化 LRU 淘汰最久未使用且未受保护的快照。
- **原生支持现代 Mac：** App、Agent、Palette 与 CLI 均以 Universal `arm64 + x86_64` 二进制交付，不依赖第三方运行时。

## 安装

### DMG

[下载 `Veloop-0.1.0-universal.dmg`](https://github.com/talentdedcat/Veloop/releases/download/v0.1.0/Veloop-0.1.0-universal.dmg)，打开后将 `Veloop.app` 拖入 `Applications`。首次启动 Veloop 后，如需 Agent 自动运行，请在控制应用中开启“登录时启动”。

> **首次启动：** v0.1.0 使用 ad-hoc 签名，尚未经过 Apple 公证。尝试打开 Veloop 后，请进入“**系统设置 > 隐私与安全性**”，滚动到“**安全性**”并选择“**仍要打开**”。仅对从本仓库下载的 DMG 执行此操作。参阅 [Apple 官方说明](https://support.apple.com/guide/mac-help/mh40616/mac)。

DMG 中包含 `Veloop.app` 和 Applications 快捷方式。在 macOS 26 上，全新注册的 Character Palette 可能需要注销并重新登录一次，当前登录会话才能发现它。

## 快速开始

1. 按 `Command-V`，在当前文本光标旁打开剪贴板历史。
2. 保持 Command 按下，按 Up 查看更旧的快照，按 Down 返回更新的快照。
3. 松开 Command，恢复并粘贴当前选中的快照。
4. 按 Escape 取消，不修改剪贴板。

历史到达首尾后停止，不会循环。如果当前文本界面没有提供有效的原生光标位置，Veloop 会保留系统原始粘贴行为。

## 权限

请在“**系统设置 > 隐私与安全性**”中为 Veloop 批准：

<table align="center">
  <thead>
    <tr>
      <th>权限</th>
      <th>Veloop 使用原因</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>输入监控</strong></td>
      <td>在剪贴板切换已启用时监听全局 Command-V 序列。</td>
    </tr>
    <tr>
      <td><strong>辅助功能</strong></td>
      <td>选中历史记录后发送最终的模拟粘贴事件。</td>
    </tr>
  </tbody>
</table>

文本光标定位不使用辅助功能权限。缺少这两项权限时，剪贴板捕获仍会继续。当 Veloop 关闭或输入监控不可用时，全局 Event Tap 停止，隐藏 Palette 取消选中，系统标准粘贴行为保持不变。

## 控制应用

<div align="center">
  <img src="Assets/README/control-window-zh-Hans.png" alt="Veloop 简体中文控制应用" width="760">
</div>

控制应用用于管理后台 Agent、登录时启动、内容预览、历史与存储上限、系统权限、语言和本地数据。关闭窗口后控制应用退出，内嵌登录项仍可继续捕获剪贴板和处理按键。

## Focus Stack 工作原理

Veloop 会安装一个不可见的附加式 `TISCategoryPaletteInputSource`。它与用户当前键盘输入源同时选中，因此系统拼音和其他输入法继续正常工作。Palette 不实现按键、组词、候选或文本插入处理，只保存 macOS 提供的 `IMKTextInput` 会话。

每次 Command-V 切换开始时，Agent 会向当前前台应用发送一次有超时上限的本机 `CFMessagePort` 请求。辅助组件要求选区已经折叠，优先使用 `attributesForCharacterIndex:lineHeightRectangle:`，仅在线矩形无效时才读取同一文本客户端的零长度 `firstRectForCharacterRange`。Veloop 只接受位于真实显示器内、尺寸符合插入线特征的有限矩形。

这条路径不扫描 Accessibility 树，也不使用鼠标位置、点击历史、截图、OCR、后台重试、旧位置缓存或应用特判。如果文本客户端没有返回有效坐标，Veloop 不显示浮层，也不拦截系统原始粘贴。

### 兼容性与回退行为

系统拼音与 Palette 共存以及中文组词已在 TextEdit 验证。正式光标查询路径已验证 TextEdit、微信聊天输入框、备忘录、Xcode、Visual Studio Code，以及 Safari 和 Microsoft Edge 的可编辑网页输入框。浏览器地址栏等没有建立原生文本输入会话的界面不会显示浮层。

测试 Mac 的热请求约为 1.6-7.2 ms；这是本机测量数据，不是平台固定保证。主卡片尺寸为 `348 × 104 pt`。切换历史使用 180 ms 垂直 Depth Push；开启“减少动态效果”后改用 100 ms 淡入淡出。

## 保存的数据

一次复制对应一个 `PasteboardSnapshot`，保存 pasteboard item 的顺序，以及捕获时数据可以物化读取的全部类型表示，包括：

- 纯文本、富文本、HTML、URL、文件 URL 和自定义 UTType。
- PNG、JPEG、TIFF、HEIC、PDF、SVG 和 GIF 表示。
- 直接存在于 pasteboard 中的音频或视频字节。
- Finder 文件和文件夹、多 item，以及单 item 的并行表示。

“全部表示”不包括源应用从未写入 pasteboard 的数据、已经失效的延迟数据、无法物化的 promised data，以及 HTTP URL 背后的远程内容。Veloop 不会自动下载远程 URL。

对于本地文件 URL，Veloop 会保存原始表示，并将引用的对象复制到快照存储。大文件按 1 MiB 分块复制和哈希；媒体不转码、不压缩。

## 隐私与存储

- 历史记录保存在 `~/Library/Application Support/Veloop/`。
- 日志不记录剪贴板文本、URL、文件名和原始字节。
- concealed、transient、auto-generated 及常见密码管理器表示默认跳过。
- 文本预览最多保留 240 个 Unicode 标量。
- 图片预览会下采样到 320 像素，并仅保存在上限 6 MiB 的临时缓存中。
- 相同 blob 只存储一次，成功粘贴会刷新并持久化 LRU 顺序。
- 达到配额后，优先淘汰最久未使用且未受保护的快照；关闭内容预览后只显示元数据。

## 命令行

```bash
veloopctl status
veloopctl pause
veloopctl resume
veloopctl clear
veloopctl count
veloopctl storage
veloopctl doctor
veloopctl config get
veloopctl open-data-directory
veloopctl restart
veloopctl version
```

Agent 与 CLI 通过权限为 `0600` 的 Unix-domain socket 通信，不监听 TCP。

## 项目结构

```text
Sources/App/             控制应用与本地化
Sources/Agent/           内嵌后台 Agent 入口
Sources/Core/            捕获、历史、按键、浮层、存储与 IPC
Sources/Veloopctl/       内嵌 veloopctl 入口
Sources/Palette/         附加式 InputMethodKit 光标桥接组件
Tests/                   行为与打包契约
Docs/                    本地化 README 与产品媒体
```

模块职责、运行流程和架构约束请参阅[源码导览](../Sources/README.md)。

## 许可证

Veloop 使用 [MIT License](../LICENSE)。Copyright (c) 2026 Veloop contributors。
