<div align="center">
  <img src="Assets/VeloopLogo.png" alt="Veloop 图标" width="104"><br>
  <strong>Veloop</strong><br>
  <sub>让本地剪贴板历史自然出现在当前输入位置。</sub>
  <p>
    <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-30343f?style=flat&logo=apple&logoColor=white">
    <img alt="Universal arm64 与 x86_64" src="https://img.shields.io/badge/Universal-arm64_%2B_x86__64-30343f?style=flat&logo=apple&logoColor=white">
    <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-f05237?style=flat&logo=swift&logoColor=white">
    <img alt="版本 v0.2.0" src="https://img.shields.io/badge/release-v0.2.0-1683c7?style=flat">
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
- **原生支持现代 Mac：** App、普通卸载监视器、Palette 与 CLI 均以 Universal `arm64 + x86_64` 二进制交付，不依赖第三方运行时。

## 安装

### Homebrew

```bash
brew tap talentdedcat/Veloop https://github.com/talentdedcat/Veloop.git
brew trust --tap talentdedcat/Veloop
brew install --cask Veloop
```

> [!IMPORTANT]
> **首次安装：** v0.2.0 使用 ad-hoc 签名，尚未经过 Apple 公证。仅对通过本仓库安装的 Veloop 解除隔离。首次启动前请运行：
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Veloop.app
> open /Applications/Veloop.app
> ```

### DMG

[下载 `Veloop-0.2.0-universal.dmg`](https://github.com/talentdedcat/Veloop/releases/download/v0.2.0/Veloop-0.2.0-universal.dmg)，打开后将 `Veloop.app` 拖入“应用程序”。

> [!IMPORTANT]
> **首次安装：** v0.2.0 使用 ad-hoc 签名，尚未经过 Apple 公证。仅对从本仓库下载的 DMG 中安装的 Veloop 解除隔离。将 Veloop 复制到“应用程序”后、首次启动前请运行：
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Veloop.app
> open /Applications/Veloop.app
> ```

启动 Veloop 后，如需 Agent 自动运行，请在控制应用中开启“登录时启动”。DMG 中包含 `Veloop.app` 和 Applications 快捷方式。Character Palette 只是可选的光标定位优化，没有它也会直接使用辅助功能回退。在 macOS 26 上，已启用的 Palette 注册了新副本后，当前登录会话可能需要注销并重新登录一次才能发现它。

## 快速开始

1. 按 `Command-V`，在当前文本光标旁打开剪贴板历史。
2. 保持 Command 按下，按 Up 查看更旧的快照，按 Down 返回更新的快照。
3. 松开 Command，恢复并粘贴当前选中的快照。
4. 按 Escape 取消，不修改剪贴板。

历史到达首尾后停止，不会循环。如果当前文本界面没有提供有效的原生光标位置，Veloop 会保留系统原始粘贴行为。

## 权限

用户只需开启“辅助功能”。请在“**系统设置 > 隐私与安全性 > 辅助功能**”中为 Veloop 批准：

<table align="center">
  <thead>
    <tr>
      <th>权限</th>
      <th>Veloop 使用原因</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>辅助功能</strong></td>
      <td>监听全局 Command-V 序列、发送最终的模拟粘贴事件，并在 Palette 无法提供坐标时定位当前聚焦光标。</td>
    </tr>
  </tbody>
</table>

辅助功能已包含 Veloop 所需的事件监听和事件发送能力，因此不需要单独配置输入监控。Veloop 会在启用剪贴板切换前分别检查监听、事件发送和 Accessibility 访问能力。因此，即使“输入监控”列表中没有 Veloop，软件仍可正常工作。

当 macOS 已经启用 Palette 输入源时，文本光标定位首先查询 Palette。Veloop 绝不会请求 macOS 启用 Palette 输入源，因此启动或激活 Veloop 不会产生输入源确认弹窗。Palette 未启用、不可用或结果无效时，Veloop 才会读取当前聚焦的 Accessibility 元素中折叠选区的矩形，并且只会在辅助功能已经获得授权时读取。没有辅助功能授权时，剪贴板捕获仍会继续。当 Veloop 关闭或必需的事件监听能力不可用时，全局 Event Tap 停止，隐藏 Palette 取消选中，系统标准粘贴行为保持不变。

### 权限状态与故障排查

权限状态由后台 Agent 实时检查。“检查中”和“Agent 不可用”都不同于“缺失”。Veloop 绝不会主动调用 macOS 权限弹窗。即使 Agent 正在连接或检查，权限按钮也始终保持可点击，并且只会打开“系统设置”中的“辅助功能”页面，因此也能用于检查或修改已有授权。

Veloop 只使用一个权限身份和一个显示名称：`Veloop`（`com.veloop.app`）。不会安装独立的 Veloop Agent.app。请在“辅助功能”页面中添加或启用 `/Applications/Veloop.app`。后台运行时，Veloop 会把完整的已签名应用包复制到隐藏运行路径 `~/Library/Application Support/Veloop/AgentRuntime/Veloop.app`，并以 `--agent` 模式运行其中的 `Contents/MacOS/Veloop`。保留 `.app` 应用包形式后，macOS 会在隐私权限列表中显示 Veloop Logo；可执行文件内容、代码哈希、应用身份和显示名称完全相同。由于运行副本位于 `/Applications` 之外，已安装的 `/Applications/Veloop.app` 不会被占用，关闭控制窗口后即可直接移到废纸篓。

ad-hoc 二进制发生变化时，代码哈希也会变化，macOS 无法把旧授权安全地转移给新二进制。Veloop 检测到已安装可执行文件发生变化时，会在启动新 Agent 前清除旧的 Veloop 权限记录。ad-hoc 二进制更新后重新启用一次“辅助功能”，即可消除“旧 Veloop 条目显示已开启、当前二进制却被拒绝”的错误状态。重复打开同一个已安装版本不会改变代码哈希或重置授权，因此正常启动不需要再次授权。

曾从旧的无后缀 `AgentRuntime/Veloop` 路径运行 Agent 的开发版本，可能会在“辅助功能”中留下一个已关闭、使用通用图标的 Veloop 条目。它属于已经移除的路径型 TCC 身份，不是当前 Veloop；选中这个已关闭条目并点击一次减号即可移除。当前版本始终从 `AgentRuntime/Veloop.app` 运行 Agent，新权限条目会显示 Veloop 名称和 Logo，不会再产生这种路径型重复项。

每次普通激活时，Veloop 都会优先查询健康的 Agent，不会先重启。socket 每个阶段的截止时间为 200 ms，仅在查询失败后执行一次恢复。从“系统设置”返回 Veloop 时，会先仅重启 Agent 再读取权限状态，因为已经运行的进程在新增或撤销授权后都可能保留旧的 TCC 缓存结果。新进程可以准确识别两个方向的变化，同时保持 Veloop 控制应用打开。除此之外，Veloop 会立即中断当前循环，并且绝不会重新启用因用户输入而被禁用的 Event Tap；即使控制窗口尚未刷新，系统标准键盘输入也始终是失效保护路径。

## 卸载行为

“移到废纸篓时”提供两个选择。默认的“保留历史记录和设置”会在控制窗口关闭且 `/Applications/Veloop.app` 被移到废纸篓后，移除当前和旧版 Veloop 权限记录，包括旧版本产生的输入监控记录，同时移除 LaunchAgent、包外 Agent 运行副本、Palette、其他运行时文件和卸载监视器，但保留剪贴板历史与设置。“移除所有内容”还会删除全部 Veloop 历史、设置、偏好、缓存、保存状态和 WebKit 数据。发布流程会在 macOS 本机验证权限记录确实消失，并核对 `config.json` 与 `history.json` 的内容哈希在默认保留模式下完全不变。

`brew uninstall --cask veloop` 始终执行彻底清理，不受废纸篓设置影响。`brew uninstall --zap --cask veloop` 的最终状态相同。对应的直接命令是 `veloopctl uninstall --purge`。

## 控制应用

<div align="center">
  <img src="Assets/README/control-window-zh-Hans.png" alt="Veloop 简体中文控制应用" width="760">
</div>

控制应用用于管理后台 Agent、登录时启动、内容预览、历史与存储上限、系统权限、语言和本地数据。关闭窗口后控制应用退出，持久 Agent 仍可继续捕获剪贴板和处理按键。

## Focus Stack 工作原理

Veloop 会注册一个不可见的附加式 `TISCategoryPaletteInputSource`。只有 macOS 已经报告它处于启用状态时，Veloop 才会将它与用户当前键盘输入源同时选中，因此系统拼音和其他输入法继续正常工作。Veloop 绝不会调用 `TISEnableInputSource`；Palette 未启用时，光标定位会直接使用 Accessibility 回退，不会弹出确认。Palette 不实现按键、组词、候选或文本插入处理，只保存 macOS 提供的 `IMKTextInput` 会话。

每次 Command-V 切换开始时，Agent 会首先查询 Palette，向当前前台应用发送一次有超时上限的本机 `CFMessagePort` 请求。辅助组件要求选区已经折叠，优先使用 `attributesForCharacterIndex:lineHeightRectangle:`，仅在线矩形无效时才读取同一文本客户端的零长度 `firstRectForCharacterRange`。Veloop 只接受位于真实显示器内、尺寸符合插入线特征的有限矩形。

如果 Palette 不可用、返回了其他进程，或提供了无效坐标，Veloop 会对当前聚焦的 Accessibility 元素执行一次回退查询。它会确认元素属于当前前台进程，要求 `AXSelectedTextRange` 已折叠，并且只读取这个选区的矩形。它不会遍历 Accessibility 树，也不会读取元素的文本；这条路径绝不会请求权限。

两条路径都不使用鼠标位置、点击历史、截图、OCR、后台重试、旧位置缓存或应用特判。如果两个来源都没有返回有效坐标，Veloop 不显示浮层，也不拦截系统原始粘贴。

### 兼容性与回退行为

系统输入法与 Palette 共存、中文组词以及正式光标查询路径，已在原生文本编辑器、聊天输入框、代码编辑器、浏览器地址栏和网页可编辑区域中验证。借助 Accessibility 回退，已经运行的应用不需要重新连接 Palette 或重新启动，Veloop 就能定位当前聚焦的可编辑区域。

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

通过 Homebrew 安装时，`veloopctl` 会加入 `PATH`。通过 DMG 安装时，同一个可执行文件位于应用包内；如果命令不在 `PATH` 中，请使用 `/Applications/Veloop.app/Contents/Resources/veloopctl` 调用。

```bash
veloopctl status
veloopctl pause
veloopctl resume
veloopctl clear
veloopctl count
veloopctl storage
veloopctl doctor
veloopctl config get
veloopctl config set maximumHistoryCount 200
veloopctl open-data-directory
veloopctl uninstall --purge
veloopctl version
```

需要 Agent 运行的命令包括 `status`、`pause`、`resume`、`clear`、`count`、`storage`、`doctor`、`config get` 和 `config set`。`open-data-directory`、`uninstall --purge` 与 `version` 在本地执行，不要求 Agent 正在运行。数值配置键包括 `maximumHistoryCount`、`maximumDiskBytes`、`maximumSingleSnapshotBytes` 和 `pollIntervalMilliseconds`，值必须是大于零的整数。布尔配置键包括 `captureConcealed`、`captureTransient`、`captureAutoGenerated`、`startEnabled` 和 `showContentPreviews`，值使用 `true` 或 `false`。数量、容量、启用状态和预览设置会立即同步；捕获策略与轮询间隔在 Agent 下次启动时生效。

Agent 与 CLI 通过权限为 `0600` 的 Unix-domain socket 通信，不监听 TCP。`restart` 不属于当前支持的公开命令。

## 项目结构

```text
Sources/
  App/                   控制界面、本地化与 --agent 入口
  Core/
    Agent/               后台运行时与注册管理
    Clipboard/           剪贴板捕获、快照与恢复
    CommandLine/         CLI 解析、协议、socket 客户端与服务端
    Configuration/       持久化运行配置
    Control/             控制窗口状态与 Agent 协调
    History/             历史索引、保留策略与仓库
    Input/               全局 Event Tap 与粘贴循环状态
    Overlay/             光标定位与 Focus Stack 展示
    Permissions/         事件和辅助功能预检
    Storage/             原子清单、blob 与文件快照
    Support/             常量、日志、锁与系统接口封装
    Uninstall/           废纸篓监视策略、TCC 重置与清理
  Palette/               附加式 InputMethodKit 光标桥接组件
  UninstallWatcher/      普通事件驱动卸载监视器入口
  Veloopctl/             内嵌 veloopctl 可执行文件入口
Tests/                   行为与打包契约
Configuration/           应用与 Palette 的 bundle 元数据
Packaging/               发布构建、DMG 创建与验证脚本
Casks/                   Homebrew Cask 定义
Docs/                    本地化 README、产品媒体、规格与计划
```

模块职责、运行流程和架构约束请参阅[源码导览](../Sources/README.md)。

## 许可证

Veloop 使用 [MIT License](../LICENSE)。Copyright (c) 2026 Veloop contributors。
