# 喵伴实施状态

更新时间：2026-10-09（America/Los_Angeles）。持续 Goal 已创建，工具状态仍为 **blocked**，无人为预算；该状态来自此前连续三轮缺少外部依赖，尚未由平台恢复。阿里云已部署，本轮安卓真机已连接并完成界面检查；iPhone、iOS 签名和推送仍未齐备。只有 F01–F10、AC01–AC14、Android/iPhone 真机与阿里云部署全部有实际证据后才 complete。

## 已执行的事实

从仅有用户文档与概念图的仓库建立 Flutter 手机客户端、FastAPI 服务、PostgreSQL 模型/迁移、Docker 开发/生产配置。原始 DESIGN.md、DEVELOPMENT.md、GOAL.md、参考图保留；没有适用 AGENTS.md，没有提交用户原始未提交文件。

- 本机 macOS Apple Silicon；项目私有 Flutter 3.47.5 / Dart 3.13.4、Android SDK 36、API 36 ARM64 模拟器、JDK 21 已安装。完整 Xcode 缺失，iOS 编译/真机尚未通过。
- API Python 3.14.6；依赖锁在 services/api/uv.lock；Flutter pubspec.lock 已生成。
- 开发 Compose PostgreSQL 18.3、API 与 worker 运行，本地 `/health`、`/ready` 通过。生产数据库、签名和推送凭证未使用演示配置。
- 后端 **49 项测试通过**（41 项 PostgreSQL 业务／worker／认证，8 项 APNs／FCM 模拟 HTTP 契约）：`docs/verification/auth-fix-backend-tests.log`；原39项日志保留历史范围。包含幂等、并发库存/钱包、容量、账目冲正、全勤、任务/目标版本、补记、DST、赠品不重发、更正、成就、通知、会话、不可变流水与部分推送重试去重。另有 Starlette testclient 的一条弃用警告；现有测试通过。
- Flutter 分析 **无问题**，**37 项测试通过**：持久离线队列、账号隔离、跨日补记、DST免打扰、长标题/放大字体、设置页退出、延迟刷新/会话切换/原幂等键重试，以及版本冲突后的明确放弃与新UUID重新提交。新增提醒跨日／账号／偏好重排、离线保留、登出竞态、UTC与未来时区规则、冻结版本、授权冷启动与旧账号提醒隔离；另覆盖初始化不显示登录表单、迟到存储不能覆盖新会话、恢复失败脱敏，以及冷初始化→账号一登录→退出→账号二登录。最新证据 `auth-fix-mobile-tests.log`、`auth-fix-mobile-analyze.log`；原30项日志保留历史范围。
- Android 本地开发最终调试主程序 APK 在启动/登录修复和补强集成后重新构建、验签并安装恢复今日页，SHA256 `529d5fb56404124c7e8f13d1751f03db7bc816972436edba5ee62d00d8dedfbd`，见`android-final-main-proof.json`；原包另存本机私有 `.tools/miaoban-local-debug-final.apk`。包含 FCM 原生桥、像素图标与启动素材，调试地址`10.0.2.2:8000`仅用于该模拟器。原生提醒证明保留此前各APK摘要，不重标为云端包。新增云端调试试装包连接 `https://8.136.0.78`，摘要与分发记录见`android-cloud-preview-proof.json`，当时使用开发签名；本轮已另行生成私有release签名与候选APK，详见下节。
- Android 模拟器双账号真实后端端到端测试 **同一用例两种 OS 权限状态均通过**：`android-e2e-denied.log` / `android-e2e-allowed.log`（绑定、接受任务、界面打卡、兑换、兑现、确认、设置页退出、重新登录恢复同一小屋余额与订单）。同时验证原生通知频道、拒绝时不排提醒、允许时真实待排提醒与退出清理，见 `notification-native-proof.json`。属于前一版本模拟器权限/排程证据；实际本地送达另见下条，不能当作真机或远程推送。
- Android 主程序本地提醒在进程退出后**实际系统送达并完成原生点击返回今日**，两次均验证余额5、永久XP1不变。`native-reminder-tap-proof.json`/`native-reminder-final-proof.json`保留当时APK摘要，后一次包含恢复页语义、无登录输入框及六秒真实开发API延迟下的冷启动重拍。临时延迟容器已移除，原API、数据库和worker恢复正常。非精确提醒本次延迟22.5秒/76.019秒，只是两次模拟器记录。
- 最终登录修正后补强集成 `android-e2e-startup-login.log` **1项通过**：真实保存会话并`await app.init()`，再完成双账号业务闭环、OS通知允许、设置页退出、重新登录恢复同一小屋/余额5/完成订单。与原两种权限测试分开保留；最终主程序重建安装见`android-final-main-proof.json`。
- 开发 HTTP/WebSocket 冒烟真实完成“100→兑换70→30→取消两次→100→兑换→兑现→确认”，30 次测量 HTTP 开始至 WS 收到的 p95 约 275 ms：`http-smoke.json`。这不是 AC04 手机界面延迟测量。
- Android 实际停服→排队→force-stop→离线启动→服务恢复：待同步期间可用余额保持0，恢复后净余额−50→30，流水9→11，永久经验保持3，再读没有重复奖励。`offline-proof.json` 与三张 `android-offline-*.png`；该截图来自会话修正前的同一队列实现，最终版本另通过上述测试。属于模拟器停服演练，不是真机断网/跨日证明。
- API 重启后真实 WS 恢复旧游标、接收持久事件，已确认游标无重复回放，钱包/经验不变：`reconnect-proof.json`。客户端以重新拉一致快照处理事件提示，旧连接回调不会替换新会话连接。
- 实际执行 pg_dump、校验SHA256并恢复至独立容器 `miaoban-restore-20261008180358`；**26张业务表**计数与规范化摘要一致，钱包流水求和差异0。`restore.log`、`restore-comparison.json`；这是18:03 UTC的开发快照，之后集成测试新增的开发数据不在该备份内。另已执行阿里云初始生产库备份/隔离恢复，见下节；正式业务数据恢复仍待验收。
- 生产 Compose 配置/HTTPS与示例密码防护、备份保留边界和健康检查退出码已验证：`production-config-proof.json`、`retention-proof.json`、`healthcheck-proof.json`。本轮真实云端部署另列如下。CI workflow 已提供，尚无远端与实际CI运行。
- Android 模拟器九张稳定截图；Impeccable reviewer 对 F1–F6 修正均评为 resolved，disposition ship：`visual-verdict-android.md`。只覆盖这些修正，不代表 iOS、硬件、推送或整体产品验收。

## 本轮阿里云部署与旧项目删除

- 用户提供 `root@8.136.0.78`，暂无域名，并明确要求删除废弃 OrgMesh。按实际路径停止/禁用/删除其 systemd 服务、环境文件、nginx 站点、`/opt/orgmesh`、`/var/lib/orgmesh`、旧归档及本轮旧配置副本；8787 不再监听，无相关命名路径残留。共享 nginx 主配置摘要不变，`rootjourney_mongo-data` 等无关卷保留。证据 `cloud-orgmesh-removal-proof.json`。
- Ubuntu 24.04 x86_64，独立目录 `/srv/miaoban`，Compose 项目 `miaoban-production`。API/worker 镜像 `miaoban-api:20261008-ip01`，生产库 `postgres:18.3-alpine`；本机导出 amd64 镜像、上传校验后导入，避免服务器无法连接 Docker Hub。源码与镜像摘要见`cloud-release-manifest.json`，实际迁移/启动日志`cloud-deployment.log`。
- API 仅发布 `127.0.0.1:18000`；数据库无宿主端口。主机 nginx 接管 80/443，HTTP 重定向 HTTPS并保留 ACME 路径。Let's Encrypt 实际 IP SAN 证书到期 `2026-10-15T17:49:28Z`。公网系统信任库验证 `/health`、`/ready` 200，未登录 `/api/v1/auth/me` 401；没有跳过证书验证。见`cloud-public-https-proof.json`。
- 生产数据库随机口令在服务器生成、仅存私有配置；没有导入 demo 账号或业务数据。已生成两枚24小时一次性激活码，仅存本机忽略、0600私密交付文件；证据索引只记录数量、有效期和路径，不记录明文。正式账号与双人绑定须用户自行完成。
- 真实生产 pg_dump 摘要校验后，恢复至 `miaoban-restore-20261009024729`（`network none`），26张业务表数量/规范化摘要均相等，钱包差异0。该时刻正式业务表均为空，因此只证明初始生产结构与恢复链，不能算正式任务/订单数据 AC14 全部通过。恢复容器已停止保留。证据`cloud-backup-restore.log`、`cloud-restore-comparison.json`。
- 已安装并启用每日备份、每5分钟健康检查、每12小时短期IP证书续期三个 systemd timer，首次服务执行成功，实际续期模拟通过。最终证据 `cloud-final-deployment-proof.json` 核对运维补充归档/10个源文件摘要、镜像、生产配置0600、0账号/0小屋/2激活码、三个服务success及无failed unit。健康检查失败记录到 journal，外部告警和获准加密异地副本尚未接入。
- Android 模拟器新增原生 HTTPS 只读集成1项通过：使用客户端真实 Dio/API访问云端 readiness并断言未登录401，没有注册账号或写生产业务表。`android-cloud-connectivity.log`；新增测试后分析无问题`flutter-analyze-cloud.log`。云端调试主程序 APK 已构建、v2验签、模拟器安装/启动至登录与激活入口；公网下载HEAD200/258658356字节、Range206/ZIP魔数通过，见`android-cloud-preview-proof.json`及`cloud-preview-download-proof.json`。不冒充真机、正式签名或云端双账号业务验收。

## 本轮继续推进：安卓release与云端有数据恢复

- 检查完整Xcode仍未安装，USB没有目标手机，adb仅有模拟器；App Store当前未登录，已打开Apple官方Xcode页面供用户安装。已集中请求两台型号/系统/USB、安卓Google Play支持及Apple账号类型；密钥不要求粘贴聊天。
- 在没有旧签名配置的新App中生成本机私有RSA3072/PKCS12签名材料，目录0700、keystore/密码/key.properties均0600，被Git忽略，未上传服务器。用户保管入口`.tools/signing/README.txt`；元信息`android-release-signing-material.json`没有密码。
- 构建 **0.1.0(2) AOT release候选APK**，62097836字节，SHA256 `586a65375c938a39f2c0b015ca506aee451c50215b5d32c9e00775008c131d9c`。实际v2验签、API24最低版本、模拟器安装/启动至登录和激活入口、公网HEAD200/Range206均通过；`android-cloud-release-proof.json`、原生XML与`android-cloud-release-login.png`。此处为历史0.1.0+2，后续认证修复已递增为0.1.1+3。不是整体正式发布/真机或真实推送通过。此前HTTPS只读集成的调试包证据保持原范围。
- 新签名不能直接覆盖旧调试签名；模拟器先保存本机调试数据至0600私有归档，再卸载调试包装release。用户若已装调试包，须先联网同步，再切换签名；服务器记录可重新登录恢复。新release下载入口见CLOUD_DEPLOYMENT.md，旧调试入口保留。
- 新建独立 `/srv/miaoban-acceptance` / Compose `miaoban-cloud-acceptance` / 数据库`miaoban_acceptance` / 独立卷及随机口令，API只在127.0.0.1:18001，通过认证SSH隧道验收。dev账号只进入这个隔离库，没有迁入正式库。`cloud-acceptance-provision-proof.json`。
- 同一已部署API镜像真实完成三任务打卡30分、阶段奖励至100、兑换70至30、取消两次恢复100、再次兑换/兑现/确认后30；30样本HTTP开始→WS p95约350ms（不代表手机UI延迟）。`cloud-acceptance-http-smoke.json`。实际API重启后26表数据不变，重新登录恢复余额30/取消与完成订单；`cloud-acceptance-relogin-proof.json`。
- 对上述有数据验收库pg_dump/校验/`network none`隔离恢复，26表数量与规范化摘要全等：1小屋、3实例、2钱包、7流水、2订单，钱包差异0。`cloud-acceptance-restore-proof.json`。这补足阿里云有数据恢复演练，但正式用户的生产数据及双真机AC14仍未验收。验收API/数据库与恢复容器已停止保留，隧道已关闭，正式服务继续健康。

## F01–F10 与阶段

| 功能 | 实现与本地证据 | 尚未完成 |
|---|---|---|
| F01 私密账号/绑定 | 独立激活、Argon2、会话轮换/撤销、一次性邀请、两人容量、REST/WS 鉴权；API/模拟器通过 | 正式账号与双真机绑定 |
| F02 每日约定 | 提议/审批/拒绝、版本、星期/结束日、未来暂停/恢复/归档/休息、零点必做快照 | 双真机操作 |
| F03 打卡/笔记/离线 | 服务端状态/版本、笔记、更正/补记、SQLite 持久队列、账号隔离；API/Flutter与模拟器离线重启证据 | 实际手机断网/重启/跨日 |
| F04 同步/鼓励 | 持久事件游标/WS、API重启恢复、重连完整快照、真实今日动态/鼓励、四类鼓励/留言、每天轻提醒 | 手机 UI p95、真实通知 worker 重启投递边界 |
| F05 积分 | 差额不可变流水、个人可用/待抵扣、全勤/冲正、消费/一次退款；并发/真实 PostgreSQL 测试 | 正式双端 35 分演示 |
| F06 奖励铺 | 提供者编辑/上下架、库存/价格、愿望、订单快照、兑现/确认、待兑现取消、已兑现双方退款 | 双真机奖励闭环 |
| F07 阶段目标 | 自动/人工、证据、积分/零价赠品、修改版本审批、奖励更正、已交付赠品不重发 | 双真机阶段演示 |
| F08 成长 | 5 徽章、有效月历/统计、永久 XP、10/30/60/100 四装饰、像素猫轻动效 | 双 OS 截图/读屏/性能核验 |
| F09 通知 | 本地提醒随日期／账号／权限／偏好更新；离线保留原提醒；仅替换任务提醒；冷启动授权跳转与账号隔离；Android模拟器实际本地提醒送达/点击；两推送通道隐私一致；缺凭证可恢复投递 | 通道凭证、实际手机前台/后台/进程不活跃推送 |
| F10 设置/恢复/导出 | 昵称猫形象、账号/系统减少动画、通知、未来休息日、退出队列处理、JSON分享清理；模拟器实际初始化后重新登录恢复、启动恢复页与会话竞态测试 | 双真机重新登录/通知撤销验证 |

M0–M5 已有可运行实现与上述本地验证，不能称整体通过；M6 开发备份与云端初始生产部署/恢复链已完成，正式双端业务、正式数据恢复与真机未通过。新增改动须继续验证。

## 实现决策

两人空间写事务先锁空间序列行，再锁用户幂等记录；账目按来源当前应得净额写差额，唯一约束兜底。访问令牌 15 分钟，刷新令牌 30 日且轮换/重放撤销，仅存摘要。邀请秘密只返回首次创建响应，不存入幂等响应。初始全勤奖励为 0，经双方接受的未来规则开启。WS 250 ms 查询持久事件，数据库是事实源。永久纪念经验/徽章不倒退，有效统计/阶段奖励随更正重算。

生成的背景、双猫 atlas、九宫格装饰/徽章、应用图标与来源见 docs/ASSETS.md。文字、按钮、状态与8×8功能图标由 Flutter 渲染。原始 DESIGN.md 保留，实际移动设计记录在 docs/MOBILE_DESIGN.md。

## 外部输入（服务器已收到，其余仍待提供）

服务器权限已收到，暂无域名；IP HTTPS已实际部署，旧 OrgMesh 按用户后续明确授权删除。安卓签名已在本机生成并交付。已实际读取华为 HBN-AL10、Android 兼容版本12/API31及安装包。尚缺 iPhone 型号与系统、小屋时区确认、完整Xcode/Apple团队与分发方式、APNs/适用Android通道凭证，以及异地加密备份/外部告警的获准目的地。密钥放本机私有文件，不粘贴聊天。不购买服务、不删除无关数据。

## 本轮补齐与依赖审计

第二轮进行了实际功能修复，并非单纯等待：补齐 F09 的跨日／账号提醒失效、原生通知频道、恢复前台权限刷新、只替换任务提醒、退出时异步计划失效、锁屏隐私与配置恢复重试；补齐本地提醒返回今日和分享失败的临时文件清理。另检查 F02：未绑定时正积分提议可持久保存为待接受、approver_id 可为空；绑定后审批按实际另一成员判断，界面不依赖旧 approver_id。

第三轮实际补齐了原生本地提醒送达/点击证据，并修复冷启动时过早出现登录表单和迟到安全存储写回；最终检查又修复初始化缓存导致再次登录不恢复资料的回归，30项host测试和补强原生集成通过。新恢复页独立复核`visual-review-startup-android.md`为disposition ship，仅限新增Android启动捕获，原九图F1–F6范围保持原样。

原始启动轮、第二轮、第三轮连续缺同一批外部依赖。第三次历史检查见`external-dependencies-audit.json`：当时仅有模拟器、完整Xcode缺失、尚无服务器参数；它保留历史事实，不代表当前云端状态。后来已补齐服务器与Android签名，并继续执行云端有数据恢复；本轮又连接安卓真机并检查界面，iPhone、完整Xcode/Apple团队和push配置仍缺。目标范围与全部AC保持，不以模拟器或隔离验收库替代最终正式双真机验收。

## 继续入口

用户连接安卓手机后，已通过授权 USB ADB 独立读取华为 HBN-AL10、Android兼容版本12/API31与旧预览包0.1.0(1)；既有会话可进入四个主页。实际六张截图覆盖空状态、1.15字号、新建约定表单与键盘滚动，未重新激活或登录、未提交业务操作。旧预览包与0.1.1(3)预览包同签名，可保留数据覆盖更新；release签名不同，此次未安装或卸载。证据见`verification/phone-audit-20261009/AUDIT.md`、`device-proof.json`和最新依赖审计。用户没有Apple开发者账号。普通Apple ID与完整Xcode可以做有限期个人iPhone试装，但TestFlight/APNs仍需开发者会员，依据Apple官方membership比较页；完整iOS目标没有因此删去。

本地核心流程和本轮云端部署证据已保存；F01–F10整体验收未通过。接续时先读本文件和 CLOUD_DEPLOYMENT.md。待已请求设备/签名/推送信息到位并由平台恢复 Goal 后，完成正式激活绑定、iOS构建/签名、双端安装、实际推送、AC01–AC14真机验收与正式业务数据备份恢复。现有 Android FCM 仅覆盖有 GMS 的实际配置；无 GMS 设备须完成适用厂商通道。工具 Goal 状态仍 blocked，不能将余下条件视作完成。

## 激活报错修复（2026-10-08）

用户确认故障发生在“激活并登录”，具体输入未收集。复现发现App只校验最小长度，未对齐服务端ASCII账号、最大长度与首尾空格规则；服务器422只返回泛化错误。已补齐两端一致校验、各字段可操作提示、服务端field_errors脱敏响应、输入保留与无障碍liveRegion。激活成功后如登录失败，直接保留账号密码进入登录重试，不再消耗一次性激活码。账号仍为3–80位英文字母/数字/_.@-；昵称支持中文，密码10–128字符。

服务器已切换到20261008-auth01，迁移头未变化，升级前自动备份，生产账号/小屋/激活码数量在部署前后为0/0/2，nginx配置不变。真实公网HTTPS验证字段提示和无效激活码恢复提示，未创建测试生产账号或消耗正式激活码。0.1.1(3) debug与release分别保持原签名，原下载URL已原子更新；公网HEAD/Range验证通过。证据auth-fix-cloud-deployment.json、auth-fix-public-https-proof.json、auth-fix-android-artifacts.json及auth-fix-public-apk-proof.json。后续真机检查确认旧包既有会话可进入今日；修复版在真机的新激活/登录流程尚未实际提交，不能由既有会话和模拟器测试替代。


## 本机目录迁移（2026-10-09）

按用户要求，项目整体从 `/Users/dev2/Documents/ChatGPT/study` 移动至 `/Users/dev2/Documents/Project/maoban`。同文件系统目录重命名，原20项顶层内容及Git、隐藏配置、APK、备份、工具和文件权限均保留；原路径仅保留指向新目录的兼容链接，当前Codex项目配置和历史证明仍可访问。
喵伴专用 `miaoban_api36` AVD 的数据与ini已移动至 `.tools/android-avd`，原 `~/.android/avd` 注册路径保留兼容链接。已更新运行配置、虚拟环境入口、Flutter/Android SDK与真机报告截图路径；历史验证日志和原始GOAL/DESIGN/DEVELOPMENT未改写。APK摘要及私密文件0600权限一致，Flutter/后端/adb可用，本地APIready200。云端部署与手机未操作。迁移记录：`verification/local-directory-migration.json`。

## Claude 重构回归修复（2026-10-09）

按用户“修复，先不打包”的要求，修复两处已复现问题。通知列表改用独立的原始分页偏移量，去重不会阻止继续加载；刷新期间暂停追加，过期分页响应和错误不会影响新列表。历史日期请求增加代次校验，回到今日或启动新日期请求后，旧响应及旧错误会被忽略，当前请求的失败提示保留。

新增 `test/remote_list_test.dart` 和 `test/today_history_test.dart`，共7项回归测试，覆盖完整重复页、刷新竞态、失败重试、回到今日后的延迟响应/错误、日期请求乱序及当前请求错误提示。实际执行 `make test-mobile`：严格静态分析0问题，44项测试全部通过。证据：`verification/claude-review-fix-mobile-checks.log`、`verification/claude-review-fix-targeted.log`、`verification/claude-review-fix.diff`。本轮仅修改本地源代码、测试及记录，未打包、部署或操作手机，版本仍为 `0.1.1+3`；新界面真机验收仍待后续执行。
