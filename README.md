# sparkler-accountcenter

Sparkler AccountCenter 公共游戏平台的官方 Ruby SDK。模块命名空间 `Sparkler::AccountCenter`。

零运行时依赖（仅 Ruby 标准库：`net/http` / `json` / `openssl` / `securerandom` / `base64`，其中 `base64` 自 Ruby 3.4 起为 bundled gem，已在 gemspec 声明）。要求 Ruby ≥ 3.1。

SDK 只封装认证、幂等键、错误分类与重试/轮询、Webhook 验签与游戏票据验签——**不封装任何游戏规则**：输赢判定、奖励计算、费用策略由游戏服务端负责并写入结算单 `details` 审计。

## 安装

```ruby
# Gemfile
gem "sparkler-accountcenter", path: "sdks/accountcenter-ruby"   # 仓库内引用
```

## 快速开始：三种凭证模式

### 1. 游戏服务端（client_credentials + funds scope）— holds / settlements / balances

```ruby
require "sparkler/accountcenter"

platform = Sparkler::AccountCenter::Client.new(
  base_url: ENV.fetch("PLATFORM_API_URL"),   # 如 https://api.example.com
  client_id: ENV.fetch("PLATFORM_CLIENT_ID"),
  client_secret: ENV.fetch("PLATFORM_CLIENT_SECRET"),
  scope: "funds"                              # 默认值
)

# 按动作预占（复活扣费等）：action_id 即幂等键，结果未知重试沿用同一值
hold = platform.holds.create(user: "9f1c2e-…", amount: "50", action_id: "revive:round7:u1")
platform.holds.execution(hold.id)                       # reserved → executing
result = platform.holds.capture(hold.id)                # executing → captured
result.ledger_transaction.reference                     # 扣款交易摘要

# 轮末结算：同游戏同 reference 业务级幂等，重复提交返回原单
settlement = platform.settlements.create(
  user: "9f1c2e-…", amount: "120", reference: "reward-42",
  details: { protocol: "my-game-settlement/v1", roundNo: 7 }
)
final = platform.settlements.wait_for("reward-42")      # 轮询至 posted / rejected
if final.state == "rejected"
  # reject_reason: asset_not_allowed / insufficient_reward_budget / …
  # 平台不自动冲正：修正后须用新 reference 开新单
end

# 开局批量拉权威余额（自动按 100 分批合并）
balances = platform.balances.get(%w[9f1c2e-… user:7 0xabc…])  # => { "player" => "120.5", … }
```

### 2. 用户接口（Bearer 用户 JWT / guest_token）

```ruby
# 游客领票（无需任何凭证）：60 秒 RS256 ticket + 30 天 guest_token
public_client = Sparkler::AccountCenter::Client.new(base_url: ENV.fetch("PLATFORM_API_URL"))
guest = public_client.game_tokens.guest
guest.ticket        # 连接游戏服务器用（jti 一次性，每次连接/重连重新领取）
guest.guest_token   # 持久化；之后以 Bearer 身份换票

# 游客原地升级为正式用户（昵称/余额/游戏记录继承）
public_client.auth.sign_up(username: "alice", password: "s3cret",
                           guest_token: guest.guest_token)

# 已登录用户
user_client = Sparkler::AccountCenter::Client.new(base_url: base_url, bearer_token: user_jwt)
user_client.me.get
user_client.me.update(nickname: "Alice", flag_style: "red")
user_client.game_tokens.create                # Bearer JWT 换 60s 游戏 ticket
user_client.withdrawals.list
user_client.withdrawals.create(amount: "100", dest: "0x已验证钱包地址")
user_client.event_logs.list(round_id)
```

SIWE 钱包登录/绑定的完整流程（三处入口契约一致）：

```ruby
challenge = public_client.game_tokens.challenge(address: "0xabc…", chain_id: 84532)
# => { "message" => "…EIP-4361 文本…", "ticket" => "…不透明防伪票据…" }
signature = wallet_sign(challenge["message"])          # 钱包签的是 message 字段

# 任选其一，提交的都是 { ticket, signature }（ticket 原样回传，不是 message）：
public_client.game_tokens.create_with_siwe(ticket: challenge["ticket"], signature:)  # 直接换游戏票据
public_client.auth.wallet(ticket: challenge["ticket"], signature:)                   # 登录/注册 → { token, user, game_token }
user_client.me.create_address(ticket: challenge["ticket"], signature:)               # 已登录用户绑定钱包
```

### 3. Webhook 接收（验签）与游戏票据验签

```ruby
# Webhook：平台 POST 原始事件 JSON + 4 个头
verifier = Sparkler::AccountCenter::WebhookVerifier.new(secret: ENV.fetch("PLATFORM_WEBHOOK_SECRET"))

post "/webhooks/platform" do
  raw = request.body.read
  event = verifier.verify!(
    raw_body: raw,
    timestamp: request.env["HTTP_X_TIMESTAMP"],
    signature: request.env["HTTP_X_SIGNATURE"]
  )
  # 幂等去重（delivery 至少投递一次，允许乱序/重复）：
  delivery_id = request.env["HTTP_X_DELIVERY_ID"]
  return 200 if seen_before?(delivery_id)
  remember(delivery_id)

  # event: event_id / event_type / aggregate_version / data（金额一律字符串）
  handle(event)
  status 200          # 处理成功才 2xx ack；否则非 2xx 让平台重试
rescue Sparkler::AccountCenter::WebhookVerificationError
  status 401
end

# 游戏票据（RS256，60s TTL）：拉 JWKS 验签 + iss/aud/exp 校验 + jti 防重放
tickets = Sparkler::AccountCenter::TicketVerifier.new(
  jwks_url: "#{base_url}/api/v1/game/jwks.json",
  issuer: ENV.fetch("PLATFORM_ISSUER"),
  audience: "my-game"
)
claims = tickets.verify!(socket_handshake_token)
claims.player_id  # 或 claims.sub（平台用户 UUID）/ claims.balance（十进制字符串）
```

## 幂等与重试规则

| 端点 | 默认 Idempotency-Key | 规则 |
| --- | --- | --- |
| `holds.create` | = `action_id`（平台强制） | 结果未知重试必须沿用同一 action_id，平台回放原 hold |
| `holds.execution/capture/release` | `<id>:execution` 等稳定值 | 同 key 同内容重放存留响应；同 key 不同内容 409 `idempotency_conflict` |
| `settlements.create` | `settlement:<reference>` | 结算单本身按 reference 幂等，换键重复提交也返回原单 |

所有写方法都可用 `idempotency_key:` 关键字覆盖默认值。

错误分类（`Sparkler::AccountCenter::Error` 携带 `code` / `status` / `retryable?`）：

| 场景 | 分类 | 行为 |
| --- | --- | --- |
| 网络错误 / 超时 / 429 / 5xx | `RetryableError`（结果未知） | SDK 指数退避自动重试（默认 3 次、基数 0.5s、上限 5s、全抖动），幂等键不变 |
| 其余 4xx（400/401/402/403/404/409/422…） | `DeterministicError`（确定结果） | 第一次就抛出，不要原样重试 |

重试默认开启，只作用于 `RetryableError`；确定错误立即上抛。配置：

```ruby
Client.new(base_url:, …, retry_options: { max_attempts: 5, base_delay: 1.0 })
Client.new(base_url:, …, retry_options: false)  # 关闭自动重试
```

`settlements.wait_for(reference, timeout: 8, interval: 0.5)` 整体超时抛 `RetryableError`（结果仍未知）——凭**同一 reference** 续查，不要换 reference 重复提交。

其他行为：service token 进程内缓存并**提前 60s 过期**，并发共享刷新（Mutex）；资金请求收到 401 会清缓存并重试一次。用户接口错误体可能是 `{error: "..."}` 或 `{error: ["..."]}` 数组，SDK 统一解析为 `error.code`（数组取第一条）。

## Webhook 接收最佳实践

1. **验签**：`X-Signature = hex(HMAC-SHA256(webhook_secret, "{X-Timestamp}.{raw_body}"))`，常数时间比较（SDK 内置）；
2. **时间窗**：±5 分钟防重放（SDK 内置，`tolerance:` 可调）；
3. **去重**：按 `X-Delivery-Id`（= outbox key）幂等去重——投递保证 at-least-once，允许乱序/重复；
4. **ack**：处理成功后返回 2xx；验签失败返回 401；处理失败返回非 2xx 让平台重试（重试至死信）。

事件信封 8 字段：`event_id` / `schema_version`(=1) / `event_type` / `occurred_at` / `aggregate_type` / `aggregate_id` / `aggregate_version` / `correlation_id` / `data`（金额一律字符串）。乱序消费以 `aggregate_version` 重建投影、`event_id` 去重。已知事件：`account.balance_changed.v1`、`hold.captured.v1`、`settlement.posted.v1`、`settlement.rejected.v1`。

## 端点覆盖表

| 类别 | 端点 | SDK 方法 | 认证 |
| --- | --- | --- | --- |
| 认证 | `POST /oauth/token` | （内部，service token 自动管理） | client_credentials |
| 资金 | `POST /api/v1/holds` | `client.holds.create` | service |
| 资金 | `POST /api/v1/holds/:id/execution` `/capture` `/release` | `client.holds.execution/capture/release` | service |
| 资金 | `GET /api/v1/holds/:id` | `client.holds.get` | service |
| 资金 | `POST /api/v1/settlements` | `client.settlements.create` | service |
| 资金 | `GET /api/v1/settlements/by-reference/:reference` | `client.settlements.by_reference` / `wait_for` | service |
| 资金 | `GET /api/v1/balances?players=…` | `client.balances.get`（>100 自动分批合并） | service |
| 用户 | `POST /api/v1/auth/sign_up` | `client.auth.sign_up`（`guest_token:` 原地升级游客） | 无 / guest Bearer |
| 用户 | `POST /api/v1/auth/sign_in` | `client.auth.sign_in` | 无 |
| 用户 | `POST /api/v1/auth/wallet` | `client.auth.wallet`（SIWE） | 无 |
| 用户 | `GET /api/v1/auth/providers` | `client.auth.providers` | 无 |
| 用户 | `GET /api/v1/game_tokens/new` | `client.game_tokens.challenge` | 无 |
| 用户 | `POST /api/v1/game_tokens` | `client.game_tokens.create`（Bearer）/ `create_with_siwe` | Bearer / SIWE |
| 用户 | `POST /api/v1/game_tokens/guest` | `client.game_tokens.guest` → `GuestTicket` | 无 |
| 用户 | `GET /api/v1/me` / `PATCH /api/v1/me` | `client.me.get` / `update` | Bearer |
| 用户 | `POST/DELETE /api/v1/me/addresses*` | `client.me.create_address` / `delete_address` | Bearer |
| 用户 | `DELETE /api/v1/me/identities/:id` | `client.me.delete_identity` | Bearer |
| 用户 | `GET/POST /api/v1/withdrawals*` | `client.withdrawals.list` / `get` / `create` | Bearer |
| 用户 | `GET /api/v1/rounds/:round_id/event_logs` | `client.event_logs.list` | Bearer |
| 公开 | `GET /api/v1/game/jwks.json` | `TicketVerifier` 内部拉取 | 无 |
| 公开 | `GET /api/v1/leaderboard` | `client.leaderboard.get` | 无 |
| 入站 | 平台 Webhook | `WebhookVerifier#verify!` → `EventEnvelope` | HMAC 验签 |
| 入站 | RS256 游戏票据 | `TicketVerifier#verify!` → `TicketClaims` | JWKS 验签 |

## 开发

```bash
bundle install
bundle exec rspec      # RSpec + WebMock，全离线
bundle exec rubocop    # 代码风格
bundle exec rake       # spec + rubocop
```
