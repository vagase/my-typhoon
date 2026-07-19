# 首次打开 TyphoonBar

TyphoonBar 当前是免费开源项目，GitHub Release 使用临时签名，尚未购买 Apple Developer Program，也没有经过 Apple 公证。因此，从浏览器下载后首次打开时，macOS 可能显示“Apple 无法验证 TyphoonBar.app 是否包含可能危害 Mac 或泄露隐私的恶意软件”。

如果你从本项目的 [GitHub Releases](https://github.com/vagase/typhoonbar/releases) 下载，并确认校验值无误，可以使用 Apple 提供的单个应用放行方式：

1. 在警告窗口点击“完成”，不要点击“移到废纸篓”；
2. 打开“系统设置”→“隐私与安全性”；
3. 向下滚动到“安全性”，找到 TyphoonBar 被阻止的提示；
4. 点击“仍要打开 / Open Anyway”；
5. 使用 Touch ID 或登录密码确认，再点击“打开”。

“仍要打开”通常只会在你尝试启动应用后的一段时间内显示。放行后，macOS 会为这个应用保存例外，之后可正常双击打开。

## 安全提示

- 只从本仓库的 GitHub Releases 下载；
- 可使用 Release 同时提供的 `TyphoonBar-macOS.zip.sha256` 核对文件；
- 不要全局关闭 Gatekeeper；
- 不要运行来源不明的 `xattr`、`spctl` 或 `sudo` 命令；
- 如果你不信任应用来源，请删除应用，不要绕过系统警告。

Apple 官方说明：[安全地打开 Mac 上的 App](https://support.apple.com/zh-cn/102445)。
