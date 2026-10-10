# 喵伴运行手册

本机开发已运行。阿里云现已通过实际 IP HTTPS 部署、初始生产隔离恢复和定时维护；本次地址/试装/激活/维护见 CLOUD_DEPLOYMENT.md。Android release私有签名已补齐；iOS、真实推送、双真机和正式业务数据恢复尚未验收，详见 IMPLEMENTATION_STATUS.md / ACCEPTANCE.md。以下通用 Caddy 生产示例与本次主机 nginx 部署配置区分使用。

## 开发

项目根目录执行 `make doctor`。锁定 Flutter 3.47.5（仓库私有 `.tools/flutter`），Python 3.14.6、uv 0.12.23、JDK 21，Docker Compose V2。`make setup` 仅在没有 `.env` 时生成随机本地数据库配置，不覆盖已有配置。新机器先 `git clone --depth 1 --branch 3.47.5 https://github.com/flutter/flutter.git .tools/flutter`，必要时按官方网络环境说明设置下载镜像。本机使用 CFUG Flutter 镜像下载 SDK，源码来自 Flutter 官方 tag。

执行 `make dev-up` 构建并迁移开发库；`make seed-demo` **只允许 development 环境**。演示账号 `demo_a`、`demo_b`，密码 `Demo-only-password-123`。这些账号只在隔离开发环境使用，seed 不改钱包。`make test-backend` 只连接 `miaoban_test`；测试会清空此测试库，拒绝其他库名。`make test-mobile` 运行分析与测试。`make test-e2e DEVICE=emulator-5554 API_BASE_URL=http://10.0.2.2:8000` 连接开发 API，不可指向生产。

Android 本机用 `.tools/android-sdk`、JDK21，Flutter doctor 可检查。模拟器通过 `10.0.2.2:8000` 访问宿主 API；iOS 模拟器用 `127.0.0.1:8000`。启动：`cd apps/mobile && ../../.tools/flutter/bin/flutter run -d DEVICE --dart-define=API_BASE_URL=URL`。iOS 真机使用 HTTPS；不要把本地回环地址写入正式包。开发明文网络只在 Android debug manifest 开放。

## 生产部署

先落实专用 SSH Host、系统/现有服务、专用目录、域名解析、80/443 使用情况、Docker/Compose、磁盘空间和备份位置。只在用户提供的专用环境执行，不覆盖无关服务。同步源码不包含 `.env*`、`.tools`、虚拟环境、build、backups、签名与 secrets。

复制 `infra/production.env.example` 到服务器私有 `.env.production`，权限600；随机 URL-safe 数据库密码，独立生产卷，域名/证书邮箱/密钥目录。密钥只放 secrets 目录，API/worker 只读挂载；开发演示账户与环境不迁入生产。Web入口公开80/443，SSH另保留维护端口，数据库没有宿主端口。默认 Caddy 提供 HTTPS 和 WebSocket 代理。本次 `8.136.0.78` 使用 `infra/compose.host-proxy.yaml` + 主机 nginx + 实际IP证书，不启动Caddy；通用命令中的 `COMPOSE_FILE` 和CLI `-f`须相应替换。

服务器专用项目目录执行：`CONFIG_FILE=.env.production RELEASE_TAG=实际版本 bash infra/scripts/deploy-local.sh`。脚本验证配置、构建带版本标签的 API 镜像、启动数据库、对已有 schema 备份、迁移、启动 API/worker/Caddy 并检查内部 readiness。随后实际检查 `https://域名/ready`、证书、正式账号双端流程。脚本成功只表明容器启动，不自动满足发布验收。

升级先通过测试/构建和迁移兼容评估，保存上一镜像标签，再执行部署。当前迁移为新增表/字段，应用兼容仍须演练。回滚先停新写入，在兼容 schema 上使用上一个保留的 `miaoban-api:TAG` 镜像启动 API/worker；**不默认 downgrade 数据库**。若 schema 不兼容，先隔离恢复备份并比对，再决定切换，不恢复覆盖唯一生产库。严禁 `docker compose down -v` 操作生产卷。

## 正式账号与维护

激活由维护 CLI 产生一次性令牌：`docker compose --env-file .env.production -f infra/compose.production.yaml exec api python -m app.cli activation`（本次服务器改用`-f infra/compose.host-proxy.yaml`）。令牌仅在安全交付渠道给受邀用户，勿写日志/仓库。用户激活后建立小屋、确认 IANA 时区、邀请另一独立账号；最多两人。恢复密码执行同 CLI 的 `reset-password` 帮助，输入新密码后所有旧会话/设备撤销。CLI 无公开维护 HTTP 接口。

积分不可直接改钱包。`python -m app.cli reconcile` 对账；异常先停受影响写入并保留证据。服务使用 request_id 定位错误，日志不打印认证令牌、密码、DSN 或设备 token。查看 Compose 状态、API/worker 脱敏日志以及 outbox 的 status/error_code/attempts，不把 `provider_accepted` 当用户已读。

## 推送与提醒

iOS：Apple 开发者 App ID、Push Notifications capability、签名/描述文件、APNs .p8/key ID/team ID/topic；设备请求系统权限后由原生桥注册 APNs token。Release entitlement 为 production，调试为 development，服务器 APNS_SANDBOX 必须与包一致。iOS 未经本机 Xcode 编译，后续必须实际编译/真机验证。

Android 当前提供有 GMS 设备的 FCM 实际注册/HTTP v1 适配。将 Firebase Android 公共应用标识放 `apps/mobile/android/push.properties`（参照 example），服务器只放 service-account JSON，客户端不包含服务账户。FCM SDK 锁定官方 BoM35.0.0，采用 [Firebase 手动配置方式](https://firebase.google.com/docs/projects/multiprojects)，版本依据 [官方发布记录](https://firebase.google.com/support/release-notes/android)。无 GMS 手机须按实际品牌选择厂商/聚合推送并完成凭证接入，不能宣称 FCM 已覆盖。

本地按小屋 IANA 时区安排7天、最多60条通知，已完成/暂停/休息日不提醒，免打扰推迟到本地结束时间，减少动画可设置。系统拒绝权限仍可打卡、同步和读收件箱。远程通知包含标识，点击后重新鉴权读取，不信任载荷中的业务状态。outbox 持久化并重试最多8次；配置缺失明确保留状态，失效设备停用，退出撤销旧会话设备。真实前台/后台/进程不活跃推送验收尚未执行。

## 备份、恢复与健康检查

`CONFIG_FILE=.env.production COMPOSE_FILE=infra/compose.production.yaml bash infra/scripts/backup.sh` 生成私有 custom-format dump 和 SHA256，成功后仅对自己格式的备份应用7日/4周保留。`python3 infra/scripts/retention.py` 默认仅显示将删除的旧归档；`--apply` 才执行。备份位于独立目录，不在数据库卷，生产须复制到批准的另一个加密位置。

`BACKUP_FILE=/绝对路径/归档.dump bash infra/scripts/restore-isolated.sh` 先校验同名 .sha256，校验失败不启动恢复；随后以 `--network none` 建立无网络/无外部端口的独立 PostgreSQL 容器，使用容器内Unix socket恢复并检查钱包与流水，差异非零则失败，保留容器供比较。之后对任务、订单、钱包、流水的数量和规范化内容做摘要比对。清理仅针对明确的隔离容器；不覆盖生产库。实际开发演练证据见 verification/restore-comparison.json（26张业务表）。

`CONFIG_FILE=.env.production COMPOSE_FILE=infra/compose.production.yaml PUBLIC_URL=https://域名 bash infra/scripts/healthcheck.sh` 检查 HTTPS、失败推送/配置缺失计数、钱包差异、备份30小时新鲜度和磁盘剩余。配套 systemd service/timer 在确认专用目录后安装，每日备份、每5分钟检查；非零退出写入 systemd failure/journal，接入用户已有告警系统。不通过聊天工具给他人发送消息。

## 手机安装

`make test-e2e`只运行开发双账号`core_flow_test.dart`；`make test-cloud-connectivity DEVICE=测试设备 API_BASE_URL=https://8.136.0.78`只运行云端只读HTTPS测试，不创建生产账号。集成测试构建为调试签名，使用专用测试设备；不得覆盖正式手机上的未同步本地数据。新签名release候选安装与旧调试签名切换见CLOUD_DEPLOYMENT.md。

Android：包名暂定 `com.miaoban.miaoban`，首次正式签名前确认。已有连接云端的0.1.0(2) release候选APK，入口/摘要/新旧签名切换见CLOUD_DEPLOYMENT.md；本机私有签名材料见`.tools/signing/README.txt`，key.properties已生成并被Git忽略。新机器使用用户保管的同一签名密钥，将 key.properties.example 复制到本机私有 key.properties；`make build-android API_BASE_URL=https://域名`，安装 release APK。更新保持同签名、递增 build number；验签用 Android apksigner，记录 SHA256，最终真机安装待验收。

iPhone：安装完整 Xcode/CocoaPods，打开 `apps/mobile/ios/Runner.xcworkspace`，设置团队/Bundle ID/Push capability。先 simulator 编译，再签名 `make build-ios API_BASE_URL=https://域名`，经 TestFlight 或用户已选择的设备分发。未签名构建不能替代可安装包，缺少 Apple 团队时不承诺安装入口。

## 通知本地验证边界与重跑

本地提醒按账号、会话、空间民用日期、权限、偏好与事件序号重排，读取失败保留原排程；只取消任务提醒，退出清除全部通知。UTC/GMT 别名与已接受的未来时区规则已覆盖。Android 在初始化时创建 `partner_events` 与 `task_reminders`，并指定默认远程频道；[FCM 官方频道契约](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages)要求收消息前创建频道。默认锁屏文案不含任务标题或笔记；详情开关明确开启后本地提醒显示标题，APNs/FCM 仅显示简短事件摘要。

Android 集成测试增加 `--dart-define=NOTIFICATIONS_ALLOWED=false/true`，断言实际 OS 权限、原生频道、待排提醒及退出清理。默认 false；切换 true 前需要在已安装的测试应用上授予通知权限。Flutter 测试默认卸载应用，可用 `--no-uninstall` 保留后切换权限；最终应重新构建主程序 APK。测试传输中断的诊断日志不代表通过。主程序在模拟器已经实际完成本地提醒送达和原生点击返回今日，证据见 verification/native-reminder-final-proof.json；真实远程推送、手机省电行为与目标设备通知点击仍须验收。

冷启动先显示“正在恢复账号与小屋…”；会话恢复完成前不提供登录表单，也不处理通知跳转。初始化只执行一次，之后每次登录都重新读取账号与空间。延迟的安全存储结果不能覆盖新账号或登出状态。恢复页已用临时六秒真实开发API响应延迟观察；该观察中间件不在产品内，实验容器已删除，开发服务恢复正常。不要把等待页截图或host故障模拟当作iOS/手机证明。

worker 将缺失/无效本地私钥文件记录为 `configuration_missing`，十分钟后再查，不耗尽外部投递的八次重试额度；已由服务商接受的设备保留 receipt，配置修复后仅投递剩余设备。HTTP 适配器测试拦截网络，不能作为服务商实际接收或设备送达证据。
