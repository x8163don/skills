# Usecase 層 — 業務案例與介面合約

## 規則

1. 只 import Domain package(`internal/domain/<entity>`)、本層自己的子 package(`port`/`result`/`command`/`event`)、`internal/usecase/usecaseerr`,以及標準函式庫的 `context`;不 import GORM、Gin 或任何 adapter 層 package。
2. 先定義 Outbound Ports(Repository、Client/Messaging/Cache/Notification/Storage 等外部依賴、事件發送)為介面,再定義 Inbound Port,最後實作對應的 UseCaseImpl。**每個 use case 情境(每條 Business Rule 或每個查詢需求)各自一個 Inbound Port 介面 + 一個 Impl,不共用一個大介面**:介面命名 `<Action><Entity>UseCase`(如 `CreateBookingUseCase`、`ConfirmBookingUseCase`、`GetBookingUseCase`),各自只宣告一個方法;Impl 命名 `<Action><Entity>UseCaseImpl`,只依賴自己需要的 Outbound Port,不共用一個大 Impl。
3. 所有依賴透過建構函式注入(`New<Action><Entity>UseCaseImpl(deps...) *<Action><Entity>UseCaseImpl`);Impl struct 本身無狀態,可安全併發重用。每個 Impl 檔案底部加 `var _ port.<Action><Entity>UseCase = (*<Action><Entity>UseCaseImpl)(nil)` 做編譯期介面滿足檢查。
4. 每個方法第一個參數固定 `ctx context.Context`,並透傳給呼叫的每個 Outbound Port 方法(`repository.Save(ctx, ...)` 等)——Go 沒有 `@Transactional` 這種宣告式交易,單一 Outbound Port 呼叫(如一次 `Save`)本身已具原子性,不需要額外標註;若某個 use case 需要跨多個 Outbound Port 呼叫的交易一致性,由該 use case 自行決定是否引入交易包裝,不在本 skill 的固定模板範圍內。
5. 查詢單筆一律:`repository.GetByID(ctx, id)` 回傳 `(*domain.<Entity>, error)`,查無資料時回傳 `(nil, nil)`(不是 error)——呼叫端(UseCaseImpl)檢查 `if <entity> == nil` 後回傳 `&usecaseerr.NotFoundError{Entity: "<entity>", ID: id}`。找不到本身不是錯誤,是查詢結果的一種(有 vs. 沒有);是否要把它當成錯誤處理,由呼叫端決定。
6. 領域事件在 `Save` 成功之後 publish;事件用 plain struct 定義在 `usecase.<entity>.event` package,`Publish` 失敗時直接回傳該 error(不吞掉)。
7. 找不到資料時回傳共用的 `usecaseerr.NotFoundError{Entity: "<entity>", ID: id}`(見 `references/architecture.md`),不用每個 entity 各自定義一個新的 error 型別——這個型別的欄位已經足以表達任何 entity 的 not-found 情境。
8. Repository Port 的標準方法簽名:`GetByID(ctx context.Context, id int64) (*domain.<Entity>, error)`、`Save(ctx context.Context, <entity> *domain.<Entity>) (*domain.<Entity>, error)`,查詢條件方法命名為 `GetBy<Field>`。
9. **Inbound Port 的方法一律回傳 `<Entity>Result` 家族型別,不直接回傳 Domain `*<Entity>`**:Domain 物件(及其業務方法)只能在 Usecase 內部與 Repository 之間流動,絕不可流出 Usecase 邊界。UseCaseImpl 內部正常操作 Domain(呼叫業務方法、`Save`),方法回傳前才用 `result.New<Entity>ResultFrom(domain)` 轉換。Result 用 plain struct 定義,無業務方法,命名依用途:
   - 預設(單筆查詢/寫入後回傳完整資料):`<Entity>Result`
   - 列表查詢、欄位精簡:`<Entity>SummaryResult`
   - 特定 use case 需要客製欄位(如包含關聯資料):依實際需求命名,不勉強套單一模板
10. **`usecase/<entity>/` 目錄下只放 `<action>_<entity>.go`(每個 use case 情境一個檔案)**,其餘依類型分子目錄,點進去就能一眼看到這個 entity 有哪些 use case、各自的設計內容而不必打開實作:
    - `port/`:所有介面——每個 use case 的 Inbound Port(`<Action><Entity>UseCase`)與全部 Outbound Port(`<Entity>Repository`、`<Concept>Client` 等、`DomainEventPublisher`)
    - `result/`:`<Entity>Result` 家族(Usecase 輸出型別)
    - `command/`:`<Action>Command` 家族(Usecase 輸入型別,規則 11)
    - `event/`:領域事件(既有規則,不變)
11. **寫入型 endpoint 的輸入型別 `<Action>Command` 定義在本層**(`usecase.<entity>.command`),不在 Adapter/Inbound:跟 Result 對稱,同樣是 Usecase 自己擁有的邊界資料結構,用 `go-playground/validator` 的 `binding` struct tag 驗證欄位(Gin 呼叫 `c.ShouldBindJSON` 時會自動套用這個 tag,見 `references/adapter_inbound_layer.md`);`<Action>Command` 是本層唯一允許帶第三方 struct tag 的型別。Inbound Port 方法直接以 `<Action>Command` 為參數(不拆欄位傳原始型別),Adapter 層的 Handler 直接 import 這個 Command 使用,不自己另外定義一份。單一 ID 這種簡單查詢/狀態變更(如 `Confirm(ctx, id int64)`、`GetByID(ctx, id int64)`)不需要包 Command,直接傳 `int64` 即可。

## 產出檔案(依序)

1. `port/<entity>_repository.go`(Outbound Port)
2. `port/<concept>_client.go` / `port/<concept>_message_publisher.go` / `port/<concept>_cache_store.go` / `port/<concept>_notification_sender.go` / `port/<concept>_file_storage.go`(Outbound Port,依外部依賴性質擇一,如有)
3. `port/domain_event_publisher.go`(Outbound Port,如有事件)
4. `event/<entity>_<action>_event.go`(如有事件)
5. `result/<entity>_result.go`(+ 其他 Result 變體,如 `result/<entity>_summary_result.go`,依規則 9 擇一或並存)
6. `command/<action>_command.go`(每個需要 request body 的 use case 一個,依規則 11)
7. 對每個 use case 情境重複:`port/<action>_<entity>_usecase.go`(Inbound Port)+ `<action>_<entity>.go`(直接放在 `usecase/<entity>/` 目錄下)

## 模板

### Outbound Port — Repository

```go
package port

import (
	"context"

	"<basePackage>/internal/domain/booking"
)

type BookingRepository interface {
	GetByID(ctx context.Context, id int64) (*domain.Booking, error)
	Save(ctx context.Context, booking *domain.Booking) (*domain.Booking, error)
}
```

（範例中 `domain.Booking` 是 import path `<basePackage>/internal/domain/booking` 底下 `package domain` 匯出的型別,見 `references/architecture.md` 命名例外說明。）

### Outbound Port — 外部依賴(Client / Messaging / Cache / Notification / Storage)

依外部依賴的性質選擇介面命名(見 `references/adapter_outbound_layer.md` 的分類表),方法簽名皆相同模式,以 Client(呼叫外部 API/SDK)為例:

```go
package port

import (
	"context"

	"<basePackage>/internal/domain/booking"
)

type PaymentClient interface {
	Charge(ctx context.Context, booking *domain.Booking) (string, error)
}
```

其餘分類介面命名同樣模式:`<Concept>MessagePublisher`(訊息佇列)、`<Concept>CacheStore`(快取)、`<Concept>NotificationSender`(通知)、`<Concept>FileStorage`(檔案儲存),package 皆為 `port`。

### Outbound Port — 事件發送

```go
package port

import "context"

type DomainEventPublisher interface {
	Publish(ctx context.Context, event any) error
}
```

### 領域事件

```go
package event

type BookingConfirmedEvent struct {
	BookingID    int64
	PayloadField Type
}
```

### Result(Usecase 輸出型別,取代直接回傳 Domain)

```go
package result

import "<basePackage>/internal/domain/booking"

type BookingResult struct {
	ID     int64
	Field  Type
	Status string
}

func NewBookingResultFrom(b *domain.Booking) BookingResult {
	return BookingResult{
		ID:     b.ID(),
		Field:  b.Field(),
		Status: string(b.Status()),
	}
}
```

列表查詢用的精簡變體(欄位依實際需求增減):

```go
package result

import "<basePackage>/internal/domain/booking"

type BookingSummaryResult struct {
	ID     int64
	Status string
}

func NewBookingSummaryResultFrom(b *domain.Booking) BookingSummaryResult {
	return BookingSummaryResult{ID: b.ID(), Status: string(b.Status())}
}
```

### Command(Usecase 輸入型別,與 Result 對稱)

跟 Result 一樣是 plain struct,無業務方法;欄位驗證用 `binding` tag(Gin + go-playground/validator 讀取):

```go
package command

type CreateBookingCommand struct {
	Field Type `json:"field" binding:"required"`
}
```

### Inbound Port(每個 use case 情境一個檔案)

每個介面只宣告**一個方法**,不 import Domain——方法簽名只暴露 Result(和需要時的 Command),呼叫方(Handler)因此也不需要認識 Domain。以帶 request body 的寫入型(`CreateBookingUseCase`)、只靠路徑參數的寫入型(`ConfirmBookingUseCase` 風格)、查詢型(`GetBookingUseCase`)各一個為例:

```go
package port

import (
	"context"

	"<basePackage>/internal/usecase/booking/command"
	"<basePackage>/internal/usecase/booking/result"
)

type CreateBookingUseCase interface {
	Create(ctx context.Context, cmd command.CreateBookingCommand) (result.BookingResult, error)
}
```

```go
package port

import (
	"context"

	"<basePackage>/internal/usecase/booking/result"
)

type ConfirmBookingUseCase interface {
	Confirm(ctx context.Context, bookingID int64) (result.BookingResult, error)
}
```

```go
package port

import (
	"context"

	"<basePackage>/internal/usecase/booking/result"
)

type GetBookingUseCase interface {
	GetByID(ctx context.Context, bookingID int64) (result.BookingResult, error)
}
```

### UseCase 實作(每個 use case 情境一個檔案,直接放在 `usecase/<entity>/` 目錄下)

帶 Command 的寫入型 Impl:

```go
package usecase

import (
	"context"

	"<basePackage>/internal/domain/booking"
	"<basePackage>/internal/usecase/booking/command"
	"<basePackage>/internal/usecase/booking/port"
	"<basePackage>/internal/usecase/booking/result"
)

type CreateBookingUseCaseImpl struct {
	bookingRepository port.BookingRepository
}

func NewCreateBookingUseCaseImpl(bookingRepository port.BookingRepository) *CreateBookingUseCaseImpl {
	return &CreateBookingUseCaseImpl{bookingRepository: bookingRepository}
}

var _ port.CreateBookingUseCase = (*CreateBookingUseCaseImpl)(nil)

func (uc *CreateBookingUseCaseImpl) Create(ctx context.Context, cmd command.CreateBookingCommand) (result.BookingResult, error) {
	booking, err := domain.NewBooking(0, cmd.Field, domain.StatusValue1)
	if err != nil {
		return result.BookingResult{}, err
	}

	saved, err := uc.bookingRepository.Save(ctx, booking)
	if err != nil {
		return result.BookingResult{}, err
	}

	return result.NewBookingResultFrom(saved), nil
}
```

只靠路徑參數、不需要 Command 的寫入型 Impl,只依賴自己需要的 Outbound Port(不強塞其他 use case 用不到的依賴):

```go
package usecase

import (
	"context"

	"<basePackage>/internal/usecase/booking/event"
	"<basePackage>/internal/usecase/booking/port"
	"<basePackage>/internal/usecase/booking/result"
	"<basePackage>/internal/usecase/usecaseerr"
)

type ConfirmBookingUseCaseImpl struct {
	bookingRepository port.BookingRepository
	eventPublisher    port.DomainEventPublisher
}

func NewConfirmBookingUseCaseImpl(
	bookingRepository port.BookingRepository,
	eventPublisher port.DomainEventPublisher,
) *ConfirmBookingUseCaseImpl {
	return &ConfirmBookingUseCaseImpl{bookingRepository: bookingRepository, eventPublisher: eventPublisher}
}

var _ port.ConfirmBookingUseCase = (*ConfirmBookingUseCaseImpl)(nil)

func (uc *ConfirmBookingUseCaseImpl) Confirm(ctx context.Context, bookingID int64) (result.BookingResult, error) {
	booking, err := uc.bookingRepository.GetByID(ctx, bookingID)
	if err != nil {
		return result.BookingResult{}, err
	}
	if booking == nil {
		return result.BookingResult{}, &usecaseerr.NotFoundError{Entity: "booking", ID: bookingID}
	}

	if err := booking.BusinessMethod(); err != nil { // 1. 呼叫 Domain 業務方法
		return result.BookingResult{}, err
	}

	saved, err := uc.bookingRepository.Save(ctx, booking) // 2. 持久化
	if err != nil {
		return result.BookingResult{}, err
	}

	// 3. 保存成功後發送領域事件
	if err := uc.eventPublisher.Publish(ctx, event.BookingConfirmedEvent{BookingID: saved.ID()}); err != nil {
		return result.BookingResult{}, err
	}

	// 4. Domain 到此為止,轉成 Result 才回傳給外層(Adapter 不可見 Domain)
	return result.NewBookingResultFrom(saved), nil
}
```

查詢型 Impl:不呼叫 `Save`、不 publish 事件、不需要 `DomainEventPublisher` 依賴:

```go
package usecase

import (
	"context"

	"<basePackage>/internal/usecase/booking/port"
	"<basePackage>/internal/usecase/booking/result"
	"<basePackage>/internal/usecase/usecaseerr"
)

type GetBookingUseCaseImpl struct {
	bookingRepository port.BookingRepository
}

func NewGetBookingUseCaseImpl(bookingRepository port.BookingRepository) *GetBookingUseCaseImpl {
	return &GetBookingUseCaseImpl{bookingRepository: bookingRepository}
}

var _ port.GetBookingUseCase = (*GetBookingUseCaseImpl)(nil)

func (uc *GetBookingUseCaseImpl) GetByID(ctx context.Context, bookingID int64) (result.BookingResult, error) {
	booking, err := uc.bookingRepository.GetByID(ctx, bookingID)
	if err != nil {
		return result.BookingResult{}, err
	}
	if booking == nil {
		return result.BookingResult{}, &usecaseerr.NotFoundError{Entity: "booking", ID: bookingID}
	}
	return result.NewBookingResultFrom(booking), nil
}
```

## 單元測試模板(TDD 時先產)

一個 use case 一個測試檔,命名 `<action>_<entity>_test.go`,用 `testify/mock` 手寫該 use case 真正用到的 Outbound Port 的假物件,不使用程式碼產生工具:

```go
package usecase

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"<basePackage>/internal/domain/booking"
	"<basePackage>/internal/usecase/usecaseerr"
)

type mockBookingRepository struct {
	mock.Mock
}

func (m *mockBookingRepository) GetByID(ctx context.Context, id int64) (*domain.Booking, error) {
	args := m.Called(ctx, id)
	booking, _ := args.Get(0).(*domain.Booking)
	return booking, args.Error(1)
}

func (m *mockBookingRepository) Save(ctx context.Context, booking *domain.Booking) (*domain.Booking, error) {
	args := m.Called(ctx, booking)
	saved, _ := args.Get(0).(*domain.Booking)
	return saved, args.Error(1)
}

type mockDomainEventPublisher struct {
	mock.Mock
}

func (m *mockDomainEventPublisher) Publish(ctx context.Context, event any) error {
	return m.Called(ctx, event).Error(0)
}

func TestConfirmBookingUseCaseImpl_Confirm(t *testing.T) {
	tests := []struct {
		name       string
		bookingID  int64
		setupMocks func(repo *mockBookingRepository, pub *mockDomainEventPublisher)
		wantErr    any // nil、或想用 errors.As 檢查的 error 型別指標
		wantStatus string
	}{
		{
			name:      "success",
			bookingID: 1,
			setupMocks: func(repo *mockBookingRepository, pub *mockDomainEventPublisher) {
				booking, _ := domain.NewBooking(1, "field", domain.StatusValue1)
				repo.On("GetByID", mock.Anything, int64(1)).Return(booking, nil)
				repo.On("Save", mock.Anything, mock.Anything).Return(booking, nil)
				pub.On("Publish", mock.Anything, mock.Anything).Return(nil)
			},
			wantStatus: "VALUE_2",
		},
		{
			name:      "not found",
			bookingID: 99,
			setupMocks: func(repo *mockBookingRepository, pub *mockDomainEventPublisher) {
				repo.On("GetByID", mock.Anything, int64(99)).Return(nil, nil)
			},
			wantErr: &usecaseerr.NotFoundError{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := new(mockBookingRepository)
			pub := new(mockDomainEventPublisher)
			tt.setupMocks(repo, pub)

			uc := NewConfirmBookingUseCaseImpl(repo, pub)
			got, err := uc.Confirm(context.Background(), tt.bookingID)

			if tt.wantErr != nil {
				require.Error(t, err)
				assert.ErrorAs(t, err, tt.wantErr)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.wantStatus, got.Status)
			repo.AssertExpectations(t)
			pub.AssertExpectations(t)
		})
	}
}
```
