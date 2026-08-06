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
- 用 testcontainer 啟動跟正式環境同一種 DB/Redis image；不用 in-memory 替代品、不 mock repository——in-memory 替代品（例如用 H2/sqlite 代替 Postgres）在型別轉換、鎖、SQL 方言上都可能跟正式環境不一致，一旦不一致，測試綠燈但正式環境炸掉。實際要起哪種 DB/Redis image，依照專案本身的技術決策而定。
- 只 mock 這層「管不到」的東西：第三方 SaaS API（例如金流、簡訊)——這些依賴不屬於專案能控制的基礎設施，也沒有 testcontainer 可以起。
- 斷言不能只看 HTTP 回應——涉及寫入的操作要再查一次，確認狀態真的落地到資料庫。

## 為什麼不需要 usecase 層 mock test 和 adapter-outbound 層獨立 test

- usecase 層本身只做 orchestration，不該藏業務規則，所以它的邏輯已經被 domain aggregate test 涵蓋；它有沒有正確呼叫 port，則由 controller-level test 涵蓋。
- adapter-outbound 層的 mapper/repository 已經在 controller-level test 裡用真實 DB 跑過一次；再用假資料庫寫一份 mapper test，是重複勞動，也容易在假資料庫測試綠燈但真實 DB 行為不一致時被蓋牌。

## Java 這個 skill 的 testcontainer 對應

Layer 2 用 [Testcontainers for Java](https://testcontainers.com/) 起跟正式環境同一種 DB(預設以 Postgres 為例,實際專案用 MySQL/MariaDB 等時把 `PostgreSQLContainer` 換成對應的 module,做法相同):

- 依賴(`pom.xml`,`<scope>test</scope>`):`org.testcontainers:junit-jupiter`、`org.testcontainers:postgresql`(或對應 DB 的 module)。Gradle 專案對應加 `testImplementation`。
- 測試類別標 `@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)` + `@Testcontainers`,用 `@Container` 宣告 `static PostgreSQLContainer<?> postgres`(`static` 讓整個測試類別共用同一個 container,不用每個 `@Test` 都重啟一次)。
- 用 `@DynamicPropertySource` 把 container 啟動後的 JDBC URL、帳號、密碼動態注入 Spring 的 `spring.datasource.*` 設定,這樣 Spring context 啟動時,JPA/Hibernate 接的就是這個真實的 Postgres container,不是 H2 或任何 in-memory 替代品。
- 需要 Redis 等其他有狀態依賴時,比照辦理:再宣告一個對應的 `@Container`(如 `GenericContainer` 包 `redis:7-alpine`),用 `@DynamicPropertySource` 注入連線資訊。
- 第三方 SaaS 依賴(如 `PaymentClient`)用 `@MockBean` 蓋掉那一個 Outbound Port 介面,其餘全部是真實 Bean、真實 container。
- 用 `TestRestTemplate`(`@SpringBootTest` 內建可注入)或 `MockMvc` 對真實 HTTP endpoint 發 request;寫入操作除了斷言 HTTP 回應本身,再呼叫一次 `<Entity>JpaRepository`(或再發一次 GET request)查一次資料庫,確認狀態真的落地。

具體模板見 `references/adapter_inbound_layer.md` 的「Controller-level 整合測試(Testcontainers)」章節。
