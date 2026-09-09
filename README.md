# 百灵桌面视觉助手 · macOS MVP

Swift + SwiftUI 原生菜单栏应用。按 **⌘⇧A** 框选屏幕，在浮窗输入问题，由百灵 `Ling-3.0-flash-VL` 看图回答。也支持只发文字，或截图后留空问题直接发送。第一版使用普通请求，不流式输出，不保留聊天历史。

## 运行

本项目要求 macOS 14 或更新系统。源码仓库不包含编译产物，首次双击 `run.command` 会先编译再启动；已有本机构建时会直接启动。

1. 在 Finder 中打开 `dist/LingDesktop.app`，或双击 `run.command`。
2. 首次打开会显示设置：Base URL 默认 `https://maas-api.antdigital.com/v1`，模型默认 `Ling-3.0-flash-VL`。填入该接入平台的 API Key，点「测试连接」，成功后「保存」。测试连接会产生一次真实 API 请求，可能计费。已有配置会保留；从旧版升级时，请在设置中更新地址。
3. 按 **⌘⇧A**，第一次使用需在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」允许「百灵视觉助手」，随后退出并重新打开。旧版系统可能显示「屏幕录制」。应用不会替你开启权限。
4. 拖动鼠标框选一个不含敏感信息的区域，输入“解释一下这里”，点「发送」或按 **⌘Return**。**Esc** 取消框选。
5. 菜单栏的取景器图标可打开提问、设置或退出。关闭浮窗不会退出应用；发送中可取消请求。

已构建的 app 是本机临时签名版本，没有开发者公证，不是安装器。无需把 API Key 发到聊天里；请直接填写在应用的安全输入框中。若快捷键与其他应用冲突，可用菜单栏「截图提问」。

当前默认接入蚂蚁数科 MaaS，最终请求为 `https://maas-api.antdigital.com/v1/chat/completions`。设置也接受这个完整地址，不会重复拼接路径。若使用 Ling Studio，请按该控制台的文档填写 `https://api.ant-ling.com/v1`，并使用对应平台的 Key 和可用模型 ID。

## 编译与检查

只依赖 macOS SDK，没有外部 Swift 包。需要 Apple Command Line Tools 或 Xcode。

```sh
bash build.sh
bash check.sh
```

`check.sh` 可在仅有 Command Line Tools、没有 XCTest 的环境运行。它使用 URLProtocol 本地模拟 HTTP，检查实际客户端的请求格式与响应处理；**通过这些检查不等于真实模型调用成功**。

## 隐私边界

- 只在按下「发送」时，将当前问题和所选截图发到设置中的 API 地址。修改 Base URL 前请确认接收方可信；「测试连接」发送少量文本，不发截图。
- API Key 存在本机 macOS 钥匙串，不写入源码或 UserDefaults；Base URL 和模型名保存在本机偏好设置。
- 原生框选产生的临时图片保存在仅当前用户可访问的临时目录，读取后立即清理。内存中保留当前截图，直到移除、替换或退出。
- 请求使用无磁盘缓存的临时 URLSession，拒绝 HTTP 重定向，非本机地址要求 HTTPS。错误保留 HTTP 状态码及服务端信息，回显的完整 Key 会脱敏。
- 超大截图按比例缩小，长边不超过 2400 像素。请避免选择密码、密钥或其他不应上传的信息。

## 实现与接口依据

`Sources/LingDesktop`：菜单栏、Carbon 全局快捷键、原生 `screencapture` 交互框选、SwiftUI 浮窗、钥匙串设置。

`Sources/LingCore`：仅百灵客户端，POST `/v1/chat/completions`，Bearer 鉴权；图片用 PNG Base64 `image_url`，与文字放在同一条 user message；读取 `choices[0].message.content`。

消息结构依据 Ling Studio 的[官方多模态文档](https://developer.ant-ling.com/en/docs/tutorials/multimodal-understanding/)和[官方快速开始](https://developer.ant-ling.com/en/docs/getting-started/quickstart/)，核实于 2026-09-09。MaaS 默认地址按项目使用者提供的接入地址配置；模型可用性及账户权限以对应控制台和真实请求结果为准。

详细验证状态见 `TESTING.md`。
