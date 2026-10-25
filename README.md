# LumiPluginPluginManager

Lumi 插件管理器插件的**共享远程包**，供 Lumi / Cisum / GameFactory / GitOK / Kuzee / Wakey
等 CofficLab 兄弟应用共同消费。

> **重要规则：本插件包不能依赖其他插件包，也不能被其他插件包依赖。**
>
> 插件之间只通过 Provider 契约通信：共享能力放入 `Provider*` / `Kit*` 包，
> 由宿主（`Factory*`）统一装配；跨插件互相引用会破坏插件的独立装配与卸载。

## Package

- Manifest 包名：`LumiPluginPluginManager`（与仓库名一致，符合远程插件包命名规范）
- Product / Target：`PluginPluginManager`（不带 `Lumi` 前缀）
- Platform: macOS 14+ / iOS 17+
- Swift tools: 6.0

## 命名规范

CofficLab 的远程插件包统一遵循：

| 仓库名 | manifest `name:` | product / target |
| --- | --- | --- |
| `LumiPluginPluginManager` | `LumiPluginPluginManager` | `PluginPluginManager` |
| `LumiPluginActivityBar` | `LumiPluginActivityBar` | `PluginActivityBar` |
| `LumiPluginToast` | `LumiPluginToast` | `PluginToast` |

理由：Xcode 的包依赖列表显示的是上游 manifest 里的 `Package(name:)`，不是仓库名。
manifest 包名不带 `Lumi` 前缀会让用户在 Xcode 里看不到前缀。仓库名保持与包名一致，
消费方 `.product(name:package:)` 的 `package:` 参数按 URL basename 匹配，必须写仓库名。

## 提供什么

- 插件管理入口：浏览插件列表、启用 / 禁用单个插件、跳转到插件设置详情
- 插件 About / 手册页面贡献（通过 `ProviderDocsView`）
- 「浏览插件」快捷建议注册（通过 `ProviderPromptSuggestion`）

## 依赖与集成

```swift
dependencies: [
    .package(url: "https://github.com/CofficLab/LumiPluginPluginManager.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "PluginPluginManager", package: "LumiPluginPluginManager"),
        ],
    ),
]
```

注意 `package:` 必须是仓库名 `LumiPluginPluginManager`，不是 product 名。

## 品牌化：注入自己的插件 id

宿主应用可以用自己的品牌 id 复用本包（与 `PluginSettingView` / `PluginStorage` /
`PluginToast` 的做法一致）。不传参时使用默认的 `com.coffic.lumi.plugin.plugin-manager`。

```swift
PluginPluginManager(id: "com.coffic.wakey.plugin.plugin-manager")
```

注入后以下三处同步跟随：

| 位置 | 取值 |
| --- | --- |
| `PluginPluginManager.id` | 注入的 id |
| `PluginPluginManager.metadata.id` | 注入的 id |
| 日志 subsystem（`Logger`） | 注入的 id |

设置入口 id 恒为 `"plugin-manager"`（与品牌无关，供设置深链使用）；
提示建议 id 为 `"\(id).browse"`。

> 更换 id 会同时更换插件的启用状态存储键：宿主切换 id 前需确认历史状态是否需要迁移。

## Testing

From this package directory:

```sh
swift test
```

## 能力边界

`PluginManagementViewModel` 原先直接持有 `any DocsViewProviding`，现改为只依赖
`PluginManagerDocsCapability`（`aboutEntry(for:)`），由
`PluginManagerDocsCapabilityAdapter` 收窄内核的 `DocsViewProviding`。

注册 / 移除 About 条目仍由插件入口负责（它们属于组装层职责），不需要进入窄协议。
