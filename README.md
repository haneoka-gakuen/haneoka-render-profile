# Haneoka render profile

`haneoka_render_profile` 提供纯 Dart 的源数据模型、动画曲线、粒子积分、投影、材质描述和通用绘制契约适配。Vega 和 Cassiopeia 的游戏插件在这里共享原作表现规则。

`flutter/` 是可选的 `haneoka_render_profile_flutter` 包，负责 Flutter 的资源声明、Shader bundle 和资源地址。应用组合层导入它，并把资源交给加载器。纯计算包和游戏插件使用相对资源标识。

```mermaid
flowchart TD
    App[应用组合层] --> Vega[Vega Flutter renderer]
    App --> Cass[Cassiopeia Flutter renderer]
    Vega --> Kernel[Flutter GPU kernel]
    Cass --> Kernel
    Kernel --> Contracts[Render contracts]
    App --> Assets[Profile Flutter assets]
    App --> GameVega[Vega Haneoka plugin]
    App --> GameCass[Cassiopeia Our Notes plugin]
    GameVega --> Profile[纯 Dart profile]
    GameCass --> Profile
    Profile --> Contracts
```

两个 renderer 接收通用场景和资源契约。游戏规则、资源选择与原作动画行为由游戏插件及 profile 提供；Flutter 的窗口、文件、音频和资源定位由宿主组合。

独立检查纯 Dart 部分：

```sh
dart pub get
dart analyze lib
```

公共绘制合同固定到 `render-kernel-flutter` 的 Git 版本；本地联调可使用各包自己的 `pubspec_overrides.yaml`。根目录的 `assets`、`shaders` 是通向 `flutter/` 的兼容链接，现有资源生产器继续写入同一份文件。

正式故事字体与精灵使用已校验的 descriptor、对象档案和输出文件更新：

```sh
node tool/export-story-assets.mjs --inputs tool/story-assets-v56.json --profile flutter/assets/profile
```

工具沿用正式字体 compact 格式，核验输入 SHA256，记录每份资产的服务器、资源版本和原始输出；布局和动画保持原有来源。生产工具使用 Node.js 24+。
