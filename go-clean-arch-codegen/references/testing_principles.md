# Testing Principles（語言無關的測試原則）

## 核心規則：只有兩個測試層級

Clean Architecture 分了很多層（domain / usecase / adapter-outbound / adapter-inbound），但這不代表每一層都要各自寫一份獨立測試。層數一多，常見的後果是：

- usecase 層的 mock port test，測的其實只是「有沒有正確呼叫 mock」，不是系統的真實行為——一旦 mock 跟真實 adapter 的行為兜不起來（該拋的 error 沒拋、真實 DB 的 constraint 沒模擬到），這些測試全綠也救不了你。
- adapter-outbound 層的 mapper/repository test，如果測的是「跟真實 DB 一樣的行為」，那它跟 controller-level 整合測試在驗證同一件事，只是晚一層才發現問題，還多一份要維護的程式碼。

所以這份原則只要求兩個測試層級，其餘不寫：

### Layer 1 — Domain Aggregate Test

- 對象：entity / aggregate root 的業務規則（狀態轉換、invariant、value object 驗證）。
- 完全不碰任何基礎設施、不 mock 任何東西——建構子把資料丟進去，呼叫方法，斷言最終狀態或丟出的 domain error。
- 目的是把「業務規則本身對不對」跟「這個規則有沒有被正確接到 HTTP/DB」這兩件事分開驗證，讓業務邏輯測試可以跑得極快、極穩定。

### Layer 2 — Controller-level Integration Test（用 testcontainer）

- 對象：從 HTTP 入口（controller/handler）一路走到真實資料庫，以及這個專案實際依賴的其他有狀態外部元件（例如 Redis）。
- 用 testcontainer 啟動跟正式環境同一種 DB/Redis image；不用 in-memory 替代品、不 mock repository——in-memory 替代品（例如用 sqlite 代替正式環境的 DB）在型別轉換、鎖、SQL 方言上都可能跟正式環境不一致，一旦不一致，測試綠燈但正式環境炸掉。實際要起哪種 DB/Redis image，依照專案本身的技術決策而定。
- 只 mock 這層「管不到」的東西：第三方 SaaS API（例如金流、簡訊)——這些依賴不屬於專案能控制的基礎設施，也沒有 testcontainer 可以起。
- 斷言不能只看 HTTP 回應——涉及寫入的操作要再查一次，確認狀態真的落地到資料庫。

## 為什麼不需要 usecase 層 mock test 和 adapter-outbound 層獨立 test

- usecase 層本身只做 orchestration，不該藏業務規則，所以它的邏輯已經被 domain aggregate test 涵蓋；它有沒有正確呼叫 port，則由 controller-level test 涵蓋。
- adapter-outbound 層的 mapper/repository 已經在 controller-level test 裡用真實 DB 跑過一次；再用假資料庫寫一份 mapper test，是重複勞動，也容易在假資料庫測試綠燈但真實 DB 行為不一致時被蓋牌。

## Go 這個 skill 的 testcontainer 對應

Go 這個 skill 的 Layer 2 實作已經內建在 `references/adapter_inbound_layer.md` 規則 9 跟它的模板裡,不用另外發明一套——那邊的 `<entity>/handler_test.go` 就是這份原則的具體落地:

- 用 `testcontainers-go` 啟動真實 MariaDB(見 `references/architecture.md` 的 `testsupport.NewMariaDBTestDB`),把真實的 Repository、UseCase Impl、Handler 全部串起來,對掛好 `middleware.ErrorHandler()` 的 `gin.Engine` 發真實 HTTP request。
- 專案有用到 Redis / Kafka / MinIO 等其他有狀態依賴,同樣用對應的 testcontainers 模組起真實 container、注入真實 Adapter,不用假的。
- 只有沒有可信賴 image 的第三方 SaaS API(Stripe、Twilio 這類,分類在 `client`/`notification`)才 fallback 用 `testify/mock` 假冒那一個 Outbound Port,其餘依賴維持真實——完整的「container 化 vs. fallback mock」判斷依據見 `references/adapter_inbound_layer.md` 裡的對照表。
- 這類測試需要 Docker,用 `//go:build integration` build tag 跟預設的快速單元測試(目前只剩 domain test)分開,不影響 `go test ./...`;要跑 Layer 2 測試時用 `go test -tags=integration ./...`。
