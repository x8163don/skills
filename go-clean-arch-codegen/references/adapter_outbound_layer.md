# Adapter/Outbound 層 — 外部基礎設施整合(Interface Adapters,驅動內層依賴的一側)

## 規則

1. GORM struct tag(`gorm:"..."`)只出現在 `<Entity>DataModel`;Domain struct 保持零 tag、零第三方 import。命名一律叫 `<Entity>DataModel`,不叫 `<Entity>Entity`——避免跟 Domain 的 `<Entity>` 混淆。
2. `<Entity>DataModel` 用 `gorm:"column:<snake_case>"` 指定欄位名,並實作 `TableName() string` 回傳 snake_case 複數表名(`func (BookingDataModel) TableName() string { return "bookings" }`);不嵌入 `gorm.Model`,所有欄位顯式宣告,跟 Domain 欄位一一對應,方便 Mapper 轉換時一眼看出對應關係。
3. `<Entity>Mapper` 全部是套件層級的純函式(`ToDomain` / `ToDataModel`),不是 struct 方法、不被注入;兩個方法開頭皆做 nil 檢查,輸入為 nil 時回傳 `nil`(`ToDomain` 回傳 `nil, nil`)。
4. `<Entity>RepositoryImpl` 實作 Usecase 的 `<Entity>Repository`(Outbound Port),持有 `*gorm.DB`,內部直接呼叫 GORM API 並經 Mapper 轉換;`GetByID` 遇到 `gorm.ErrRecordNotFound` 時回傳 `(nil, nil)`(對映 Usecase 層規則 5 的「找不到不是 error」)。
5. 外部 SDK(Stripe、Kafka、Redis 等)只在對應的 `adapter/outbound/<category>` 子目錄 import;SDK 回傳的 error 在此層捕捉,轉為自訂 error 型別(如 `PaymentClientError`,實作 `Error() string` 與 `Unwrap() error` 以保留原始 cause)後回傳,不讓 SDK 的原始 error 型別外流到 Usecase。
6. 每個外部依賴 Adapter 構造函式接收已經解析好的設定值(API key、endpoint 等字串/數值),不在 Adapter 內部讀環境變數——設定值統一在 `cmd/server/main.go`(composition root)用 `os.Getenv` 或設定檔讀取後傳入建構函式,Adapter 本身保持可測試、不依賴全域狀態。
7. 依外部依賴的性質分類到對應子目錄,Outbound Port 與 Adapter 命名對照:

   | 子目錄 | Outbound Port(usecase 層介面) | Adapter 實作 | Error 型別 | 範例 |
   |---|---|---|---|---|
   | `client/` | `<Concept>Client` | `<Provider><Concept>Adapter` | `<Concept>ClientError` | `PaymentClient` → `StripePaymentAdapter` |
   | `messaging/` | `<Concept>MessagePublisher` | `<Provider><Concept>Adapter` | `<Concept>MessagingError` | `OrderMessagePublisher` → `KafkaOrderAdapter` |
   | `cache/` | `<Concept>CacheStore` | `<Provider><Concept>Adapter` | `<Concept>CacheError` | `BookingCacheStore` → `RedisBookingAdapter` |
   | `notification/` | `<Concept>NotificationSender` | `<Provider><Concept>Adapter` | `<Concept>NotificationError` | `SmsNotificationSender` → `TwilioSmsAdapter` |
   | `storage/` | `<Concept>FileStorage` | `<Provider><Concept>Adapter` | `<Concept>StorageError` | `AttachmentFileStorage` → `S3AttachmentAdapter` |

   五類結構完全相同(見下方模板),只有子目錄、Port 介面名稱、error 型別名稱不同。
8. 事件發送使用 `InProcessEventPublisher`,實作 Usecase 的 `DomainEventPublisher`,以 handler function 清單的形式在程序內同步呼叫——這是 in-process 的 domain event,跟 `messaging/`(對外部訊息佇列發送)是不同用途,不可混用。
9. **測試**:這層不產生獨立測試檔案。Mapper 的轉換正確性與 Repository 的查詢/寫入行為,已經在 Adapter/Inbound 層的 controller-level integration test(用 testcontainer 起真實 DB,見 `references/testing_principles.md`)裡用真實 DB 跑過一次;另外用記憶體 SQLite 寫一份 repository test,測的是「跟記憶體 SQLite 相容」而不是「跟正式環境的 DB 相容」,容易在假資料庫測試綠燈但正式 DB(型別轉換、鎖、SQL 方言不同)行為不一致時被蓋牌,所以不再產生。

## 產出檔案(依序)

1. `datamodel/<entity>_data_model.go`
2. `mapper/<entity>_mapper.go`
3. `<entity>_repository.go`(RepositoryImpl)
4. `<category>/<provider>_<concept>_adapter.go`(如有 Client/Messaging/Cache/Notification/Storage Port,`<category>` 依規則 7 的分類表擇一)
5. `event/in_process_event_publisher.go`(如有事件 Port,且專案尚未產生過)

## 模板

### GORM DataModel `datamodel/<entity>_data_model.go`

```go
package datamodel

type BookingDataModel struct {
	ID    int64  `gorm:"column:id;primaryKey;autoIncrement"`
	Field string `gorm:"column:field;not null"`
	Status string `gorm:"column:status;not null"` // 狀態一律以字串儲存(Status 底層型別)
}

func (BookingDataModel) TableName() string {
	return "bookings"
}
```

### 對映器 `mapper/<entity>_mapper.go`

```go
package mapper

import (
	"<basePackage>/internal/adapter/outbound/repository/datamodel"
	"<basePackage>/internal/domain/booking"
)

func ToDomain(dm *datamodel.BookingDataModel) (*domain.Booking, error) {
	if dm == nil {
		return nil, nil
	}
	return domain.NewBooking(dm.ID, dm.Field, domain.Status(dm.Status))
}

func ToDataModel(b *domain.Booking) *datamodel.BookingDataModel {
	if b == nil {
		return nil
	}
	return &datamodel.BookingDataModel{
		ID:     b.ID(),
		Field:  b.Field(),
		Status: string(b.Status()),
	}
}
```

### Outbound Port 實作 `<entity>_repository.go`

```go
package repository

import (
	"context"
	"errors"

	"gorm.io/gorm"

	"<basePackage>/internal/adapter/outbound/repository/datamodel"
	"<basePackage>/internal/adapter/outbound/repository/mapper"
	"<basePackage>/internal/domain/booking"
	"<basePackage>/internal/usecase/booking/port"
)

type BookingRepositoryImpl struct {
	db *gorm.DB
}

func NewBookingRepositoryImpl(db *gorm.DB) *BookingRepositoryImpl {
	return &BookingRepositoryImpl{db: db}
}

var _ port.BookingRepository = (*BookingRepositoryImpl)(nil)

func (r *BookingRepositoryImpl) GetByID(ctx context.Context, id int64) (*domain.Booking, error) {
	var dm datamodel.BookingDataModel
	err := r.db.WithContext(ctx).First(&dm, id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return mapper.ToDomain(&dm)
}

func (r *BookingRepositoryImpl) Save(ctx context.Context, booking *domain.Booking) (*domain.Booking, error) {
	dm := mapper.ToDataModel(booking)
	if err := r.db.WithContext(ctx).Save(dm).Error; err != nil {
		return nil, err
	}
	return mapper.ToDomain(dm)
}
```

### 外部依賴 Adapter `<category>/<provider>_<concept>_adapter.go`

以 `client/` 為例(`messaging/`、`cache/`、`notification/`、`storage/` 套用同一個模板,只換子目錄、Port 介面、error 型別名稱):

```go
package client

import (
	"context"
	"fmt"

	"<basePackage>/internal/domain/booking"
	"<basePackage>/internal/usecase/booking/port"
)

type PaymentClientError struct {
	Message string
	Cause   error
}

func (e *PaymentClientError) Error() string { return fmt.Sprintf("%s: %v", e.Message, e.Cause) }
func (e *PaymentClientError) Unwrap() error  { return e.Cause }

type StripePaymentAdapter struct {
	apiKey string
}

func NewStripePaymentAdapter(apiKey string) *StripePaymentAdapter {
	return &StripePaymentAdapter{apiKey: apiKey}
}

var _ port.PaymentClient = (*StripePaymentAdapter)(nil)

func (a *StripePaymentAdapter) Charge(ctx context.Context, booking *domain.Booking) (string, error) {
	// 呼叫 Stripe SDK
	chargeID, err := stripeSDKCharge(ctx, a.apiKey, booking)
	if err != nil {
		return "", &PaymentClientError{Message: "failed to charge via Stripe", Cause: err}
	}
	return chargeID, nil
}
```

### 事件發送器 `event/in_process_event_publisher.go`

```go
package event

import (
	"context"

	"<basePackage>/internal/usecase/booking/port"
)

// EventHandler 處理單一領域事件;回傳的 error 會中止後續 handler 並往上回傳。
type EventHandler func(ctx context.Context, event any) error

type InProcessEventPublisher struct {
	handlers []EventHandler
}

func NewInProcessEventPublisher(handlers ...EventHandler) *InProcessEventPublisher {
	return &InProcessEventPublisher{handlers: handlers}
}

var _ port.DomainEventPublisher = (*InProcessEventPublisher)(nil)

func (p *InProcessEventPublisher) Publish(ctx context.Context, event any) error {
	if event == nil {
		return nil
	}
	for _, handler := range p.handlers {
		if err := handler(ctx, event); err != nil {
			return err
		}
	}
	return nil
}
```
