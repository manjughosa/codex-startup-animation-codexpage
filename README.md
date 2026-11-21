# codex star up animation+Codex page美化插件整合包

本机版入口叫 **3号插件**。它是两个社区项目的本地整合与兼容适配，**不是 OpenAI 官方产品，也不是对上游的重新发布或官方背书**。

3号用 R16 播放开屏动画、等待客户端窗口并做落泪转场，由包内的 CodexPage 管理小龙娘视频壁纸。需要 Windows x64、.NET Framework 4.8 和微软商店版 Codex。

## 日常使用

- 双击桌面的 **3号插件**：开屏动画、等待 Codex 窗口就绪并播放动态壁纸。
- 双击桌面的 **3号插件 - 壁纸管理器**：选择图库里的 **Dragon Ambient**（常态版）或 **Dragon Particles**（粒子版），也可以导入自己的图片或视频。
- 也可以直接运行安装目录内的 `Launch.exe` 和 `CodexPage\CodexSkinManager.exe`。

## 上游与分工

| 来源 | 在本整合包中的作用 |
| --- | --- |
| [mytjxs/codex-startup-animation](https://github.com/mytjxs/codex-startup-animation) | 原龙娘启动动画及启动器概念与素材来源。 |
| [HanwenZhang-George/codex-startup-animation · R16](https://github.com/HanwenZhang-George/codex-startup-animation/releases/tag/community-v34-r5) | R16 的启动动画、窗口交接与签名/路径校验基础。 |
| [JiPaiFan1109/CodexPage · 3.8.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.8.0) | 壁纸库、导入、视频播放与 Codex 页面注入基础。其上游为 [Fei-Away/Codex-Dream-Skin v1.5.18](https://github.com/Fei-Away/Codex-Dream-Skin)。 |
| 本项目的适配 | 将原开屏器改为调用包内壁纸引擎，停用旧壁纸宿主，修复新版 Codex 的页面识别、主区透明背景及输入框圆角。 |

这只是**插件整合包与本地适配代码**，不替代 Codex，也不修改 Codex 本体、签名、账号或模型设置。

## 本地复建

1. 从上方 **R16 官方发布页**下载 `CodexDragon-V34-Portable-Windows-x64-r5.zip`（该链接保留旧文件名，内容是 R16），完整解压到普通本地目录，例如 `C:\Temp\CodexDragon-R16`。保留其中 `release-manifest.json`、`source`、`assets`、`output`。
2. 确认有 Windows PowerShell 5.1、.NET Framework 4.8、微软商店版 Codex，以及包含 `libx264` 的 `ffmpeg.exe`。
3. 运行下面命令，将 `D:\Apps\CodexPlugin3` 换成一个尚不存在的安装目录：

```powershell
.\Build-Local.ps1 -UpstreamDirectory 'C:\Temp\CodexDragon-R16' -FetchNode -Destination 'D:\Apps\CodexPlugin3'
```

如果 `.local\CodexPage\engine\runtime\node` 已经有校验过的 Node.js 24.22.1，可省略 `-FetchNode`。输入脚本只复制官方 R16 媒体与构建输入，按 SHA-256 校验后生成 1080p 播放副本；不会上传本地数据。构建会编译启动器、安装仓库内的 CodexPage 适配源码、导入壁纸，并执行入口 `--check`。

构建后运行安装目录内的 `Launch.exe` 和 `CodexPage\CodexSkinManager.exe`。已有安装目录不会被覆盖。

`.local/` 保存本地复建输入、下载运行时和播放副本，**不会提交到公开仓库**。运行中的配置、会话和日志保留在安装目录。

## 隔离与回退

旧版安装包保留在桌面的 **待隔离区**，不会自行删除。该区还保存旧桌面入口、旧计划任务快照和恢复清单。使用者可在确认 3号稳定后，自行决定是否删除旧版。

需要回退时运行同目录的 `隔离与恢复.ps1`，选择 **Restore**。恢复前应关闭旧版 CodexPage 管理器与旧 Codex 窗口，避免文件被占用。脚本会把旧目录、旧快捷方式和旧监控任务放回原位置；3号本身不会被删除。

## 维护交接

1. 保留原版 R16 作为回退，不删除启动素材与完整性校验。
2. 页面透明化只针对已经实测的首页和聊天页面；不得把弹窗、正文文字、输入框或可点击控件一并隐藏。
3. 输入框使用新版 Codex 原生圆角及填色，旧结构才使用兼容底色。
4. 新旧 Codex 的 DOM 和 CSS 类名变化可能使页面识别或透明规则失效；Codex 更新后先检查主表面、侧栏与聊天底板，再修改适配。
5. 只读检查时不得重载正在观看的壁纸；样式重载后验证持续显示，不能只看一瞬间的截图。
6. 冷启动测试必须从当前 Windows 会话没有 Codex 进程的状态开始，并分别记录转场成功、动画跳过、壁纸播放和回退结果。

## 发布范围与许可

- 本项目公开的是整合逻辑、适配代码、使用说明与构建方式。
- CodexPage 的代码采用 MIT 许可证，发布相关代码时保留许可证与署名。Node.js、图标等第三方素材继续遵循其各自的许可证与声明。
- R16 的发布说明仍明确提到上游代码与媒体的再分发条款待确认。在获得相应许可前，公开仓库不直接上传其启动视频、龙娘壁纸或完整 R16 包。公开版采用使用者从上游取得输入后本地构建的方式，或在得到授权后提供官方输入来源。
- 不将本机 Codex 会话、浏览器配置、日志、凭据或旧版浏览器配置目录放入公开仓库。隔离区仅供本机回退。
