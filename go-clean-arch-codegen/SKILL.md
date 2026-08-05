---
name: go-clean-arch-codegen
description: Use when the user wants to implement a new feature or entity in a Go project using Clean Architecture / Hexagonal Architecture layers (Domain/Entities, Usecase, Adapter — split into Outbound and Inbound sides of Interface Adapters), generating idiomatic Go (Gin handlers, GORM repositories, testify/mock tests, error-return style instead of exceptions). Triggers on an entity spec with fields/business rules, "generate Go layers for X", "implement X with clean architecture in Go", "scaffold X entity in Go", "write TDD implementation for X in Go", or requirement + test descriptions in a Go project. Invoke even for partial specs — ask only for missing critical info (entity name or fields).
---

# Go Clean Architecture Code Generator

## 目的

根據實體規格(Entity Spec)產生完整、可編譯的 Go 分層程式碼(Domain → Usecase → Adapter/Outbound → Adapter/Inbound),對應 Clean Architecture 的 Entities → Use Cases → Interface Adapters 三圈(Adapter 依方向拆為 Outbound/Inbound 兩側,合稱 Interface Adapters;Frameworks & Drivers 第四圈不獨立成 package,詳見 `references/architecture.md`)。技術選型固定為 **Gin**(HTTP)+ **GORM**(持久化)+ **testify/mock**(usecase 層測試替身)。所有型別名稱、package 路徑、檔案位置皆由固定模板推導,確保多次產出結果高度一致,且是這個技術棧下慣用的 Go 寫法(interface + 建構函式注入、`error` 回傳值、`context.Context` 貫穿、table-driven 測試)。

## 觸發時機

**使用**:在 Go 專案中實作新實體或新功能、依規格 scaffold Clean Architecture 分層、TDD 實作(規格附測試描述)。

**不使用**:非 Go 專案、只修改既有單一檔案而不涉及分層、純 SQL/設定檔調整。

## 規則

所有產出必須同時滿足以下規則(各層細節規則見對應 reference):

1. **依賴方向由外向內**:Adapter(Interface Adapters,含 Outbound/Inbound 兩側)→ Usecase → Domain。每一層只 import 自己這層與更內層的 package。
2. **Domain 是純 Go**:只 import 標準函式庫與 `internal/domain/domainerr`;業務邏輯寫在實體方法內(充血模型);建構函式 `New<Entity>(...)` 回傳 `(*<Entity>, error)`,驗證失敗回傳包住 `domainerr.ErrInvalidArgument` 的錯誤;行為隨型別變化時用策略介面 + 多個實作。
3. **Usecase 用 `error` 回傳值取代例外**:每個方法第一個參數固定 `ctx context.Context`;查詢單筆找不到時 Repository 回傳 `(nil, nil)`,UseCaseImpl 轉成共用的 `usecaseerr.NotFoundError`;先 `Save` 成功、後 `Publish` 事件;依賴一律建構函式注入;Inbound Port 方法一律回傳 Usecase 自己定義的 `<Entity>Result` 家族型別,方法內部操作完 Domain 才轉換,Domain 物件不可流出 Usecase 邊界。**每個 use case 情境(每條 Business Rule 或查詢需求)各自一個 Inbound Port 介面 + 一個 Impl struct,不共用一個大介面/大 struct**;需要 request body 的 use case,其輸入型別 `<Action>Command` 也定義在本層(跟 `<Entity>Result` 對稱);`usecase/<entity>/` 目錄下只放這些 `<action>_<entity>.go`,介面收進 `port/`、Result 收進 `result/`、Command 收進 `command/`、事件收進 `event/`。
4. **Adapter/Outbound 隔離技術細節**:GORM struct tag 只出現在 `<Entity>DataModel`(不叫 `<Entity>Entity`,避免與 Domain 的 `<Entity>` 混淆);`<Entity>Mapper` 全部為套件層級純函式;`<Entity>RepositoryImpl` 實作 Usecase 的 Outbound Port;非 DB 的外部依賴(API/SDK、訊息佇列、快取、通知、檔案儲存)一律命名 `<Provider><Concept>Adapter`,分類到 `client/`、`messaging/`、`cache/`、`notification/`、`storage/` 子目錄,SDK error 在此層捕捉並轉為自訂 error 型別(如 `PaymentClientError`,實作 `Unwrap()`)後回傳。
5. **Adapter/Inbound 只做轉換**:Handler 僅解析參數 → 呼叫 UseCase → 寫回 JSON;寫入型輸入物件 `<Action>Command` 是從 usecase 層 import 使用(本層不自己定義一份),搭配 `c.ShouldBindJSON`;`middleware.ErrorHandler()` 統一轉換:`*usecaseerr.NotFoundError` → 404、綁定驗證失敗 → 400、`domainerr.ErrInvalidState`/`ErrInvalidArgument` → 400、其他 → 500;Response 包裝 Usecase 回傳的 `<Entity>Result` 後回傳(不是 Domain,不叫 Dto);本層一律不 import `domain` package。這一層的 package 名稱是 entity 本身(如 `package booking`),不叫 `http`(避免跟 `net/http` 撞名),型別因此不重複加 entity 前綴。
6. **共用基礎設施只生成一次**:`internal/domain/domainerr`、`internal/usecase/usecaseerr`、`internal/adapter/inbound/http/middleware/error_handler.go` 是專案級檔案,不是 per-entity 檔案——第一次在這個專案使用本 skill 時產生,之後每個新 entity 直接重用,不要重複產出(見 `references/architecture.md`)。
7. **命名一律依推導表**:所有型別名稱與檔案路徑依 `references/architecture.md` 的命名推導表從 Entity 名稱產生,不自創命名。
8. **每個檔案完整可編譯**:含 package 宣告、全部 import、完整方法實作,零 TODO、零 `panic("not implemented")`。
9. **產生順序固定**:(共用基礎設施,如未生成 →)(測試 →)Domain → Usecase → Adapter/Outbound → Adapter/Inbound;有測試描述時,測試先於實作產生。

## 固定輸出格式

整體輸出依序包含三個部分:(1) module path 註記一行、(2) 產出檔案清單(相對路徑,依產生順序)、(3) 各檔案內容。檢查清單為內部步驟,不出現在輸出中。

每個檔案一律使用以下標頭,讓用戶可直接放置:

```
// === <Layer> Layer ===
// File: internal/<layer 路徑>/<file>.go

<完整 Go 原始碼>
```

未提供 module path 時,一律使用 `github.com/example/<project>` 並在輸出開頭註明,所有程式碼放在 `internal/` 之下。

## 工作流程

1. **解析與確認**:從輸入提取 Entity 名稱(PascalCase)、Fields(Go 型別)、Business Rules(→ 方法簽名)、Outbound Dependencies、API Endpoints、Tests。輸入為段落描述時,自行整理成規格並請用戶確認;僅在 Entity 名稱或 Fields 完全缺失時才暫停詢問。輸入格式見 `references/architecture.md`。
2. **確認共用基礎設施**:詢問或依上下文判斷這是否是專案第一次使用本 skill;若是,先產生 `internal/domain/domainerr/domainerr.go`、`internal/usecase/usecaseerr/not_found.go`、`internal/adapter/inbound/http/middleware/error_handler.go`(模板見 `references/architecture.md`)。若專案已有這三個檔案,跳過此步驟。
3. **(TDD)先產測試**:規格含測試描述時,產生 `<entity>_test.go`(table-driven、無 mock、每條業務規則一個正常案例 + 至少一個邊界案例)與每個 use case 情境各自的 `<action>_<entity>_test.go`(table-driven + `testify/mock`,只手寫該 use case 用到的 Outbound Port 的假物件)。
4. **依序產生四層**:每層產生前先讀取對應 reference 的模板:

   | 層 | Reference | 產出檔案 |
   |---|---|---|
   | 共用 | `references/architecture.md` | package 結構、命名推導表、輸入格式、共用基礎設施 |
   | Domain | `references/domain_layer.md` | Entity、Status 型別、策略介面(如適用) |
   | Usecase | `references/usecase_layer.md` | Outbound Ports、Result、Command、每個 use case 情境的 Inbound Port + Impl、事件 |
   | Adapter/Outbound | `references/adapter_outbound_layer.md` | GORM DataModel、Mapper、RepositoryImpl、(Client/Messaging/Cache/Notification/Storage Adapter) |
   | Adapter/Inbound | `references/adapter_inbound_layer.md` | Response、Handler(Command 已在 Usecase 產出,此處直接 import) |

5. **逐層檢查**:每層完成後對照該 reference 的「規則」小節與本文件「產出前檢查」。

## 簡單範例

輸入:

```
Entity: Booking
Fields:
  - id (int64)
  - accountId (int64)
  - status (enum: PENDING / CONFIRMED / CANCELLED)
Business Rules:
  - Confirm(): 只有 PENDING 可確認,否則回傳包住 domainerr.ErrInvalidState 的錯誤
Outbound Dependencies:
  - BookingRepository: 預約持久化
API Endpoints:
  - PUT /api/bookings/{id}/confirm: 確認預約
```

產出檔案清單(命名全部由推導表產生;假設專案已有共用基礎設施):

```
internal/domain/booking/status.go
internal/domain/booking/booking.go
internal/usecase/booking/port/booking_repository.go          ← Outbound Port
internal/usecase/booking/result/booking_result.go            ← Usecase 輸出型別(不回傳 Domain)
internal/usecase/booking/port/confirm_booking_usecase.go     ← Inbound Port(對應 Confirm() 這個 use case)
internal/usecase/booking/confirm_booking.go                  ← 直接放在 usecase/booking/ 目錄下
internal/adapter/outbound/repository/datamodel/booking_data_model.go
internal/adapter/outbound/repository/mapper/booking_mapper.go
internal/adapter/outbound/repository/booking_repository.go
internal/adapter/inbound/http/booking/response.go
internal/adapter/inbound/http/booking/handler.go
```

其中 Domain 實體產出樣貌(對應規則 2 與固定輸出格式):

```go
// === Domain Layer ===
// File: internal/domain/booking/booking.go

package domain

import (
	"fmt"

	"github.com/example/booking/internal/domain/domainerr"
)

type Status string

const (
	StatusPending   Status = "PENDING"
	StatusConfirmed Status = "CONFIRMED"
	StatusCancelled Status = "CANCELLED"
)

type Booking struct {
	id        int64
	accountID int64
	status    Status
}

func NewBooking(id int64, accountID int64, status Status) (*Booking, error) {
	if accountID == 0 {
		return nil, fmt.Errorf("accountID must not be zero: %w", domainerr.ErrInvalidArgument)
	}
	if status == "" {
		return nil, fmt.Errorf("status must not be empty: %w", domainerr.ErrInvalidArgument)
	}
	return &Booking{id: id, accountID: accountID, status: status}, nil
}

// Confirm 業務行為:確認預約
func (b *Booking) Confirm() error {
	if b.status != StatusPending {
		return fmt.Errorf("only PENDING booking can be confirmed, current status is %s: %w",
			b.status, domainerr.ErrInvalidState)
	}
	b.status = StatusConfirmed
	return nil
}

func (b *Booking) ID() int64        { return b.id }
func (b *Booking) AccountID() int64 { return b.accountID }
func (b *Booking) Status() Status   { return b.status }
```

## 產出前檢查

- [ ] Domain 檔案只 import 標準函式庫與 `internal/domain/domainerr`
- [ ] 每個對外方法(port 介面方法、usecase 方法、repository 方法)第一個參數是 `context.Context`;Domain 方法不帶
- [ ] 事件在 `Save` 之後 publish
- [ ] GORM tag 只在 `<Entity>DataModel`;Mapper 全是套件層級純函式
- [ ] 每個 use case 情境各自一個 Inbound Port 介面(只宣告一個方法)+ 一個 Impl struct,沒有共用的大介面/大 struct;方法皆回傳 `<Entity>Result` 家族型別,不直接回傳 Domain `*<Entity>`;Impl 檔案有 `var _ port.Xxx = (*XxxImpl)(nil)` 編譯期檢查
- [ ] `usecase/<entity>/` 目錄下只有 `<action>_<entity>.go`(每個 use case 一個);介面在 `port/`、Result 在 `result/`、Command 在 `command/`、事件在 `event/`
- [ ] `<Action>Command` 定義在 usecase 層,不在 Adapter/Inbound 重複定義一份
- [ ] 找不到資料一律回傳共用的 `usecaseerr.NotFoundError`,不是每個 entity 各自定義的型別
- [ ] Handler 無 if/else 業務邏輯;錯誤一律 `c.Error(err)` 交給 middleware,不自組錯誤 JSON;回傳皆為 `Response`;輸入物件皆為 `<Action>Command`(無 Request/Dto 命名);不 import `domain` package
- [ ] `internal/domain/domainerr`、`internal/usecase/usecaseerr`、`middleware.ErrorHandler()` 若專案已存在則未重複產生
- [ ] 所有型別名稱符合命名推導表
- [ ] 每個檔案有輸出標頭、完整 import(無未使用 import)、零 TODO
