# 验收记录

2026-10-09（America/Los_Angeles）；整体未通过。下表分清已验证内容与必须在 Android/iPhone/正式业务补做的验收。业务测试数据来自隔离开发/测试环境，积分通过业务链获得；云端另有初始空生产库部署与恢复证明，没有迁入演示账号或测试业务。

| 条件 | 本地证据 | 整体验收 |
|---|---|---|
| AC01 账号/容量/鉴权 | backend-tests.log：邀请竞争、第三人、跨空间 REST/WS；android-e2e.log 绑定 | 待双正式账号真机 |
| AC02 提议/接受/版本 | API 旧约定保留、拒绝/修改审批测试；模拟器真实接受 | 待双真机全部入口 |
| AC03 10/5/15必做=35/不重领 | PostgreSQL planned fixture 零点前接受任务与5分规则；并发/重试测试 | 待正式验收日期必做演示 |
| AC04 UI p95≤2秒 | http-smoke.json：30次 HTTP开始→WS收到 p95约275ms；仅开发网络 | 待提交→手机界面实测，不能拿WS代替 |
| AC05 离线/重启/跨日 | Flutter持久队列/账号隔离/跨日待审批；offline-proof.json及模拟器停服、force-stop、离线启动、恢复后不重领 | 待两台真机断网/进程重启/跨日 |
| AC06 撤销冲正/永久XP | PostgreSQL 35→冲正→35，负余额、阶段更正，XP不重复；开发手机撤销真实产生待抵扣 | 待双真机 |
| AC07 100兑换70取消恢复 | http-smoke.json 实际100→30→100，重复取消；PostgreSQL并发取消一次退款 | 待双真机 |
| AC08 兑现/确认/库存/快照 | android-e2e.log 完整闭环；并发库存、相同余额、价格快照、取消兑现竞态 | 待双真机 |
| AC09 阶段/赠品/成就一次 | API积分/零价来源订单、已兑现更正、版本奖励差额、5徽章4装饰测试 | 待手机完整目标/赠品/解锁演示 |
| AC10 休息/时区/DST | API UTC/上海/洛杉矶、未来规则、重复小时；Flutter跨DST免打扰、UTC别名与未来接受时区的本地提醒计划 | 待手机提醒与休息页面验证 |
| AC11 通知与深链 | worker缺配置恢复/失效token/退出/重试去重；8项APNs/FCM HTTP模拟契约；提醒跨日/账号隔离与授权跳转控件测试；Android权限拒绝/允许与排程/退出清理；主程序本地提醒在进程退出后实际送达、原生点击返回今日（native-reminder-final-proof.json） | 真机与真正APNs/FCM三种进程状态未验证 |
| AC12 F01–F10真实状态/恢复 | 可运行Flutter四入口，API操作和错误；模拟器设置页退出/恢复余额订单；延迟令牌/存储/同步会话保护；恢复期间无登录表单、恢复失败可重新登录；host连续两账号测试与补强真实init后的Android集成通过（android-e2e-startup-login.log） | 待双端全表单与恢复验收 |
| AC13 两台手机/像素/可读 | 九张Android模拟器截图、360×640字体1.3；另有华为HBN-AL10真机旧预览版六张截图，四主页/空状态/1.15字号/表单/键盘滚动正常，见phone-audit-20261009 | 安卓界面子项已有真机证据；修复版真机复查、iOS截图/第二台硬件与全流程仍待验证 |
| AC14 导出/隔离恢复 | 开发export-dev.json / restore-comparison.json；云端初始生产空库cloud-restore-comparison.json；新增云端有数据隔离验收库cloud-acceptance-restore-proof.json，26表全等、1小屋/3实例/2订单/7流水、账目差异0 | 待正式账号业务数据导出/生产隔离恢复，验收库不能替代正式双真机数据 |

所有 *_test.dart 的 host adapter 用于有界故障模拟，不是产品假数据；integration_test 使用真实 HTTP/PostgreSQL。没有以 SQLite 声称 PostgreSQL 锁语义已验收。远程 provider_accepted 仅表示服务商接收，不是送达/阅读。

本轮云端：实际受信任IP HTTPS、公网ready200/未登录401、Android原生只读连接集成1项、debug主程序构建验签/模拟器安装、证书续期模拟和三个维护timer均有独立证据。没有因此改动 AC01–AC13 的双真机/正式业务未通过状态，见 CLOUD_DEPLOYMENT.md。

用户随后连接安卓手机，安装/启动与既有会话四主页可达已通过真实USB ADB独立检查；设备型号/兼容系统版本、实际旧预览包摘要与签名已读取，见phone-audit-20261009/device-proof.json、AUDIT.md及latest-device-dependency-audit.json。此次未更新应用、提交激活/登录、创建约定或执行业务/通知验收，不能扩张为AC13双手机或全部真机验收通过。
