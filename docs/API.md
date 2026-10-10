# 喵伴 API

由本地实际服务 `/openapi.json` 生成，前缀 `/api/v1`。鉴权采用 Authorization: Bearer 短期 opaque 令牌，刷新单独轮换；客户端不能提交应获积分。时间 ISO8601，日界线由小屋 IANA 时区决定。

领域变更必须 Idempotency-Key（8–100字符），同键不同载荷409。记录和订单命令带 expected_version；笔记改动也递增版本。鉴权/设备注册/已读等收敛操作遵循自身会话或最终状态语义。具体字段与约束见 [OpenAPI](openapi.json)。

列表支持 offset/limit（events 为 after_seq/limit），snapshot 是一致状态与 snapshot_seq；WS 为 `/api/v1/spaces/{sid}/ws`，只接受鉴权 Header，连接后发送 `{ "after_seq": 整数 }`。连接失效/游标超前时重新鉴权和拉快照。

错误为 code/message/request_id；消息可直接显示中文，输入/密钥/连接串不回显。登录/激活422另含已知字段的field_errors（username/password/token/nickname）与fields路径，message包含可操作的字段规则；未知字段名也不回显。账号3–80位ASCII英文字母/数字/_.@-，密码10–128字符，激活码20–128字符，昵称1–40字符且可用中文；首尾空格按既有服务端规则裁剪。兑换确认价格须与服务端相同；负净余额可来自更正，可用余额最低0，不允许透支兑换。

响应契约：登录/刷新返回 access_token、refresh_token；令牌是 opaque 值。auth/me 返回用户、preferences 和已授权 spaces。

| 读取结果 | 关键字段与语义 |
|---|---|
| snapshot | space（space/config/members/today）、daily、wallet、rewards、orders、growth、rest_dates、latest_partner_event、snapshot_seq；空间锁内取得，游标与状态一致 |
| daily | plans和instances；实例含date、user_id、task_id、title、standard、points、required、completed、version、note；当天新加任务选做，必做基于零点版本 |
| wallet | balance为账目净和，available=max(0,balance)，debt=max(0,-balance)；更正可产生待抵扣，消费不能透支 |
| growth | permanent_xp、level、decorations、achievements为永久纪念；stats/calendar来自当前有效完成事实 |
| event | seq、id、actor_id、type、entity_id、entity_version、created_at；客户端不直接加分，重拉snapshot处理提示 |
| orders | 价格/奖品描述快照、reward_id、milestone_id、status、version、ever_fulfilled；阶段赠品价格0，兑现事实阻止更正后再次交付 |
| export | schema_version、exported_at、snapshot_seq及领域记录；不含认证凭证、设备token或推送秘密 |

空间资源每次检查成员；任务/奖励/目标命令按提议者、执行者、提供者、领取者分别授权。notification ID 必须属于当前用户且仍可访问其空间。私密激活由维护CLI提供；登录10次失败/15分钟限流，正式模式拒绝不安全示例配置。

| 方法 | 路径 | 操作 |
|---|---|---|
| POST | `/api/v1/auth/activate` | Activate |
| POST | `/api/v1/auth/login` | Login |
| POST | `/api/v1/auth/logout` | Logout |
| GET | `/api/v1/auth/me` | Me |
| POST | `/api/v1/auth/refresh` | Refresh |
| POST | `/api/v1/devices` | Register Device |
| POST | `/api/v1/invitations/claim` | Claim |
| GET | `/api/v1/notifications` | Notifications |
| GET | `/api/v1/notifications/{nid}` | Notification Detail |
| POST | `/api/v1/notifications/{nid}/read` | Read Notification |
| PUT | `/api/v1/preferences` | Preferences |
| POST | `/api/v1/spaces` | Create Space |
| GET | `/api/v1/spaces/{sid}` | Space Info |
| GET | `/api/v1/spaces/{sid}/corrections` | Correction List |
| POST | `/api/v1/spaces/{sid}/corrections/{cid}/decision` | Correction Decision |
| GET | `/api/v1/spaces/{sid}/daily` | Daily |
| GET | `/api/v1/spaces/{sid}/events` | Events |
| POST | `/api/v1/spaces/{sid}/events/{eid}/reactions` | React |
| GET | `/api/v1/spaces/{sid}/export` | Export |
| GET | `/api/v1/spaces/{sid}/growth` | Growth Info |
| POST | `/api/v1/spaces/{sid}/instances/{iid}/checkin` | Checkin |
| POST | `/api/v1/spaces/{sid}/instances/{iid}/corrections` | Correction |
| POST | `/api/v1/spaces/{sid}/instances/{iid}/note` | Note |
| POST | `/api/v1/spaces/{sid}/invitations` | Invite |
| POST | `/api/v1/spaces/{sid}/invitations/{iid}/revoke` | Revoke Invite |
| GET | `/api/v1/spaces/{sid}/ledger` | Ledger |
| POST | `/api/v1/spaces/{sid}/milestone-versions/{vid}/decision` | Decide |
| GET | `/api/v1/spaces/{sid}/milestones` | Goals |
| POST | `/api/v1/spaces/{sid}/milestones` | Goal Create |
| POST | `/api/v1/spaces/{sid}/milestones/{gid}/confirm` | Goal Confirm |
| POST | `/api/v1/spaces/{sid}/milestones/{gid}/decision` | Goal Decision |
| POST | `/api/v1/spaces/{sid}/milestones/{gid}/evidence` | Evidence |
| GET | `/api/v1/spaces/{sid}/milestones/{gid}/versions` | Versions |
| POST | `/api/v1/spaces/{sid}/milestones/{gid}/versions` | Propose |
| POST | `/api/v1/spaces/{sid}/nudge` | Nudge |
| GET | `/api/v1/spaces/{sid}/orders` | Orders |
| POST | `/api/v1/spaces/{sid}/orders/{oid}/command` | Order Command |
| POST | `/api/v1/spaces/{sid}/rest-dates` | Rest |
| GET | `/api/v1/spaces/{sid}/rewards` | Reward List |
| POST | `/api/v1/spaces/{sid}/rewards` | Reward Create |
| PUT | `/api/v1/spaces/{sid}/rewards/{rid}` | Reward Edit |
| POST | `/api/v1/spaces/{sid}/rewards/{rid}/redeem` | Redeem |
| POST | `/api/v1/spaces/{sid}/rules` | Propose Rule |
| POST | `/api/v1/spaces/{sid}/rules/{rid}/decision` | Rule Decision |
| GET | `/api/v1/spaces/{sid}/snapshot` | Snapshot |
| POST | `/api/v1/spaces/{sid}/task-versions/{vid}/decision` | Task Decision |
| GET | `/api/v1/spaces/{sid}/tasks` | Task List |
| POST | `/api/v1/spaces/{sid}/tasks` | Task Create |
| POST | `/api/v1/spaces/{sid}/tasks/{tid}/schedule` | Schedule |
| POST | `/api/v1/spaces/{sid}/tasks/{tid}/versions` | Task Edit |
| GET | `/api/v1/spaces/{sid}/wallet` | Wallet |
| GET | `/api/v1/spaces/{sid}/wishes` | Wishes |
| POST | `/api/v1/spaces/{sid}/wishes` | Wish Create |
| POST | `/api/v1/spaces/{sid}/wishes/{wid}/decision` | Wish Decision |
| GET | `/health` | Health |
| GET | `/ready` | Ready |
