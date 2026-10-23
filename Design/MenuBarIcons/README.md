# 菜单栏图标方案

提供 7 款无蒸汽方案，每款都有实心（运行）与空心（关闭）两个状态。`comparison.png` 为对比图，包含放大轮廓、25 × 18 实际尺寸与浅色背景对比。

| 编号 | 文件前缀 | 方向 |
| --- | --- | --- |
| 01 | `01-classic-no-steam` | 经典宽杯与杯碟，延续当前图标 |
| 02 | `02-rounded-mug` | 圆角马克杯，杯身饱满、无杯碟 |
| 03 | `03-wide-latte` | 矮胖拿铁杯，宽口与低重心 |
| 04 | `04-espresso` | 直壁意式杯，更规整的系统符号感 |
| 05 | `05-takeaway` | 外带纸杯，杯盖与纵向收口 |
| 06 | `06-moka-pot` | 小摩卡壶，棱角壶身与侧把手 |
| 07 | `07-native-system-cup` | 原生咖啡杯：椭圆杯口、圆润杯身、完整杯碟 |

- `*-filled.svg` / `*-outline.svg`：01—06 的可编辑矢量，25 × 18 的 viewBox，使用 `currentColor` 着色。
- 07 直接使用原生咖啡杯 SF Symbols `cup.and.saucer.fill` / `cup.and.saucer`，提供原生渲染 PNG；接入时调用系统符号，不提供近似 SVG。
- `07-native-preview.png`：原生咖啡杯图标的蓝色放大与实际尺寸预览。
- `*@2x.png`：50 × 36，透明背景，供 Retina 菜单栏预览。
- `*@8x.png`：200 × 144，透明背景，供放大查看。
- `render.swift`：SVG 与 PNG 共用的路径定义和原生 AppKit 渲染脚本。

从仓库根目录重新生成：

```bash
env DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcrun swift "Design/MenuBarIcons/render.swift"
```

7 款方案已接入应用的「总览 → 菜单栏图标」。应用使用原生 AppKit 绘制，代码位于 `Sources/Lidwake/MenuBarIconStyle.swift`；此目录保留设计阶段的对比图与导出素材。
