---
name: 喵伴 · 移动端当前设计系统
description: 两只像素猫在温暖书桌前陪伴学习，真实中文操作与纪念成长独立渲染。
colors:
  coral: "#D56B57"
  coral-ink: "#963E30"
  sage: "#56744B"
  sage-container: "#DAE3CB"
  cream: "#F6EBD8"
  paper: "#FFF9ED"
  ink: "#392A25"
  secondary-ink: "#6B584D"
  button-ink: "#241711"
  line: "#DFCCB3"
  peach-indicator: "#F2C4AE"
  connection-banner: "#F2D9C2"
  error: "#9D3026"
  white: "#FFFFFF"
typography:
  headline:
    fontSize: "28px"
    fontWeight: 700
  title-large:
    fontSize: "22px"
    fontWeight: 700
  title-medium:
    fontSize: "18px"
    fontWeight: 600
  body-large:
    fontSize: "16px"
    lineHeight: 1.5
  body-medium:
    fontSize: "14px"
    lineHeight: 1.5
  label-large:
    fontSize: "16px"
    fontWeight: 600
rounded:
  calendar: "8px"
  field-action: "12px"
  paper-scene: "16px"
spacing:
  detail: "4px"
  compact: "8px"
  item: "12px"
  content: "16px"
  section: "24px"
components:
  button-primary:
    backgroundColor: "{colors.coral}"
    textColor: "{colors.button-ink}"
    typography: "{typography.label-large}"
    rounded: "{rounded.field-action}"
  button-outlined:
    textColor: "{colors.ink}"
    typography: "{typography.label-large}"
  button-text:
    textColor: "{colors.coral-ink}"
    typography: "{typography.label-large}"
  paper:
    backgroundColor: "{colors.paper}"
    rounded: "{rounded.paper-scene}"
    padding: "{spacing.content}"
  text-field:
    backgroundColor: "{colors.paper}"
    rounded: "{rounded.field-action}"
  navigation:
    backgroundColor: "{colors.paper}"
  navigation-active:
    backgroundColor: "{colors.peach-indicator}"
    textColor: "{colors.ink}"
  selection-active:
    backgroundColor: "{colors.sage-container}"
    textColor: "{colors.ink}"
  calendar-effective:
    backgroundColor: "{colors.sage}"
    textColor: "{colors.white}"
    rounded: "{rounded.calendar}"
---

# Design System: 喵伴移动端

## Overview

**Creative North Star: "两只小猫，一起在温暖书桌前学习"**

这是已实现的 Flutter 手机界面记录。温暖木桌、书本、台灯、植物与月夜窗景形成共同小屋，两只奶油橘猫与灰白猫保持不同毛色。像素插画承担陪伴与纪念，中文标题、说明、表单、任务勾选和导航由原生控件独立绘制。

界面延续用户已定的奶油、深棕、珊瑚与鼠尾草绿世界。Material 3 的表单和导航承载真实操作；视觉密度随手机高度调整，以待完成约定的标题与操作优先。此处记录实际结果，不重新选择风格，也不把概念图中的日期、余额或等级作为产品数据。

本文件与 [MOBILE_DESIGN.design.json](MOBILE_DESIGN.design.json) 是移动端交接记录。根目录 [DESIGN.md](../DESIGN.md) 仍是用户确认的功能与视觉合同，[DEVELOPMENT.md](../DEVELOPMENT.md) 与 [GOAL.md](../GOAL.md) 保持原样；本记录不能替代或扩张其验收结论。品牌与功能权威保持为根 DESIGN.md；已有 [PRODUCT.md](../PRODUCT.md) 作为产品摘要，另有[实施契约](verification/visual-contract.md) 与[选定原图](assets/pixel-cat-study-room.png)。前言令牌从 apps/mobile/lib/app/theme.dart 及已使用的控件抽取，源代码是当前实现的事实依据；这里的 px 对应 Flutter 字体缩放前的 nominal logical px，不是设备物理像素。

**Key Characteristics:**

- 分层像素房间、独立两猫与解锁纪念，文字和触区保持原生。
- 奶油页面、浅纸内容、深棕正文、珊瑚操作、鼠尾草绿完成。
- 四入口：今日、小屋、奖励、成长；通知与设置在顶部。
- 普通约定直接勾选，离线状态和服务端余额有独立表达。
- 永久纪念经验与当前有效学习事实分别显示。

**证据范围。** 已有九张稳定的 Android emulator 视觉捕获：[登录](verification/screenshots/android-login.png)、[今日](verification/screenshots/android-today.png)、[小屋](verification/screenshots/android-room.png)、[奖励](verification/screenshots/android-rewards.png)、[成长](verification/screenshots/android-growth.png)、[设置上部](verification/screenshots/android-settings.png)、[设置下部](verification/screenshots/android-settings-bottom.png)、[360×640／1.3 倍文字](verification/screenshots/android-small-130.png)、[今日真实动态](verification/screenshots/android-today-event.png)。[首轮复核](verification/visual-review-android.md) 的六项修正经[同一 reviewer 复核](verification/visual-verdict-android.md)均为 resolved，disposition 为 ship；结论仅覆盖这些捕获和六项修正。退出登录路由、同步会话与令牌隔离行为按最新源码记录；[Flutter 测试](verification/flutter-tests.log)、[退出回归](verification/logout-regression.log)与[Android 联调](verification/android-e2e.log)等日志各有其运行时点，本记录不为尚未返回的最终检查新增通过结论。本次只读取证据、记录系统，没有重跑验证。没有 iOS 编译、目标硬件、真实推送、完整产品验收或独立动效验收结论。

最新已有日志记录 [Flutter analyze 无问题](verification/flutter-analyze.log)与 [30 项 host 测试通过](verification/flutter-tests.log)。覆盖一次串行冷恢复、初始化后首次登录 → 退出 → 第二次登录、延迟安全存储回包的会话守卫，以及 Dart 层通知授权、旧账号隔离和返回今日。补强的[启动后登录 Android 集成](verification/android-e2e-startup-login.log)也通过（1 项，运行 10 秒）：真实保存会话后 await app.init()，不预填 controller.user／sid；真实开发 HTTP／PostgreSQL 用例覆盖打卡、订单、通知权限允许、退出和重新登录恢复同小屋余额 5 与已完成订单。本记录只读取证据，没有重跑检查；host 通知测试本身不等于原生点击证据。

Android API36 ARM64 模拟器上，相同真实开发 HTTP／PostgreSQL 集成用例在[系统通知拒绝](verification/android-e2e-denied.log)和[系统通知允许](verification/android-e2e-allowed.log)两轮均通过。[原生通知证据](verification/notification-native-proof.json)覆盖两个 channel 存在、允许时有待排提醒、拒绝时无排程、payload 当前账号／空间范围、默认锁屏正文不含任务标题，以及退出清空待排提醒。[主程序 debug APK 构建日志](verification/android-build.log)与各次证明中的记录 APK 分别保留。上述权限证明限权限与排程断言；另外的原生本地送达、点击和启动证明见下文。正常页面布局没有变化，原九张捕获的 F1–F6 视觉评分范围保持原样。


[旧版原生本地提醒证明](verification/native-reminder-tap-proof.json)保留历史 APK 4e9adc1e… 的送达与点击；[较新版记录 APK 的证明](verification/native-reminder-final-proof.json)对应 6f2721b6…，记录应用进程被杀后系统本地提醒实际送达、原生通知点击返回“今日”，余额 5／永久经验 1 不变，payload 限当前账号与空间。通知接收器可能先启动原生进程再打开 Flutter Activity。第二份证明一次观测的送达延迟约 76 秒；它验证实际送达，不提供精确时刻或跨设备可靠性保证。

新增[启动 Android 复核](verification/visual-review-startup-android.md)为独立、有界的 ship，包含 persistence、fidelity、ceiling、material_fixes、keep 五节，只覆盖[恢复中](verification/screenshots/android-startup-restoring.png)与[恢复完成](verification/screenshots/android-startup-restored.png)两张 Android 捕获及回到既有 Today 的转场。首张尚未完成 Flutter 绘制的空白 PNG 已丢弃；有效两图是在同一记录 APK、真实开发 /auth/me 六秒延迟下再次冷启动后重拍，不与另行记录的原生点击语义混作同一捕获。[目标任务图](verification/screenshots/android-reminder-target-visible.png)在恢复后滚动取得。临时延迟 middleware／容器已移除，原 API／数据库／worker 恢复，实际 /health 为 ok、/ready 为 ready。新的启动复核不重开原九图 F1–F6，也不证明全部启动失败态、放大字体启动、动画性能、APNs／FCM、iOS 或真机；最后登录修正没有改变这两图的视觉构图。

## Colors

珊瑚承担主要操作，绿承担完成事实，深棕维持中文可读性；大面积保持奶油页面与浅纸内容。

### Primary

- **珊瑚操作色**（coral）：FilledButton 主填充与主强调。填充按钮使用 button-ink 前景。
- **深珊瑚文字**（coral-ink）：TextButton 的日期、余额、笔记、愿望和退出等操作文字；与填充色分开。

### Secondary

- **鼠尾草绿**（sage）：已完成任务说明、任务类别像素图标、今日成长条和有效学习日历。
- **浅鼠尾草容器**（sage-container）：选中分段与任务完成按钮的浅色 Material 容器，前景使用 ink。

### Neutral

- **奶油底**（cream）：页面与 AppBar。
- **浅纸面**（paper）：Paper、字段填充与底部导航。
- **深棕墨**（ink）：主文案、导航图标、OutlinedButton 前景。
- **柔棕说明**（secondary-ink）：次要正文、未解锁说明、待同步信息。
- **按钮深墨**（button-ink）：珊瑚填充按钮标签，独立于正文墨色。
- **浅木线**（line）：Paper 边框、字段基础边框、分隔和今日成长轨道。
- **浅桃选中底**（peach-indicator）：底部当前入口的胶囊指示底。
- **暖桃连接提示**（connection-banner）：首页连接错误／离线提示条。
- **深红错误**（error）：Material ColorScheme 的错误角色，用于登录与表单反馈。
- **白色前景**（white）：sage 有效日历及 onSecondary。

**The Contrast Roles Rule.** 珊瑚填充与珊瑚文字是两个不同角色。保留 coral 主填充，操作文案使用 coral-ink；填充按钮使用 button-ink，导航图标使用 ink。

[已保存的对比实测](verification/contrast-proof.json)给出：coral-ink／cream 为 5.88:1，coral-ink／paper 为 6.61:1，button-ink／coral 为 5.03:1，ink／选中导航为 8.67:1，ink／选中任务容器为 10.33:1，sage／paper 为 5.01:1。这是这些实际前景组合的记录，不等于所有组件或全部状态已经测量。sidecar 中的八阶色条仅用于文档面板预览，标明为合成色阶；应用没有使用这些色阶。

## Typography

**Display / Body Font:** Flutter 当前平台默认字体与系统中文回退。pubspec.yaml 没有声明自定义字体，ThemeData 没有显式 fontFamily。不能据 Android 截图为 iOS 承诺同一字体。

**Character:** 清晰的系统中文承载操作与阅读。像素语言保留在插画与图标，不强行应用到小字号中文。

### Hierarchy

- **Headline**：headline 用于登录“喵伴”，粗体，尺寸由前言定义。
- **Title large**：页面内容标题，如“今日约定”“成就册”和小屋名称。
- **Title medium**：任务、奖品、状态卡与组内标题。
- **Body large**：默认正文及完整完成标准，行高由前言定义。
- **Body medium**：次要说明，使用 secondary-ink。
- **Label large**：按钮标签。AppBar、NavigationBar、小辅助文案等未单独覆盖的角色沿用 Flutter Material 3 默认样式；不把其推断值列为项目令牌。

**The Independent Chinese Rule.** 标题、余额、日期、任务标准、状态和按钮文字独立于位图，使用正常文本与可换行布局。不能把概念图里的文字或数值烘焙进应用素材。

## Layout

首页使用 Scaffold、左对齐 AppBar、SafeArea、可滚动内容与固定 NavigationBar。四页在 IndexedStack 中保留页面状态，列表各自有 PageStorageKey。首页列表与编辑／设置页使用 content 外边距；登录和绑定页使用 section 外边距。间距的已复用步长见前言，任务卡间采用 item，主要分组采用 section。动态操作区用 Wrap，自然换行；任务标题用 Expanded，占据图标与勾选按钮之间的剩余宽度。

| 页面 | 当前结构 |
| --- | --- |
| 冷启动恢复 | cream 全页与 SafeArea 居中区域 → 48 logical px 像素爪印 → 恢复状态 → Material 进度；初始化完成后再进入登录、绑定或既有首页。 |
| 登录／激活 | 品牌标题与一句说明 → 180 logical px 房间 → 账号密码；激活时增加激活码与昵称 → 主按钮与切换入口。 |
| 创建／加入小屋 | 180 logical px 房间 → 小屋名和 IANA 时区 → 创建；分隔后输入一次性邀请码并加入。 |
| 今日 | 场景 → 永久经验进度／下一件纪念 → 等级与可用余额／待抵扣 → 日期 → 我的／TA的 → 待完成优先的任务 → TA 最新动态与直接爪印鼓励 → 管理、补记和完整动态。 |
| 小屋 | 240 logical px 场景 → 小屋名和双方昵称 → 永久经验与解锁进度 → 已解锁纪念 → 邀请、动态、轻轻提醒与规则。 |
| 奖励 | 可用余额 → 提供奖品、订单、愿望入口 → 奖品纸卡，价格、库存、上下架和兑换状态。 |
| 成长 | 我的／TA的 → 当前有效统计 → 月份与七列日历 → 阶段目标 → 成就册与纪念／事实区别说明。 |
| 设置 | 昵称、猫咪形象 → adaptive 通知与减少动态开关 → 免打扰时间 → 系统权限 → 保存 → 休息日、导出、退出。 |

今日场景当前按 MediaQuery 的**总屏幕高度**分支：高度小于 740 logical px 时为 100 logical px，否则为 190 logical px。实施契约中的 150–210 范围是常规首屏方向；实际短屏例外采用上述更小尺寸。这一例外已出现在 360×640／1.3 倍文字捕获中，第一项未完成长标题全文与勾选可见。场景使用 BoxFit.cover，短屏可裁切周边布景。不能从这张证据推导所有设备、键盘或文字比例均已通过。

成长日历使用七列嵌套 GridView，列／行间距为 compact，内层不单独滚动；整页列表滚动。任务和奖品编辑表单、设置与休息日页均采用 SafeArea 与滚动布局。应用没有独立的桌面、平板或网页界面规则，也没有自定义宽度断点。

“adaptive”在当前实现中指 Flutter 手机 Android／iOS 目标、系统尺寸与文字缩放，以及 SwitchListTile.adaptive 等平台控件行为。整体仍由共享 Material 3 主题、AppBar、NavigationBar、日期选择器与对话框实现，未实现单独的 Cupertino 页面壳。当前 iOS 尚未编译或截图验证。

## Elevation & Depth

项目自定义内容表面保持平面：Paper 用浅纸底与浅木边线划分层次，RoomScene 用圆角裁切；两者都没有自定义 BoxShadow。像素插画里的木桌、灯光与窗景自带素材深度。Material 的 AlertDialog、SnackBar、按钮覆盖层、浮动操作等沿用框架默认层次，没有定义项目阴影或海拔刻度，sidecar 不伪造这些令牌。

**The Paper Surface Rule.** 任务与记录使用 paper 的色面与 line 边界表达结构，沿用当前平面容器；不可把素材内的阴影当作通用组件阴影。

## Shapes

纸卡与场景采用 paper-scene 圆角，FilledButton 与字段基础轮廓采用 field-action 圆角，日历格采用 calendar 圆角。OutlinedButton、TextButton、分段选项、导航指示与系统对话框中未显式覆盖的形状继续使用 Material 3 默认形态；不能给它们附加一个不存在的统一圆角。Paper 的边线来自 Border.all 的默认单逻辑像素宽度。

PixelGlyph 在 8×8 网格上逐格原生绘制、关闭抗锯齿；默认图标为 24 logical px。位图场景、两猫与纪念使用 FilterQuality.none，保持最近邻采样。控件形状可以圆润，像素主体与图标保持整格边缘。

## Components

### Buttons

主要操作使用 FilledButton，文字说明和轻操作使用 TextButton，次要入口使用 OutlinedButton。三个按钮主题都显式设置最小 48×48 logical px；FilledButton 的形状和前景由前言定义。主题没有声明项目专属 hover、focus 或 pressed 颜色，继续使用原生 Material 状态覆盖层与焦点行为。

提交期间通过 onPressed: null 阻止重复操作，并提供“正在连接…”“正在保存…”等实际文本。图标按钮的视觉由 Material 默认控件承载；通知、设置、月切换、回到今日和打卡都有 tooltip 或明确 Semantics。截图与当前主题不是全应用触区、TalkBack 或键盘焦点的独立验收记录。

### Inputs / Fields

字段用浅纸填充、浅木基础 OutlineInputBorder 与 field-action 圆角。focused、disabled、error 的边框和颜色按当前 Material 3 ThemeData 解析，没有额外自定义焦点环。表单使用真实 validator，错误显示在字段或登录区域；密码使用 obscureText，账号密码声明 autofillHints。长说明字段允许多行，编辑页可滚动。

### Chips / Segments

今日与成长使用 SegmentedButton 切换“我的／TA的”；选中状态由 Material 的浅鼠尾草容器与勾标表达。任务编辑的重复星期使用七个 FilterChip 并放入 Wrap。它们沿用原生状态和布局，不定义新的自绘交互形状。

### Cards / Containers

Paper 是复用容器：浅纸底、浅木边框、paper-scene 圆角与 content 默认内边距。用于任务、奖品、动态和远程记录。EmptyState 使用标题、说明和可选真实 action，垂直 section 间距，不制造示例内容。

### Navigation

四入口与标签固定为今日、小屋、奖励、成长；图标来自 PixelGlyph 的 today、room、gift、growth。底为 paper，当前入口显示 peach-indicator 胶囊，所有导航图标使用 ink，图标尺寸为 24 logical px。通知与设置使用 AppBar 的原生 Material 图标；项目没有把所有辅助工具图标一律替换为像素。

退出登录由设置页 context.go('/') 返回根路由；GoRouter 对 initializing、user、needsLogin 与 sid 保护受限页面，设置路由额外处理空 user。冷恢复先显示 _StartupScreen，完成后未登录用户进入登录、未绑定用户进入绑定、已有空间用户进入首页。AppController 的 init 复用同一初始化 Future；登录／退出先等待它与正在执行的同步结束，再切换会话。登录安装新令牌后显式调用 _restoreAccount，恢复该账号和空间；不能复用已完成的冷初始化代替登录恢复。会话世代继续阻止旧同步、WebSocket 与 API 回包作用于新账号；Api.restore 在安全存储读取后校验令牌世代。最新登录修正由 30 项 host 测试与启动后登录 Android 集成覆盖，不把历史提醒证明自动视为最新源码全部行为证明。

### Task Row / Shared Growth / Partner Event

任务卡以像素类别图标、可换行标题、完成标准、积分与状态、笔记和独立勾选组成。C 使用 c 网格，运动使用 exercise，其余当前类别使用 book。自己的普通今日约定直接勾选；撤销先确认后果；历史日期进入有理由的补记／更正。TA 的任务只读，以状态图标显示。

排序先未完成后已完成，同组先必做后选做，再保持原始顺序。提交时显示 24 logical px 进度指示；队列存在时按钮禁用，显示“待同步 · 积分尚未入账”。失败状态显示原因，并在 Wrap 中提供“重试同步”和“使用服务器记录”。完成同时有勾标、文字与 sage 颜色。

今日成长条紧贴场景，使用四点高 sage 条、line 轨道和下一件纪念差值；读取 growth.permanent_xp 与当前解锁阈值。其 Semantics 说明永久经验与下一件纪念。TA 最新动态来自 latest_partner_event，对真实事件 ID 提交爪印；无事件时显示真实空说明，并保留完整动态入口。

**The Memorial and Facts Rule.** 今日／小屋的经验、等级和装饰属于永久纪念；成长页的有效完成数、有效学习天数、C 次数和日历属于更正后的学习事实。撤销不使纪念装饰倒退，却可以改变有效统计，两者不能互相替代。

### Reward / Calendar / Achievement

奖品卡对提供者显示编辑入口，对领取者显示兑换。下架、售罄或可用余额不足时禁用兑换，按实际原因显示“暂未上架”“已兑完”或“还差 N 小鱼干”。能兑换时先确认价格，服务端保留最终余额与库存验证。捕获中的可用 30／价格 70 是明确标记的开发验收数据，不是默认生产奖品。

日历显示有效学习记录，sage 格配白色日期，无有效完成用浅纸底配 ink，并给日期和记录状态提供 Semantics。解锁成就用 PixelSprite，未解锁用锁图标；说明明确徽章保留纪念、统计随撤销和更正更新。

### Pixel Room / Assets / Motion

正式运行素材来自 apps/mobile/assets，pubspec.yaml 注册三份场景素材。它们由 RoomScene 与 PixelSprite 独立组合，既不使用概念图整页截图，也不包含透明按钮覆盖层。

| 素材 | 当前尺寸与使用 |
| --- | --- |
| room-background.png | 1536×1024；房间层，BoxFit.cover、FilterQuality.none。 |
| cats-atlas.png | 1774×887；四列两行，逐行绘制两种猫，每列为 pose 帧。猫宽为场景宽的 31%，左右位置由场景比例决定。 |
| decorations-badges.png | 1254×1254；三列三行。索引 0–3 为台灯、猫窝、植物、书架，4–8 为五个纪念成就。PixelSprite 默认显示 48 logical px。 |
| app-icon.png | 1254×1254；存在于正式素材目录，用于应用包装，不是 RoomScene 的运行图层；本视觉复核未评估 launcher 包装。 |

场景只叠加服务端 growth.decorations 中已解锁的项目：台灯 10、猫窝 30、植物 60、书架 100 永久经验。当前基础房间本身已有灯、植物与书架画面，因此布景不能被当作“额外纪念已解锁”的证据，解锁事实以服务端数据和列表状态为准。设置中已有奶油橘猫／灰白猫选项；当前 RoomScene 总是按 atlas 两行绘制两只固定猫，没有据该偏好交换场景位置。

源码的轻动效为帧切换：pose 0 待机，周期 5 秒，眨眼帧 1 持续 160 ms；同步成功的打卡反馈使用帧 2，观察到等级增长使用帧 3，同步收尾在 500 ms 后回到 pose 0。没有定义缓动、音效或连续位置动画；不把合同中的“升级亮灯”描述成已独立验证的灯光动画。

今日与小屋传入账号 reduce_motion；RoomScene 内统一把调用方 reduceMotion 与 MediaQuery.disableAnimations 以 OR 合并。因此登录、绑定、今日与小屋的场景均在系统减少动态开启时固定帧 0，今日和小屋同时尊重账号偏好。这里是源码覆盖的记录；静态截图不证明帧时序、系统设置切换或性能已经在目标设备验收。

### Startup Restoration

_StartupScreen 使用现有 cream Scaffold、SafeArea、Center 与 section 内边距；48 logical px 的 PixelGlyph('paw')、独立中文“正在恢复账号与小屋…”和 Material CircularProgressIndicator 之间各留 section 间距。状态文字设为 Semantics liveRegion，未引入新字体、插画、按钮或独立动画令牌；恢复期没有登录输入框和可提交操作。状态只覆盖一次冷启动恢复，正常页面构图保持原样。

AppController.init 一次串行恢复安全存储令牌、账号档案、活动空间、缓存快照和本机队列，并拉取当前服务端状态；initializing 从开始持续至 finally。登录与退出等待初始化，登录仍单独恢复新会话。存储损坏／不可用导致初始化异常时，控制器清空内存 user、sid、snapshot 与 pending，设 needsLogin 并保留经过净化的“本机会话恢复失败，请重新登录。”错误，尽力清除安全存储会话与档案，不暴露令牌 JSON。这里没有声称删除所有 SQLite 历史快照，也没有把控制器错误字段等同于所有失败态已做设备截图验收。

恢复期间主程序暂缓通知更新、注册／排程和待处理通知路由；完成并拥有当前账号快照后再按既有授权与会话守卫处理。恢复完成无 snapshot 的首页连接态仍有独立文案与重试，不与冷启动恢复混为同一状态。

### Notifications / Reminders / Export

设置页继续先解释用途，再申请系统通知权限；拒绝后仍可打卡、前台同步和查阅收件箱。NotificationService 初始化 Android 的 partner_events（TA 的动态）与 task_reminders（每日约定提醒）两个 channel，初始化时检查现有权限。恢复前台先重新检查系统权限，再同步和更新通知；权限改变会清除旧的计划与注册缓存键，重新按当前状态处理。

本地提醒计划串行执行。去重／重排键包含账号、空间、API 会话世代、系统许可、snapshot_seq、小屋时区下的本地民用日期、快照中的今日以及当前偏好；账号、日期、权限、偏好或序号变化都可使旧键失效。读取已接受任务成功后才替换提醒，离线读取失败保留原来的已排提醒。常规重排只取消 payload 标识为任务提醒的待排通知，保留伴侣已显示通知和无关通知。退出完成后调用 cancel，递增计划世代令未完成的异步计划失效，并串行清空全部通知。

reminder_plan.dart 从当前小屋的民用日期起规划七个日期，而非累加七段 24 小时；采用每个日期已生效且被接受的时区规则，UTC 和 GMT 别名直接解析为 UTC。只选当前执行人的已接受任务版本，遵守生效后的启停、重复星期、结束日期与个人休息日。今日已有日期实例时优先匹配其冻结 task_version_id；该版本未在返回数据中找到时才回退到最新可用的接受版本，今日已完成实例不再提醒。免打扰内的提醒延后到该时区的免打扰结束民用时刻，包含跨日和夏令时边界；仅保留未来提醒，按时间排序，最多排 60 条。Android 使用 inexactAllowWhileIdle，不承诺精确到分钟的送达。

锁屏学习详情只有 lock_screen_details 明确为 true 时才显示：本地提醒可显示任务标题，前台伴侣通知可显示事件短文案；否则使用通用提示。前台远程通知先从服务器按 notification_id 获取当前账号有权查阅的通知，核对会话与空间，并遵守打卡／互动／奖励偏好和免打扰，不能授权则保留收件箱为事实来源。注册与通知回包也检查账号／会话身份，避免旧账号异步结果作用于新会话；注册失败以 registrationError 保留明确反馈，不代表推送已成功。

点击通知先核对空间及携带的账号，再同步当前会话。远程通知按授权 ID 读取并标为已读，再按事件进入订单、阶段目标、任务或动态；读取失败进入通知收件箱。本地任务提醒不含远程通知 ID，返回根页面后明确选中“今日”，而不是保留点击前的其他入口。导出仍只读取有权访问的空间数据；调用系统分享后，无论分享成功或抛出异常，finally 都会删除存在的临时 JSON 文件。

这些行为由当前源码、30 项 host 测试、Android 通知拒绝／允许两轮权限与排程证明，以及记录版本 APK 的实际本地提醒送达与点击证明分别支持。原 F1–F6 视觉复核保持原范围，新增启动复核单独界定；APNs／FCM 真实送达、iOS 和目标真机仍未验证。

### Loading / Empty / Offline / Error

initializing 时根页面显示“正在恢复账号与小屋…”的冷恢复屏；初始化完成后首页无 snapshot 时显示“正在打开我们的小屋…”和重新连接；首页有 error 时显示连接条，离线时加“离线”与重试。RemoteList 用 FutureBuilder 提供加载指示、读取失败／重试、真实空态及下拉刷新；今日也支持下拉同步。

登录错误使用 error 角色；其他命令错误由 attempt 的 SnackBar 表达。保存和登录以忙碌文字及禁用按钮表达进度，成功后的列表／余额来自同步数据。离线意图与已入账状态分开，待同步不增加可消费余额。系统通知权限拒绝时，设置页保留说明及收件箱、前台同步入口；Android 模拟器上的本地提醒已有实际送达与点击证据，远程推送和目标设备送达仍待验收。

失败意图可继续“重试同步”，或选择“使用服务器记录”。后者先显示“使用服务器记录？”确认，说明“放弃本机这条同步失败的操作，不修改服务器记录。之后可按最新记录重新打卡。”AppController.discardFailedOperation 只处理当前账号 pending 中 status 为 failed 的操作，清除该条本机失败意图，检查账号与空间未切换后刷新队列并同步服务端快照。之后用户重新打卡会从当前快照取版本并创建新的 UUID，避免持续重发已经冲突的旧载荷。这是源码中的失败恢复流程；没有更改九张已评捕获的正常状态结构，不为其新增视觉评分或尚未返回的测试通过结论。

## Do's and Don'ts

### Do:

- **Do** 保留用户已定的奶油、珊瑚、鼠尾草绿、温暖木桌与两只不同毛色像素猫。
- **Do** 使用独立中文文本、原生控件和当前像素网格图标，让真实任务可直接勾选。
- **Do** 延续当前最小 48×48 logical px 按钮设置，并为图标操作提供明确标签；新增页面仍需对应设备与辅助功能验证。
- **Do** 按实际屏幕高度与文字缩放安排内容，保留短屏待完成标题和操作优先。
- **Do** 明确区分可用余额、待同步操作、永久纪念经验和当前有效统计。
- **Do** 把截图、源码和日志的证据范围写清楚，保持 Android 六项视觉修正与整体产品验收的边界。

### Don't:

- **Don't** 覆写根 DESIGN.md、DEVELOPMENT.md 或 GOAL.md，也不要用本视觉记录替代功能合同。
- **Don't** 重开风格选择，或把整页概念图当作实际界面后覆盖透明触区。
- **Don't** 把概念图、开发验收截图或 sidecar 预览中的数值、奖品和状态注入生产默认数据。
- **Don't** 用永久经验或纪念徽章冒充实时有效学习次数和日历。
- **Don't** 在余额不足时展示可执行的兑换，或在待同步时显示积分已经入账。
- **Don't** 从本轮静态 Android 捕获宣称 iOS、硬件、推送、全部状态、动效或完整产品已经验收。

## 登录与激活输入恢复（0.1.1）

保持现有像素猫场景与Material表单，账号/密码持续显示格式帮助，首次使用入口标为“首次使用？激活账号”，昵称注明可用中文。提交后对齐服务端长度和账号字符规则，错误就近显示且允许多行；busy时冻结输入与模式切换，键盘Done可提交。服务端422字段提示保留原输入，改正该字段清除对应错误，全局错误用liveRegion宣告。激活成功但登录失败后自动切换到登录重试，并说明无需再次使用激活码。切换模式保留控制器内容。原生phone/短屏1.3字号错误态捕获见verification/screenshots/auth-fix-*.png，仅限Android模拟器，不代表双真机或iOS验收。
