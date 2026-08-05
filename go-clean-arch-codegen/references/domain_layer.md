# Domain 層 — 領域實體與核心業務

## 規則

1. 只 import Go 標準函式庫(`errors`、`fmt`、`time` 等)以及 `internal/domain/domainerr`(本身也只 import 標準函式庫的共用錯誤套件,見 `references/architecture.md`);不 import 任何第三方套件、不 import `context`——Domain 是純運算,不做 I/O。
2. 業務邏輯寫在實體的行為方法內(充血模型);每條 Business Rule 對應一個方法,回傳 `error`(成功回傳 `nil`)。
3. 提供 `New<Entity>(...)` 建構函式回傳 `(*<Entity>, error)`;所有輸入驗證在建構函式內完成,失敗時回傳包住 `domainerr.ErrInvalidArgument` 的錯誤,不回傳部分建構的實體(回傳 `nil, err`)。
4. 欄位一律 unexported(小寫);對外只透過 getter 方法讀取(`func (e *Entity) Field() Type`),沒有 setter——狀態只能透過業務方法變更,呼叫端無法繞過業務規則直接改欄位。
5. 狀態型別 `Status` 與實體定義在同一個 domain package,用 `type Status string` + `const` 區塊列舉,不用 `iota` 數字列舉——字串值可直接對映到 DB 欄位與 JSON,不需要額外轉換表。
6. 行為隨型別變化時,定義策略介面 `<Concept>` 與多個實作 struct,以多型取代 if-else。
7. 唯讀值物件(如外部系統查回的資料)用 plain struct,不需要建構函式與 getter,欄位可以直接 exported。
8. 業務規則違反時,回傳的 `error` 一律用 `fmt.Errorf("...: %w", domainerr.ErrInvalidState)` 或 `domainerr.ErrInvalidArgument` 包裝——狀態轉移錯誤包 `ErrInvalidState`、建構參數不合法包 `ErrInvalidArgument`,讓上層可以用 `errors.Is` 判斷種類,不需要認得每個 entity 各自的錯誤型別。

## 產出檔案(依序)

1. `status.go`(如有狀態欄位)
2. `<concept>.go` + 各實作(如有策略介面)
3. `<entity>.go`

## 模板

### 狀態型別 `status.go`

```go
package domain

type Status string

const (
	StatusValue1 Status = "VALUE_1"
	StatusValue2 Status = "VALUE_2"
	StatusValue3 Status = "VALUE_3"
)
```

### 核心實體 `<entity>.go`

```go
package domain

import (
	"fmt"

	"<basePackage>/internal/domain/domainerr"
)

type Booking struct {
	id            int64
	immutableField string // 建構後不再變動的欄位
	status        Status  // 可變狀態欄位
}

// NewBooking validates all invariants up front; a Booking value can never
// exist in an invalid state once constructed.
func NewBooking(id int64, immutableField string, status Status) (*Booking, error) {
	if immutableField == "" {
		return nil, fmt.Errorf("immutableField must not be empty: %w", domainerr.ErrInvalidArgument)
	}
	if status == "" {
		return nil, fmt.Errorf("status must not be empty: %w", domainerr.ErrInvalidArgument)
	}
	return &Booking{id: id, immutableField: immutableField, status: status}, nil
}

// BusinessMethod 對應一條 Business Rule;狀態檢查失敗回傳包住 ErrInvalidState 的錯誤。
func (b *Booking) BusinessMethod() error {
	if b.status != StatusValue1 {
		return fmt.Errorf("only %s booking can BusinessMethod, current status is %s: %w",
			StatusValue1, b.status, domainerr.ErrInvalidState)
	}
	b.status = StatusValue2
	return nil
}

// 查詢型業務方法回傳 bool,不變更狀態,不回傳 error。
func (b *Booking) CanBusinessQuery() bool {
	return b.status == StatusValue1
}

func (b *Booking) ID() int64              { return b.id }
func (b *Booking) ImmutableField() string { return b.immutableField }
func (b *Booking) Status() Status         { return b.status }
```

### 策略介面(行為隨型別變化時)

```go
package domain

type Concept interface {
	Type() ConceptType
	Behavior() ReturnType
}
```

各實作 struct(如 `FreeConcept` / `StandardConcept`)實作同一介面,差異行為封裝在各自的方法內;每個實作 struct 檔案底部加 `var _ Concept = (*FreeConcept)(nil)` 做編譯期檢查。

### 唯讀值物件

```go
package domain

type ValueObject struct {
	Field1 Type1
	Field2 Type2
}
```

## 單元測試模板(TDD 時先產)

一個實體一個測試檔 `<entity>_test.go`,不使用 mock(Domain 沒有外部依賴),用 table-driven 涵蓋每條 Business Rule 的正常案例與至少一個邊界案例:

```go
package domain

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"<basePackage>/internal/domain/domainerr"
)

func TestBooking_BusinessMethod(t *testing.T) {
	tests := []struct {
		name          string
		initialStatus Status
		wantErr       bool
		wantStatus    Status
	}{
		{name: "eligible status succeeds", initialStatus: StatusValue1, wantStatus: StatusValue2},
		{name: "ineligible status fails", initialStatus: StatusValue2, wantErr: true, wantStatus: StatusValue2},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			booking, err := NewBooking(1, "field", tt.initialStatus)
			require.NoError(t, err)

			err = booking.BusinessMethod()

			if tt.wantErr {
				assert.Error(t, err)
				assert.ErrorIs(t, err, domainerr.ErrInvalidState)
			} else {
				assert.NoError(t, err)
			}
			assert.Equal(t, tt.wantStatus, booking.Status())
		})
	}
}
```
