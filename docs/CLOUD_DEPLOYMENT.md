# 喵伴本次云端部署与试装

记录日期：2026-10-08（America/Los_Angeles）。服务器日志使用 UTC 或服务器 CST，具体以证据字段为准。此记录证明实际部署、Android release签名与候选安装入口，不代表双真机、真实推送或整体 Goal 已通过。

## 服务与安装入口

- 阿里云实例 `i-bp1ieen4obk0v9io0ndi`，Ubuntu 24.04 x86_64，SSH `root@8.136.0.78`；专用目录 `/srv/miaoban`。
- API：`https://8.136.0.78/api/v1`；[健康检查](https://8.136.0.78/ready)，[本地接口说明](API.md)（生产环境关闭交互文档）。App 的 `API_BASE_URL` 为 `https://8.136.0.78`，客户端自行添加 `/api/v1`。
- [安卓 release 候选包](https://8.136.0.78/downloads/miaoban-android-release.apk?v=3)：当前0.1.1(3)，AOT release，62097836字节（约62MB），连接生产HTTPS，最低Android API24；保持0.1.0(2)原release签名。构建、v2验签、模拟器覆盖安装、公网HEAD/Range通过，仍未完成双真机、推送及整体发布验收。
- release SHA256：`fe72acf384d84fc33b24d2c8df551b759570d085ac8ec01472dea7fc8a2c1b74`。本机`.tools/miaoban-android-release-v3.apk`，最新证据`verification/auth-fix-android-artifacts.json`。源码`0.1.1+3`；历史v2文件已另存，不重标旧验收。
- 私有签名目录 `.tools/signing`（0700）含 `miaoban-release.p12` 与 `store-password.txt`（均0600），另有迁移说明。Android `key.properties` 0600且被Git忽略。请保管该目录的加密备份；这些文件没有上传服务器。签名材料元信息 `verification/android-release-signing-material.json` 不记录密码。
- 若已安装先前调试包，两个签名不同，不能直接覆盖。先联网同步待提交操作，再卸载调试包并安装release候选包，重新登录恢复服务器记录。模拟器已先将调试数据保存在本机私有`.tools/emulator-debug-data-before-release.tar`后切换。新用户直接安装release候选包。
- [同签名安卓preview更新](https://8.136.0.78/downloads/miaoban-android-preview.apk?v=3)：当前0.1.1(3) debug，186647218字节，SHA256`034783b4d0c5189417b11e317b92c95b0546a5150691ece293c2e7a35ab08af2`。保持原preview调试证书，已经安装preview的用户可直接覆盖，无需切换签名。旧v1副本本机`.tools/miaoban-android-preview-v1.apk`及服务器私有incoming目录保留，原证据维持历史范围。
- iPhone 安装仍需完整 Xcode、Apple 团队、应用标识和已选择分发方式；没有生成可安装 iPhone 包。

## 正式激活

两枚一次性激活码只存本机忽略、0600 的 `.tools/miaoban-activation-codes.txt`。各自24小时有效；准确时间见私密文件和脱敏记录 `verification/cloud-activation-delivery.json`。不要把文件提交仓库、上传网站或粘贴公共渠道。

每人使用一枚，在 App 激活页自行设置用户名、昵称与密码。首位用户创建小屋并确认 IANA 时区，再创建邀请供另一独立账号认领。激活码和小屋邀请用途不同；没有预置正式用户密码，也没有把 demo 账号迁入生产。

失效后维护者在服务器安全终端重新产生：

```bash
cd /srv/miaoban
docker compose --env-file .env.production -f infra/compose.host-proxy.yaml exec api python -m app.cli activation
```

不要将该命令输出写入日志。正式账号、双端绑定与业务验收尚未执行。

## 实际部署与维护

Compose 项目 `miaoban-production` 运行独立数据库、API、worker。当前镜像 `miaoban-api:20261008-auth01`、`postgres:18.3-alpine`（初次部署API为20261008-ip01，保留可回切镜像），均为实际导入并核对摘要的 linux/amd64 镜像。服务器 Docker Hub 不可达，因此本机导出镜像并通过已认证 SSH 上传；没有使用演示数据库或口令。原始源码/镜像归档摘要见 `verification/cloud-release-manifest.json`，后续运维补充文件另有最终部署清单。

主机 nginx 负责80/443；API只发布到 `127.0.0.1:18000`，PostgreSQL没有宿主端口。HTTP固定重定向到本IP HTTPS，ACME challenge保持可读；APK只开放明确的静态下载路径，私有部署目录不对网站公开。系统信任库和IP主机名验证通过；没有使用 `curl -k` 或自签证书。当前 Let's Encrypt IP SAN 证书到期 `2026-10-15T17:49:28Z`，Certbot5.8.0已完成续期模拟，实际证据见 `cloud-certificate-renewal-dry-run.log`。

已启用：`miaoban-backup.timer` 每日备份、`miaoban-health.timer` 每5分钟巡检、`miaoban-ip-tls-renew.timer` 每12小时检查续期。首次服务运行均成功。安装的 backup/health service 使用 `infra/compose.host-proxy.yaml`，其余项目默认 Caddy 部署示例仍保留。查看/手动运行：

```bash
systemctl list-timers --all 'miaoban-*'
systemctl start miaoban-health.service
journalctl -u miaoban-health.service --since today
systemctl start miaoban-backup.service
systemctl start miaoban-ip-tls-renew.service
```

健康检查包含公网HTTPS、失败/缺配置推送计数、钱包流水一致性、备份30小时新鲜度和2GiB剩余磁盘。失败留在 systemd/journal；尚无外部通知告警渠道。云端 `PUSH_PROVIDER=disabled`，尚未提供APNs/FCM/厂商凭证，不能声称真实系统推送送达。

升级使用本项目 host-proxy Compose：

```bash
cd /srv/miaoban
CONFIG_FILE=.env.production COMPOSE_FILE=infra/compose.host-proxy.yaml PREBUILT_IMAGES=1 RELEASE_TAG=已导入且校验的版本 bash infra/scripts/deploy-local.sh
```

只有新版本镜像已导入时使用 `PREBUILT_IMAGES=1`。部署前保留上一镜像和数据库备份；不默认 downgrade数据库，不执行 `down -v`。初次部署时没有旧喵伴版本；认证修复已真实升级且保留原镜像/私有配置备份，尚未实际回切进行回滚兼容演练。

## 备份恢复与旧项目清理

初始生产备份 `/srv/miaoban/backups/miaoban-20261009T024728Z.dump` 校验后实际恢复到 `miaoban-restore-20261009024729`，网络 `none`，无对外端口；26张业务表规范化摘要与数量完全相等，钱包流水差异0。此时全部业务表为空，所以只证明初始生产结构和恢复链，正式任务/钱包/订单数据须用户开始使用后再验收。恢复容器已停止保留，未覆盖生产库；激活码生成后另已运行新备份。异地加密副本和外部告警仍待用户现有目的地/渠道。

用户后续明确授权删除废弃 OrgMesh；已删除它的服务、私有环境配置、nginx站点、项目数据和旧归档，包括最初为保留旧站生成的配置副本。旧8787端口关闭，相关顶层命名路径无残留，共享nginx主配置摘要不变，`rootjourney_mongo-data` 等无关卷保留。证据 `cloud-orgmesh-removal-proof.json`；之前的 ACME 保留旧站记录为历史事实。

## 尚未通过

安卓签名已经补齐。仍待正式双账号绑定、Android/iPhone真机全业务验收、iOS构建分发、真实推送、手机UI同步延迟、正式业务数据备份恢复、加密异地副本、外部告警与升级回滚。缺项不由本次云端试装替代。

## 新增独立云端验收演练

`/srv/miaoban-acceptance` 使用独立数据库`miaoban_acceptance`/独立卷/随机私有口令，dev账号只在这里。API只绑定127.0.0.1:18001，认证SSH隧道连接；不通过网站公开。真实任务/阶段奖励赚取100，兑换70、重复取消恢复100，另一订单兑现/确认后余额30；30样本HTTP开始→WS p95约350ms，不是手机UI延迟。API实际重启后26表不变，重新登录恢复余额和订单。

有数据pg_dump在`network none`容器恢复后，26表摘要与数量全等（1小屋、3任务实例、2钱包、7流水、2订单），钱包差异0。证据 `cloud-acceptance-http-smoke.json` / `cloud-acceptance-relogin-proof.json` / `cloud-acceptance-restore-proof.json`。验收服务和恢复容器已停止保留，隧道已关闭，生产服务继续运行。该演练仍不能代替正式用户生产数据AC14。

## 激活表单修复

App旧版只检查最小长度，服务端ASCII账号及最大长度拒绝时缺少具体原因。当前API对登录/激活422响应返回已知字段的脱敏field_errors，message也包含具体规则，现有App无需更新即可显示；不回显凭证或未知字段名。App0.1.1(3)对齐校验并去掉粘贴时的首尾空格，账号不接受中文/内嵌空格，昵称可用中文。激活已成功而登录失败时改为直接重试登录，不再次激活。两枚原激活码没有因验证被消耗；部署前已自动备份，数据库结构无变化。当前真实用户登录结果仍未独立验证。
