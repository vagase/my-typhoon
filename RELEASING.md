# 发布新版本

GitHub Actions 会在推送版本标签后自动构建应用并创建 GitHub Release。

## 版本规则

- 正式版：`v主版本.次版本.修订号`，例如 `v1.3.0`；
- 预发布版：在正式版本后添加后缀，例如 `v1.3.0-beta.1`；
- 正式版会更新 GitHub 的 Latest Release，预发布版不会替换 README 的最新版下载入口。

## 发布步骤

发布前确保目标提交已经进入 `main`，并完成本地构建：

```bash
git switch main
git pull --ff-only
./build_app.sh
```

确认无误后创建并推送标签：

```bash
git tag -a v1.3.0 -m "TyphoonBar v1.3.0"
git push origin v1.3.0
```

工作流会自动：

1. 从标签解析版本号并写入应用包；
2. 使用 Swift Release 配置构建应用；
3. 对应用进行临时签名并验证签名；
4. 生成 `TyphoonBar-macOS.zip` 和 SHA-256 校验文件；
5. 根据相邻标签自动生成发布说明并创建 GitHub Release。

## 发布限制

当前产物使用临时签名，没有 Apple Developer ID 签名和公证。用户首次运行时可能需要在 Finder 中右键选择“打开”。面向 App Store 或提供无警告的站外分发前，仍需配置开发者证书、公证和相应的 GitHub Secrets。
