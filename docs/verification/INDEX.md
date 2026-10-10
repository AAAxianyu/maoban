# 验证证据索引

日期2026-10-08（America/Los_Angeles）；macOS Apple Silicon、本地 Docker PostgreSQL、Android API36 ARM64模拟器；本轮新增阿里云Ubuntu x86_64实际部署（证据UTC为10月9日）。整体 Goal 尚未完成。证据只支持各自环境及命令所验证的事实。

2026-10-09新增安卓硬件证据：`phone-audit-20261009/AUDIT.md`、`device-proof.json`、六张编号原生截图及XML、`installed-signature.log`。华为HBN-AL10/API31，1260×2844、540dpi、字体1.15；安装的是0.1.0(1)旧debug预览包，完整APK摘要与原预览包匹配。既有会话四主页可达，表单与键盘滚动正常；没有重新激活/登录、提交业务、更新或卸载。与新preview同签名、与release不同签名已核验；修复版和双端业务/推送仍待真机验收。

| 证据 | 实际验证 | 范围与限制 |
|---|---|---|
| backend-tests.log | `.venv/bin/ruff check app tests` 与 `.venv/bin/pytest`：39项通过（31业务/worker、8 HTTP适配器模拟） | 隔离真实PostgreSQL；一条Starlette弃用警告 |
| flutter-analyze.log / flutter-tests.log | `flutter analyze`无问题；`flutter test`30项通过，含恢复期间不显示登录表单、两次账号登录、延迟存储会话保护 | Host故障模拟与控件测试，不是硬件行为 |
| android-e2e-denied.log / android-e2e-allowed.log / notification-native-proof.json | 同一真实后端用例在 OS 权限 false/true 两轮通过，频道/原生待排提醒/退出清理也断言通过 | 前一版本 Android 模拟器权限/排程证据；实际送达另见下行；android-e2e.log 为更早核心流程记录 |
| android-e2e-startup-login.log / android-final-main-proof.json | 当前登录修正后补强真实后端集成：保存会话后实际init，再完成双账号流程、退出、重新登录恢复同小屋/余额5/完成订单，1用例通过 | Android模拟器、OS通知允许；最终主程序重建/安装与集成测试APK分开记录 |
| native-reminder-tap-proof.json / native-reminder-final-proof.json | 主程序真实 AlarmManager 提醒在应用进程退出后送达；系统通知点击返回今日，钱包5与XP1不变；后一次恢复期间无登录框 | 两次均为 Android 模拟器本地提醒，APK摘要分别记录；非精确提醒本次延迟22.5秒/76.019秒，不能推广为真机时限或APNs/FCM证明 |
| notification-tap-tests.log | 3项控件测试：冷启动按授权通知ID查阅/已读/跳转、旧账号提醒隔离、本地提醒返回今日 | Dart路由与HTTP模拟，不是原生通知点击证据 |
| android-build.log / android-apk-signature.log / android-apk.sha256 | 主程序调试APK构建、调试签名与摘要 | 非用户release签名；地址只适用于模拟器 |
| http-smoke.json | `scripts/smoke.py`真实100→30→100→30；30次HTTP开始到WS接收p95约275ms | 不代表提交到另一台手机UI的AC04 |
| offline-proof.json | `scripts/offline_proof.py before/after/repeat`与实际adb打卡、force-stop、离线启动 | API停服；净余额−50→30，经验3不重复；截图来自最后会话修正前的相同队列代码；真机和跨日仍待验收 |
| reconnect-proof.json | `scripts/reconnect_proof.py`：断开时写事件、重启API后游标恢复，已确认游标不回放 | 本地WS；不是手机界面延迟或推送 |
| restore.log / restore-comparison.json / restore-isolation.json | pg_dump→SHA256→独立PostgreSQL恢复；`scripts/restore_proof.py`对26张业务表内容摘要与计数一致，之后断开bridge验证Unix socket | 18:03 UTC开发快照；钱包与流水差异0；容器无网络并保留；云端独立证据另见下表 |
| retention-proof.json | 临时目录验证dry-run、7日/4周保留与只清理自有过期归档 | 外部文件、symlink保留；未清理用户备份 |
| healthcheck-proof.json | 临时命令fixture健康退出0、失败推送退出1 | 不是阿里云健康监控或告警送达 |
| production-config-proof.json | 历史本地Compose config与生产HTTPS/密码守卫 | 当时未启动生产容器；实际云端部署另见下表 |
| visual-review-android.md / visual-verdict-android.md | 独立reviewer对六项视觉/行为修正全部resolved，disposition ship | 只评分Android模拟器指定捕获，不扩张为全产品通过 |
| visual-review-startup-android.md | 新增恢复页和恢复后今日捕获独立复核，disposition ship；登录初始化回归已修正并由host测试覆盖 | 只覆盖 Android 模拟器启动状态，不扩张原 F1–F6 或整体验收 |
| external-dependencies-audit.json | 第三轮历史记录仅有模拟器、完整Xcode缺失、正式配置/签名/推送配置/远端未提供 | 本轮服务器已补齐；历史依赖事实不能作为真机或生产验收 |

| 云端证据 | 实际验证 | 范围与限制 |
|---|---|---|
| cloud-release-manifest.json / cloud-deployment.log / cloud-final-deployment-proof.json | amd64镜像/源码上传摘要、迁移、API/db/worker健康、最终运维补充文件与监听/维护状态 | 阿里云真实生产部署；正式双账号业务未执行 |
| cloud-public-https-proof.json | 系统信任库/IP验证；ready/health200、未登录API401 | 没有绕过TLS验证；不是手机业务验收 |
| cloud-certificate-issue.log / cloud-certificate-renewal-dry-run.log / cloud-maintenance-proof.json | 实际IP证书签发、续期模拟通过、三维护timer启用且首跑成功 | 续期模拟不替换当前正式证书；失败留journal，外部告警未接入 |
| cloud-backup-restore.log / cloud-restore-comparison.json | 阿里云dump校验、network none恢复、26张业务表数量/规范化摘要全等、钱包差异0 | 初始生产业务表全为空，不能视作正式订单/余额恢复通过；恢复容器已停止保留 |
| cloud-orgmesh-removal-inventory.json / cloud-orgmesh-removal-proof.json | 按用户授权删除旧OrgMesh服务、站点、私有环境、项目/数据/旧归档；8787关闭；主nginx配置摘要与无关卷保留 | 只删除已核对的OrgMesh路径；更早cloud-nginx-acme-proof.json是保留旧站的历史阶段 |
| cloud-activation-delivery.json | 两枚24小时一次性激活码只存本机忽略0600文件，生成后另备份 | 不记录令牌明文，未预置正式账号；用户激活/绑定待验收 |
| android-cloud-connectivity.log / flutter-analyze-cloud.log | 原生Android真实Dio/API连接IP HTTPS，ready200/未登录401；新增测试后分析无问题 | 1项只读集成；模拟器、不写生产业务数据 |
| android-cloud-preview-proof.json / android-cloud-apk-signature.log / android-cloud-install.log / cloud-preview-publish-proof.json / cloud-preview-download-proof.json | 云端主程序debugAPK构建、v2验签、模拟器安装、服务器文件摘要与公网HEAD/Range验证 | 开发签名，非正式release、非真机；下载258658356字节，未重复下载全包 |
| android-release-signing-material.json / android-cloud-release-proof.json / android-cloud-release-signature.log / android-cloud-release-install.log / android-cloud-release-download-proof.json / cloud-release-publish-proof.json | 本机私有RSA3072签名材料、0.1.0(2) AOT release候选62097836字节、v2验签、模拟器安装/登录与激活入口、公网下载 | 未上传签名私钥；真机/推送/整体发布未通过；旧debug证据保持原范围 |
| cloud-acceptance-provision-proof.json / cloud-acceptance-http-smoke.json / cloud-acceptance-relogin-proof.json | 同一部署镜像、云端独立库、三任务/阶段奖100→兑换30→重复取消100→兑现确认30、实际重启后登录恢复、30样本WS p95约350ms | 只在dev隔离验收库，经SSH回环隧道；不是手机UI p95或生产正式业务 |
| cloud-acceptance-restore-proof.json / cloud-acceptance-stop.log | 有数据云端备份校验/network none恢复、26表内容全等，1小屋/3实例/2钱包/7流水/2订单、账目差异0；已停止保留 | 非正式双真机生产AC14；源验收服务/恢复容器停止，临时隧道关闭 |

截图 `screenshots/android-login.png`、`android-today.png`、`android-room.png`、`android-rewards.png`、`android-growth.png`、`android-settings.png`、`android-settings-bottom.png` 均为稳定实际界面；`android-small-130.png` 为360×640 logical、字体1.3，展示未完成长标题与打卡控制；`android-today-event.png`为今日页下方真实TA动态。场景数据来源与隔离说明在visual-fixture.json。

`android-offline-pending.png`与`android-offline-restarted.png`均展示离线待同步且不发分；`android-offline-reconnected.png`展示恢复后的实际余额。`android-undo-dialog.png`是早期失败定位捕获，**不作为任何验收证据**。window.xml仅用于native语义定位。

`android-native-reminder-notification.png`与`android-native-reminder-cold-tap.png`来自第一次实际本地提醒点击。第二次的`android-native-reminder-final-delivered.png`是系统已送达通知；`native-startup-restoring.xml`与`native-reminder-final-after.xml`分别记录点击后恢复页和今日语义。`android-startup-restoring.png`/`android-startup-restored.png`在同APK冷启动重拍，使用六秒真实开发API延迟观察恢复过程；首次过早的空白PNG已弃用，未作为证据。`android-reminder-target-visible.png`是恢复后滚动查看零积分任务。临时延迟容器已移除，原API恢复健康。各原生证明的APK摘要保持原值，不冒充之后登录修正的最终APK。

`android-notification-diagnostic.png` 是测试启动停顿的诊断截图，`android-e2e-allowed-startup-failed.log` / `android-e2e-allowed-transport-failed.log` 是被中断的测试尝试，均不计入通过。工具安装/下载失败与旧日志保留作追溯，不能把其标题或文件存在当作通过。GitHub CI配置已保存但未执行；iOS编译、两台真机、真实推送、正式签名与正式业务数据恢复仍未验收。IP HTTPS和初始生产恢复已有上述云端证据。外部输入与下一步见[实施状态](../IMPLEMENTATION_STATUS.md)。

## 激活/登录格式修复证据

- `auth-fix-backend-tests.log`：49项真实隔离PostgreSQL/适配器测试通过；新增10项认证校验、脱敏、粘贴输入与一次性码恢复。`auth-fix-mobile-analyze.log`无问题，`auth-fix-mobile-tests.log`37项控件/host测试通过，新增7项表单与激活后重试回归。
- `auth-fix-release-manifest.json` / `auth-fix-cloud-deployment.json` / `auth-fix-public-https-proof.json`：实际新镜像导入、备份与切换，生产ready200；422明确字段规则、400指引已有账号登录。没有测试生产账号和正式激活码消耗，结构无变更。
- `auth-fix-android-artifacts.json` / `auth-fix-*-signature.log` / `auth-fix-release-install.log`：0.1.1(3)两个APK分别与对应旧版同签名，release模拟器原位覆盖成功。旧preview-v1/release-v2副本保留，旧日志的稳定本机路径不再指向旧文件，应以各自摘要和版本归档为准。
- `auth-fix-cloud-apk-publish.json` / `auth-fix-public-apk-proof.json`：服务器核对完整SHA256后原子替换两个公开固定路径，nginx配置不变；公网HEAD200与Range206、64字节匹配。没有重复下载全包。
- `screenshots/auth-fix-phone-login.png` / `auth-fix-phone-errors.png` / `auth-fix-small-errors-*.png`：实际API36 Android release界面，正常/字段错误、360×640 logical及1.3字号，输入与按钮可通过滚动访问。其余历史截图不扩张为本版本证据。

用户在真机报告“激活并登录”报错；本轮修复不等同于其真机激活/登录已成功。

- `auth-fix-native-proof.json` / `auth-fix-native-https.log` / `screenshots/auth-fix-native-https-error.png` / `auth-fix-landscape-https-error.png`：release模拟器真实生产HTTPS提交无效fixture激活码，显示具体恢复提示，原账号输入保留；横屏底部操作可滚动访问。夜间系统标志下维持已定奶油主题。fixture不创建正式账号，设备尺寸/字号/夜间标志已恢复。
