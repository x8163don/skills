# Testing Principles（語言無關的測試原則）

## 核心規則：只有兩個測試層級

Clean Architecture 分了很多層（domain / usecase / adapter-outbound / adapter-inbound），但這不代表每一層都要各自寫一份獨立測試。層數一多，常見的後果是：

- usecase 層的 mock port test，測的其實只是「有沒有正確呼叫 mock」，不是系統的真實行為——一旦 mock 跟真實 adapter 的行為兜不起來（該拋的 error 沒拋、真實 DB 的 constraint 沒模擬到），這些測試全綠也救不了你。
- adapter-outbound 層的 mapper/repository test，如果測的是「跟真實 DB 一樣的行為」，那它跟 controller-level 整合測試在驗證同一件事，只是晚一層才發現問題，還多一份要維護的程式碼。

所以這份原則只要求兩個測試層級，其餘不寫：

### Layer 1 — Domain Aggregate Test

- 對象：entity / aggregate root 的業務規則（狀態轉換、invariant、value object 驗證）。
- 完全不碰任何基礎設施、不 mock 任何東西——建構子把資料丟進去，呼叫方法,斷言最終狀態或丟出的 domain error。
- 目的是把「業務規則本身對不對」跟「這個規則有沒有被正確接到 HTTP/DB」這兩件事分開驗證，讓業務邏輯測試可以跑得極快、極穩定。

### Layer 2 — Controller-level Integration Test（用 testcontainer）

- 對象：從 HTTP 入口（controller/handler）一路走到真實資料庫，以及這個專案實際依賴的其他有狀態外部元件（例如 Redis）。
- 用 testcontainer 啟動跟正式環境同一種 DB/Redis image；不用 in-memory 替代品、不 mock repository——in-memory 替代品（例如用 sqlite 代替正式環境的 DB）在型別轉換、鎖、SQL 方言上都可能跟正式環境不一致，一旦不一致，測試綠燈但正式環境炸掉。實際要起哪種 DB/Redis image，依照專案本身的技術決策而定。
- 只 mock 這層「管不到」的東西：第三方 SaaS API（例如金流、簡訊）——這些依賴不屬於專案能控制的基礎設施，也沒有 testcontainer 可以起。
- 斷言不能只看 HTTP 回應——涉及寫入的操作要再查一次，確認狀態真的落地到資料庫。

## 為什麼不需要 usecase 層 mock test 和 adapter-outbound 層獨立 test

- usecase 層本身只做 orchestration，不該藏業務規則，所以它的邏輯已經被 domain aggregate test 涵蓋；它有沒有正確呼叫 port，則由 controller-level test 涵蓋。
- adapter-outbound 層的 mapper/repository 已經在 controller-level test 裡用真實 DB 跑過一次；再用假資料庫寫一份 mapper test，是重複勞動，也容易在假資料庫測試綠燈但真實 DB 行為不一致時被蓋牌。

## TypeScript 這個 skill 的 testcontainer 對應

- 套件:[`testcontainers`](https://node.testcontainers.org/)(Node.js 官方 binding),依專案實際使用的 DB 搭配對應的 module 套件——Postgres 用 `@testcontainers/postgresql`(`PostgreSqlContainer`)、MySQL 用 `@testcontainers/mysql`(`MySqlContainer`)、Redis 用 `@testcontainers/redis`(`RedisContainer`)。安裝:`npm install -D testcontainers @testcontainers/postgresql`(依實際用到的模組調整)。
- 用法固定在 Vitest 的 `beforeAll`/`afterAll`:`beforeAll` 呼叫 `new PostgreSqlContainer('postgres:16-alpine').start()` 起真實容器,再用回傳物件的 `getHost()`/`getPort()`/`getUsername()`/`getPassword()`/`getDatabase()` 組成 `TypeOrmModule.forRoot(...)` 的連線設定;`afterAll` 呼叫 `container.stop()` 釋放資源。第一次啟動容器需要拉 image,`beforeAll` 建議搭配較長的 timeout(如 `beforeAll(async () => {...}, 60_000)`)。
- 執行測試的環境需要有 Docker(CI 上通常已內建或需要額外啟用 Docker-in-Docker/Docker socket 掛載),這是 Layer 2 測試唯一額外的環境需求。
- 完整範例見 `references/adapter_inbound_layer.md` 的「Controller-level 整合測試」章節。
