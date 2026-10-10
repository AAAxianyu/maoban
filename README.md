# 喵伴

Flutter Android/iPhone 双人学习约定 App：像素猫咪自习室、任务审批与打卡、个人小鱼干、奖励兑现、共同成长。FastAPI + PostgreSQL 为事实源，SQLite 持久保存手机待同步操作。

持续 Goal 已创建，核心功能已有可运行实现，并完成本地验证：49项后端测试（41项PostgreSQL业务/worker/认证、8项推送HTTP模拟契约）、44项Flutter测试、Android模拟器真实后端集成/初始化后退出恢复、系统本地提醒送达/点击，以及26张业务表备份恢复比对。阿里云后端现已部署至 `https://8.136.0.78`，受信任 IP 证书、独立生产库、定时维护和初始生产隔离恢复已有证据；按用户指令删除了废弃 OrgMesh。Android 云端试装包另有原生 HTTPS 连接证明。Android已追加私有签名的0.1.1(3) release候选包及云端有数据隔离恢复；iOS、双真机、真实推送及正式业务数据恢复仍未验收，当前不作为正式发布使用。

- [实施状态](docs/IMPLEMENTATION_STATUS.md)：实际进度、证据和缺项。
- [运行手册](docs/RUNBOOK.md)：开发、部署、激活、推送、签名、备份与恢复。
- [验收记录](docs/ACCEPTANCE.md) / [发布清单](docs/RELEASE_CHECKLIST.md)。
- [产品设计](DESIGN.md) / [开发契约](DEVELOPMENT.md) / [Goal](GOAL.md)。
- [接口](docs/API.md) / [素材来源](docs/ASSETS.md)。
- [实际移动设计](docs/MOBILE_DESIGN.md) / [验证证据索引](docs/verification/INDEX.md)。
- [本次云端部署与试装](docs/CLOUD_DEPLOYMENT.md)：地址、安装入口、私密激活方式及维护命令。

本地入口：`make doctor`、`make setup`、`make dev-up`、`make seed-demo`、`make verify`。测试数据库与开发/生产严格分开；详情和首次 SDK 安装看运行手册。

源码：`apps/mobile`、`services/api`；部署/维护：`infra`；实际日志/截图：`docs/verification`。密钥、签名、数据库和生成构建不提交。

GitHub 仓库：[AAAxianyu/maoban](https://github.com/AAAxianyu/maoban)。推送与拉取请求仅自动运行分析和测试；如需构建 Android APK 与 iOS 模拟器版本，在 Actions 的 `verify` 工作流中手动运行并勾选 `build_checks`。

激活/登录格式提示已修复并部署：旧App立即获得具体字段提示；新版0.1.1(3)对齐账号、密码、激活码校验并保留输入，激活成功后的登录重试不会重复消耗激活码。旧preview安装使用[同签名preview更新](https://8.136.0.78/downloads/miaoban-android-preview.apk?v=3)，旧release安装使用[同签名release更新](https://8.136.0.78/downloads/miaoban-android-release.apk?v=3)。
