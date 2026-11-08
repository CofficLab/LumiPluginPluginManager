# LumiPluginPluginManager

📖 English | [中文版](README_zh.md)

Shared **remote package** for the Lumi plugin manager plugin, consumed by CofficLab sibling apps such as Lumi / Cisum / GameFactory / GitOK / Kuzee / Wakey.

> **Important rule: this plugin package must not depend on other plugin packages, and must not be depended on by other plugin packages.**
>
> Plugins communicate only through Provider contracts: shared capabilities go into `Provider*` / `Kit*` packages, assembled uniformly by the host (`Factory*`); cross-plugin references break independent plugin assembly and uninstallation.

## Package

- Manifest package name: `LumiPluginPluginManager` (matches the repository name, per the remote plugin package naming convention)
- Product / Target: `PluginPluginManager` (without the `Lumi` prefix)
- Platform: macOS 14+ / iOS 17+
- Swift tools: 6.0

## Naming Convention

CofficLab remote plugin packages follow this convention uniformly:

| Repository | manifest `name:` | product / target |
| --- | --- | --- |
| `LumiPluginPluginManager` | `LumiPluginPluginManager` | `PluginPluginManager` |
| `LumiPluginActivityBar` | `LumiPluginActivityBar` | `PluginActivityBar` |
| `LumiPluginToast` | `LumiPluginToast` | `PluginToast` |

Why: Xcode's package dependency list shows the upstream manifest's `Package(name:)`, not the repository name. Without the `Lumi` prefix in the manifest package name, users would not see the prefix in Xcode. The repository name stays consistent with the package name, and the consumer's `.product(name:package:)` `package:` argument matches the URL basename, so it must be the repository name.

## What It Provides

- Plugin management entry: browse the plugin list, enable/disable individual plugins, jump to plugin settings details
- Plugin About / manual page contribution (via `ProviderDocsView`)
- "Browse plugins" prompt suggestion registration (via `ProviderPromptSuggestion`)

## Enable/Disable Failure Feedback

When enabling/disabling a plugin fails, the page shows the failure reason via `AppErrorBanner`, instead of leaving the toggle silently in a position inconsistent with reality.

The failure reason comes from the underlying `PluginControlling.lastErrorDescription` (surfaced through `PluginManagementCapability`) and is cleared on the next success.

## Responsive Layout

| Width | Layout |
| --- | --- |
| Regular (macOS / iPad) | Edge-to-edge split view with the plugin list on the left and the detail panel on the right |
| Compact (iPhone) | Plugin list, tapping pushes the detail panel via `NavigationLink` |

The split form is the baseline for the settings page (list column 300, detail column padding 22, edge-to-edge with no outer border); the compact form only changes the container arrangement — list rows and the detail panel itself stay the same.

## Dependencies and Integration

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

Note that `package:` must be the repository name `LumiPluginPluginManager`, not the product name.

## Branding: Inject Your Own Plugin ID

Host apps can reuse this package with their own brand ID (consistent with the `PluginSettingView` / `PluginStorage` / `PluginToast` approach). When not passed, the default `com.coffic.lumi.plugin.plugin-manager` is used.

```swift
PluginPluginManager(id: "com.coffic.wakey.plugin.plugin-manager")
```

After injection, the following three places follow along:

| Location | Value |
| --- | --- |
| `PluginPluginManager.id` | Injected ID |
| `PluginPluginManager.metadata.id` | Injected ID |
| Log subsystem (`Logger`) | Injected ID |

The settings entry ID is always `"plugin-manager"` (brand-independent, for settings deep links); the prompt suggestion ID is `"\(id).browse"`.

> Changing the ID also changes the plugin's enabled-state storage key: before switching IDs, hosts should confirm whether historical state needs migration.

## Entry Visibility: Hide the Entry When No Configurable Plugins Exist

The plugin management page only lists **user-configurable** plugins (`PluginEnablePolicy.isConfigurable`, i.e. `enabledByDefault` / `disabledByDefault`).

If a host's plugin policies are all `required` / `alwaysOn` (`isConfigurable` is false), this page is necessarily a permanently empty list — such an entry is meaningless to users and instead makes them think the feature is broken.

**The default behavior is to hide**: hosts get the correct result with zero configuration, without writing any arguments in the Factory. When the host later adds configurable plugins, the entry appears automatically.

| Policy | Behavior |
| --- | --- |
| `.onlyWhenConfigurablePluginsExist` (default) | Register the entry only when the host has user-configurable plugins |
| `.always` | Always register the "Plugin Manager" entry |

Most hosts need not pass any value explicitly:

```swift
PluginPluginManager()   // zero configuration: hide the entry when no configurable plugins
```

Only override explicitly when the host knowingly has no configurable plugins but still wants to keep this entry:

```swift
PluginPluginManager(entryVisibility: .always)
```

> The decision happens at the `onReady` stage (not `onBoot`): `KernelCoreContainer.start` registers all plugins first, then executes `onBoot` one by one; during `onBoot`, plugins with a larger `order` are not yet registered, so judging then would miss plugins.

The "Browse plugins" prompt suggestion follows the entry: when the entry does not exist, the suggestion is not registered either — its action is `openSettingsTab("plugin-manager")`, and once the entry is withdrawn this deep link is a dead end.

> Entry visibility is decided once at startup. The current plugin catalog is fixed at compile time (`unloadPlugin` / `reloadPlugin` are not called in production code), so the runtime plugin list effectively never changes; there is no need to listen for plugin list change events.

## Testing

From this package directory:

```sh
swift test
```

## Capability Boundary

`PluginManagementViewModel` previously held `any DocsViewProviding` directly; it now depends only on `PluginManagerDocsCapability` (`aboutEntry(for:)`), with `PluginManagerDocsCapabilityAdapter` narrowing the kernel's `DocsViewProviding`.

Registering/removing About entries remains the responsibility of the plugin entry (they belong to the assembly layer) and does not need to enter the narrow protocol.
