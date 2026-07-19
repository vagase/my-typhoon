# 第三方声明

TyphoonBar 的 Apache-2.0 许可证仅适用于本仓库中的项目代码、文档和原创项目资源，不自动授予任何第三方数据、地图内容、服务名称、Logo 或商标的使用权。

## 中国气象局中央气象台

应用目前在运行时读取中央气象台台风网公开页面所使用的数据接口，用于展示台风名称、编号、状态、实况路径、预报路径、中心强度和风圈。

- 来源：[中央气象台台风网](https://typhoon.nmc.cn/)
- 网站声明：[中央气象台网站声明](https://www.nmc.cn/publish/cms/view/722665831f0a4e98800c41e691444963.html)
- 权利主体：国家气象中心/中央气象台

这些数据不包含在本项目的 Apache-2.0 授权中。本项目尚未通过本仓库向使用者授予中央气象台数据的下载、再发布、商业利用或衍生利用权。分发者应自行确认其使用场景符合中央气象台条款，并在需要时取得书面授权。

应用对原始路径数据进行了筛选、排序、距离计算和可视化。此类结果属于 TyphoonBar 的计算展示，不应被理解为中央气象台制作或认可的产品。

## Open-Meteo

应用在运行时调用 Open-Meteo Forecast API，获取模式风场及用户所在地的逐小时降水、持续风和阵风数据。

- 服务：[Open-Meteo](https://open-meteo.com/)
- 数据许可证：[CC BY 4.0](https://open-meteo.com/en/license)
- API 条款：[Open-Meteo Terms](https://open-meteo.com/en/terms)
- 定价与商业使用：[Open-Meteo Pricing](https://open-meteo.com/en/pricing)

Open-Meteo API 返回的数据要求署名，并且免费 API 的适用范围受其当前服务条款约束。应用分发者有责任根据实际用途选择合适的 API 方案并保留所需署名。本项目仅调用远程 API，没有复制或链接 Open-Meteo 的 AGPL 服务端代码。

## Apple MapKit、Core Location 与 SF Symbols

应用使用 macOS 系统提供的 MapKit、Core Location、CLGeocoder 和 SF Symbols。相关框架、地图内容、符号及服务仍受 Apple 的协议和指南约束。

- [Apple Developer Agreements](https://developer.apple.com/support/terms/)
- [MapKit](https://developer.apple.com/documentation/mapkit)
- [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)

地图中的 Apple 或其数据合作方署名不得被移除、遮挡或修改。SF Symbols 仅用于应用界面，不应被重新用作应用图标、Logo 或商标。

## 商标

Apple、MapKit、SF Symbols、Open-Meteo、中国气象局、中央气象台以及其他名称和标识均可能是其各自权利人的商标。本项目对这些名称的使用仅用于说明数据或技术来源，不表示相关机构对 TyphoonBar 的认可、赞助或背书。
