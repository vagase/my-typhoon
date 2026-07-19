# 参与贡献

感谢你帮助改进 TyphoonBar。

## 开始之前

- 搜索现有 Issue，避免重复工作；
- 较大的功能或数据源变更建议先创建 Issue 讨论；
- 不要提交无权公开的气象数据、地图素材、Logo、字体、密钥或个人信息；
- 新增或替换图标、图片等资源时，应在 `ASSETS.md` 记录来源和许可证；
- 新增数据源时必须同时说明许可证、署名要求、请求限制和隐私影响。

## 本地构建

需要 macOS 14 或更高版本以及 Xcode Command Line Tools：

```bash
swift build
./build_app.sh
open dist/TyphoonBar.app
```

构建目录 `.build/` 和打包目录 `dist/` 不应提交。

## 提交要求

1. 保持改动聚焦，并使用清晰的提交信息；
2. 确保 `swift build` 和 `./build_app.sh` 通过；
3. 运行 `git diff --check`；
4. UI 改动应说明 macOS 版本并附截图；
5. 算法或风险阈值改动应同步更新 `DATA_SOURCES.md`；
6. 定位、网络请求或第三方共享发生变化时应同步更新 `PRIVACY.md`；
7. 不应把派生结果描述成官方预报或预警。

项目目前没有自动化测试 target。新增可独立验证的解析或计算逻辑时，欢迎同时建立相应测试。

## 贡献许可

除非明确标记为“Not a Contribution”，向本项目提交的贡献将按 Apache License 2.0 授权，具体以 [LICENSE](LICENSE) 第 5 节为准。提交者必须拥有所贡献代码和资源的必要权利。
