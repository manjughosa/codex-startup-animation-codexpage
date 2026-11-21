# 上游来源与本地适配

本机整合包：3号插件。

## 1号：启动动画与窗口交接

- 原项目：mytjxs/codex-startup-animation
  - https://github.com/mytjxs/codex-startup-animation
- R16 发布与定制打包：HanwenZhang-George
  - https://github.com/HanwenZhang-George/codex-startup-animation/releases/tag/community-v34-r5
- 本机使用：R16 开屏、等待 Codex 窗口就绪、落泪转场。
- 本机改动：关闭原壁纸宿主，将冷启动委托给包内 CodexPage；精简外层入口对旧壁纸宿主及旧壁纸文件的依赖。
- 分发边界：R16 的 `SOURCE-PROVENANCE.txt` 明确说明上游代码许可证与分发条款尚待确认，不能据 MIT 许可推定其代码、视频或图像可公开再分发。

## 2号：壁纸库与视频注入

- CodexPage 3.8.0：JiPaiFan1109/CodexPage
  - https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.8.0
- 上游引擎：Fei-Away/Codex-Dream-Skin v1.5.18
  - https://github.com/Fei-Away/Codex-Dream-Skin
- 本机使用：壁纸库、视频服务、页面注入与 Codex Store 身份验证。
- 本机改动：允许新版 Codex 缺失的装饰性 `header-tint` 锚点；首页和聊天页底板透明；新版输入框保留原生圆角填色。
- 代码许可：MIT，详见 `.local/CodexPage/LICENSE` 和 `.local/CodexPage/THIRD_PARTY_NOTICES.md`。

## 3号：本地整合

R16 负责开屏与交接；CodexPage 负责壁纸；龙娘素材沿用 R16 的两段原片，播放副本为 1080p/60fps 与 1080p/48fps。原片保留在旧版归档内，不参与公开发布。

这是整合与适配，不是 OpenAI 官方产品，也不宣称对所有未来 Codex 版本免维护。
