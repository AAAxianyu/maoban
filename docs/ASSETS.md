# 正式像素素材与来源

视觉基准 `docs/assets/pixel-cat-study-room.png` 来自用户选定的第 4 张生成图，完整原件保留，仅作风格参考。

| 文件 | 来源与用途 | 处理 |
| --- | --- | --- |
| apps/mobile/assets/room-background.png | 2026-10-08，内置 imagegen；参考原图生成独立自习室 | 无文字/UI，单独背景层，未裁切 |
| apps/mobile/assets/cats-atlas.png | 2026-10-08，内置 imagegen；两猫透明 4×2 图集 | 保留 alpha，Flutter 按单元格绘制，未修改源图 |

生成物已复制到项目；原输出保留于 Codex generated_images。使用条件遵循当前图像生成服务条款，不额外宣称版权独占。正文和控件由 Flutter 独立渲染。

生成提示要点：房间为 3:2 宽幅、鼠尾草墙、夜窗月亮、暖木桌、词汇书和电脑，中间留独立猫空间，不含猫/文字/数字/UI；猫图集为透明 4 列×2 行，橘白与灰白两行，四列依次睁眼、眨眼、单爪、双爪，统一基线和像素轮廓。内置工具原始输出分别为 exec-b4d084fc-e59c-4c36-9755-373d17b2824a.png 和 exec-53848225-b1e4-4113-b46c-10012e3ad123.png。

功能图标由 `lib/core/pixel_glyph.dart` 的 8×8 格式绘制，包含今日、小屋、奖励、成长、词汇、C、阅读、运动、小鱼干和爪印；它们属于项目原生代码。四件独立装饰依实际 10/30/60/100 永久经验解锁；亮灯由台灯装饰表示。素材合成已通过 Android 模拟器截图检查，iOS 与实际手机仍待验收。

2026-10-08：新增 `apps/mobile/assets/decorations-badges.png`（透明 3×3 atlas），由 ImageGen 生成，原件 `exec-618edda7-9c5a-4a20-aae7-eacbff3127e8.png` 保留。九个独立格依次为台灯、猫窝、植物、书架、首次爪印、七天月历、C 花括号、双猫同日、三本书。提示要求奶油/可可/珊瑚/鼠尾草色、九宫格透明间隔、像素风、无文字/界面；客户端以 `drawImageRect` 分格渲染，配独立中文标签。装饰叠加到小屋，徽章按真实解锁显示。

2026-10-08：新增 `apps/mobile/assets/app-icon.png`，ImageGen 输出 `exec-dfbe377a-e63d-4ff8-82a7-557cc1610fc2.png`，奶油背景上的橘猫、灰猫与珊瑚色爱心，无文字。原件保留。`flutter_launcher_icons` 0.14.4 按 `flutter_launcher_icons.yaml` 生成 Android/iOS 所需尺寸与 Android adaptive icon；Android/iOS 启动画面使用同一图像和奶油表面。Android 原生构建通过，iOS 打包未验证。

2026-10-09：为减小安装包与解码内存，三张运行时素材做了 256 色调色板量化（无抖动）：`room-background.png` 保持 1536×1024（1.69 MB → 0.41 MB）；`cats-atlas.png` 缩至 1332×666（1.11 MB → 0.22 MB）；`decorations-badges.png` 缩至 942×942（1.43 MB → 0.23 MB）。新尺寸都能被图集网格整除（4×2、3×3），分格绘制逻辑不变。未处理原件保存在本机 `.tools/asset-originals/`（不提交）。
