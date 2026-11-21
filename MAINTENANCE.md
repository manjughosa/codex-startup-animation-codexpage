# 维护交接：3号插件

## 本机入口与位置

- 桌面启动：`3号插件.lnk`。
- 桌面壁纸管理：`3号插件 - 壁纸管理器.lnk`。
- 安装目录：`%LOCALAPPDATA%\Programs\3号插件`。
- 源码项目：本仓库根目录。
- 旧版归档：桌面 `待隔离区`。其中保留原版 R16 的原片、旧组合副本与旧 CodexPage 副本。

## 已完成的实机验收

- Codex 26.1117.3838.0 上，3号从冷启动完成开屏转场并播放龙娘视频。
- 临时屏蔽 1号与 2号启动入口后，3号仍独立启动、完成转场并通过壁纸播放校验。
- 首页与已有聊天的底板透明；输入框原生 22px 圆角保留。
- 本地复建脚本已在新目录生成完整副本并通过入口 `--check`。
- 旧插件恢复脚本已执行恢复，旧监控任务也已重新注册并读取验证。当前旧插件重新保持隔离。

## 适配点

1. R16 `wallpaperEnabled=false`，关闭旧壁纸宿主。`src/DragonLauncher.cs` 调用包内 `CodexPage\engine\launcher\CodexDynamicSkinLauncher.exe`。
2. `packaging/PortableLaunch.cs` 保留官方 Store 身份与路径校验，但不再生成旧壁纸宿主配置。
3. `Build.ps1` 只编译 `Start-Codex-Dragon.exe` 与 `Launch.exe`，动画清单仍校验所需素材。
4. CodexPage `selectors.json` 与嵌入的 `renderer-inject.js` 同步，将 `header-tint` 改为可选装饰。
5. `earth-background.css` 按活动页面透明化底板。已实测的页面标识：`home`、`chatgpt-thread`、`local-thread`。
6. 新版输入框存在 `[data-composer-body]` 时保留原生填色与圆角，不在其外层再铺矩形底色。

## 维护规则

- 先读原始错误与实测日志，不要按 DOM 类名印象修改。
- Codex 每次更新后检查页面结构与 CSS 类名变化；背景失效不等于启动器过期。至少检查 `home`、`chatgpt-thread`、`local-thread`、侧栏、输入框和底板；活动页面可能不再与底板保持原来的直接父子层级。
- 更新后出现“已有聊天遮住壁纸”时，先检查 `[data-app-shell-workspace]` 内是否存在活动的聊天标识，再定位 `> [data-app-shell-surface-backing]`，而不是盲目新增全局透明规则。保留回归夹具中活动页面与底板分离的结构。
- 样式更新后连续读取两次透明底板与视频帧，确认播放推进且规则没有回退。源码、安装目录和待提交副本必须一致；本地日志、R16 原媒体、浏览器配置及输入缓存只保留在忽略目录。
- 不复制旧 CodexPage 的 `cdp-profile`、日志、会话或凭据到公开仓库。
- 不用删旧版文件的方式“简化”安装。旧版作为回退保留，由使用者决定何时删除。
- 测试旧版隔离/恢复前先保存清单，恢复脚本要能处理任务重复注册、文件占用和失败回滚。
- 样式重载后不要额外切走用户正在看的窗口。验证需覆盖持续播放，而非只看瞬时截图。

## 未覆盖与发布限制

- 只有本机 Windows 会话与当前 Codex 版本的实测，不等于所有硬件、DPI、多屏、GPU 和未来 Codex 版本都兼容。
- R16 的代码、动画和壁纸再分发许可未确认；公开仓库先不放完整媒体或旧版浏览器配置。
- CodexPage 的 MIT 许可证与第三方声明需随相关代码保留。
