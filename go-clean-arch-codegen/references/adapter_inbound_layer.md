# Adapter/Inbound 層 — 通訊與應用進入點(Interface Adapters,被外部驅動的一側)

## 規則

1. Gin 的 `*gin.Context`、路由註冊只出現在本層。
2. Handler 方法固定三步:解析參數(path param / `ShouldBindJSON`)→ 呼叫 UseCase(Inbound Port)→ 寫回 JSON;方法內零業務判斷,出錯一律 `c.Error(err); return`,不自己組錯誤 JSON、不自己決定狀態碼(由 `internal/adapter/inbound/http/middleware.ErrorHandler()` 統一處理,見 `references/architecture.md`)。
3. Handler 依賴 UseCase **介面**(`port.<Action><Entity>UseCase`,不是 Impl),建構函式注入;每個 use case 情境是獨立的窄介面,Handler 有幾個 endpoint 就注入幾個對應的 UseCase 介面欄位,不共用一個大介面。
4. `<Action>Command` 定義在 **usecase 層**(`usecase.<entity>.command`,見 `references/usecase_layer.md`),不在本層;Handler 直接 import 使用,不自己另外定義一份,用 `c.ShouldBindJSON(&cmd)` 綁定並自動套用 Command 上的 `binding` tag 驗證。
5. Response 包裝 Usecase 回傳的 `<Entity>Result`(不是 Domain 物件);提供 `NewResponseFrom(result.<Entity>Result) Response` 工廠函式;Domain 物件與其業務方法不可流出 Usecase 邊界,本層一律不 import `domain` package;不叫 `Dto`。**本層 package 名稱是 entity 本身(如 `package booking`),型別不重複加 entity 前綴**(`Response`、`Handler`,不是 `BookingResponse`、`BookingHandler`)——見 `references/architecture.md` 的命名例外說明。
6. 狀態碼:建立回 `http.StatusCreated`(201)、查詢/更新回 `http.StatusOK`(200)、刪除回 `http.StatusNoContent`(204)。
7. `middleware.ErrorHandler()` 在整個 router 上全域註冊一次(`router.Use(middleware.ErrorHandler())`),固定處理四類:`*usecaseerr.NotFoundError` → 404、`validator.ValidationErrors`(來自 `ShouldBindJSON` 綁定失敗)→ 400、`domainerr.ErrInvalidState` / `domainerr.ErrInvalidArgument` → 400、其他 → 500;錯誤回應格式固定為 `{"error": "<message>"}`。這個檔案是共用基礎設施,專案內只生成一次,見 `references/architecture.md`。
8. URL 命名:`/api/<entities>`(複數、kebab-case);路徑參數用 `c.Param("id")` 取得後 `strconv.ParseInt` 轉型。
9. **測試走 e2e,不 mock Inbound Port**:`<entity>/handler_test.go` 把真實的 Repository(接 `references/architecture.md` 的 `testsupport.NewMariaDBTestDB` 啟動的 MariaDB testcontainer)、真實的 UseCase Impl、真實的 Handler 全部串起來,對一個掛好 `middleware.ErrorHandler()` 的 `gin.Engine` 發真實 HTTP request——目標是盡量測完整條路線(HTTP → Handler → UseCase → Repository → DB),不是只測 Handler 這一層的參數轉換。UseCase 用到的外部服務有對應的 testcontainers 模組(Redis、Kafka、MinIO 等)就一併啟動真實 container、注入真實 Adapter;沒有可信賴映像的第三方 SaaS API(Stripe、Twilio 這類,分類在 `client`/`notification`)才 fallback 用 `testify/mock` 假冒那一個 Outbound Port,其餘依賴維持真實——是否可 container 化的判斷依據見下方模板的對照表。斷言不能只看 HTTP 回應,要再用 Repository 查一次資料庫,確認資料真的被寫成預期的樣子。這類測試需要 Docker,用 `//go:build integration` 跟預設的快速單元測試分開,不影響 `go test ./...`;執行時用 `go test -tags=integration ./...`。

## 產出檔案(依序)

1. `<entity>/response.go`
2. `<entity>/handler.go`(+ `<entity>/handler_test.go`,如有測試描述)
3. `middleware/error_handler.go`(僅專案第一次使用本 skill 時產生,見 `references/architecture.md`)

`<entity>/handler_test.go` 依賴 `internal/testsupport`(共用基礎設施,見 `references/architecture.md`),該套件若專案尚未產生則一併產生。

`<Action>Command` 在 usecase 層產生(見 `references/usecase_layer.md`),本層不重複產出。

## 模板

### Response `<entity>/response.go`

```go
package booking

import "<basePackage>/internal/usecase/booking/result"

type Response struct {
	ID     int64  `json:"id"`
	Field  Type   `json:"field"`
	Status string `json:"status"`
}

func NewResponseFrom(r result.BookingResult) Response {
	return Response{ID: r.ID, Field: r.Field, Status: r.Status}
}
```

### Handler `<entity>/handler.go`

Handler 不 import `domain` package——它只認識 `<Action>Command`(從 usecase 層 import,不自己定義)、`<Entity>Result`(Usecase 的輸出)、`Response`(自己的輸出),完全看不到 Domain。每個 endpoint 對應一個獨立的 `<Action><Entity>UseCase` 介面欄位,建構函式注入時一個 endpoint 一個依賴,不共用一個大介面。Command 物件整個直接傳給 UseCase 方法,不在 Handler 拆欄位:

```go
package booking

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"<basePackage>/internal/usecase/booking/command"
	"<basePackage>/internal/usecase/booking/port"
)

type Handler struct {
	createBookingUseCase  port.CreateBookingUseCase
	confirmBookingUseCase port.ConfirmBookingUseCase
	getBookingUseCase     port.GetBookingUseCase
}

func NewHandler(
	createBookingUseCase port.CreateBookingUseCase,
	confirmBookingUseCase port.ConfirmBookingUseCase,
	getBookingUseCase port.GetBookingUseCase,
) *Handler {
	return &Handler{
		createBookingUseCase:  createBookingUseCase,
		confirmBookingUseCase: confirmBookingUseCase,
		getBookingUseCase:     getBookingUseCase,
	}
}

// RegisterRoutes 掛載這個 entity 的所有 endpoint;由 composition root 的 router 統一呼叫。
func (h *Handler) RegisterRoutes(rg *gin.RouterGroup) {
	rg.POST("", h.Create)
	rg.PUT("/:id/confirm", h.Confirm)
	rg.GET("/:id", h.GetByID)
}

// POST 建立 → 201
func (h *Handler) Create(c *gin.Context) {
	var cmd command.CreateBookingCommand
	if err := c.ShouldBindJSON(&cmd); err != nil {
		c.Error(err)
		return
	}

	result, err := h.createBookingUseCase.Create(c.Request.Context(), cmd)
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusCreated, NewResponseFrom(result))
}

// PUT 狀態變更 → 200
func (h *Handler) Confirm(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.Error(err)
		return
	}

	result, err := h.confirmBookingUseCase.Confirm(c.Request.Context(), id)
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusOK, NewResponseFrom(result))
}

// GET 查詢單筆 → 200
func (h *Handler) GetByID(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.Error(err)
		return
	}

	result, err := h.getBookingUseCase.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusOK, NewResponseFrom(result))
}
```

### 全域錯誤處理 middleware

模板與產出時機見 `references/architecture.md` 的「共用基礎設施」章節——這是 `middleware.ErrorHandler()`,不是每個 entity 各自的檔案,不要重複產生。

## e2e 測試模板(規格含測試描述時產生)

### 依賴要不要真的用 container,還是 fallback mock

| Outbound Port 分類 | 範例 | 有無常見 testcontainers 模組 | 測試裡怎麼接 |
|---|---|---|---|
| Repository(DB) | `<Entity>Repository` | 有(`testcontainers-go/modules/mariadb`) | 一律真實 container + 真實 `<Entity>RepositoryImpl`,見 `testsupport.NewMariaDBTestDB` |
| `cache` | `<Concept>CacheStore` | 有(`testcontainers-go/modules/redis`) | 真實 container + 真實 Adapter |
| `messaging` | `<Concept>MessagePublisher` | 有(`testcontainers-go/modules/kafka`、`rabbitmq`) | 真實 container + 真實 Adapter |
| `storage` | `<Concept>FileStorage` | 有(MinIO image,用通用 `testcontainers-go` container API) | 真實 container + 真實 Adapter,指向 MinIO endpoint |
| `client` / `notification` | `PaymentClient`、`SmsNotificationSender` | 通常沒有可信賴映像(第三方 SaaS API,如 Stripe、Twilio) | `testify/mock` 假冒該 Outbound Port,其餘依賴維持真實 |
| 領域事件 | `DomainEventPublisher` | 不需要,本來就是 in-process | 直接用真實 `InProcessEventPublisher` |

### 全真實依賴的情境 `<entity>/handler_test.go`

以 `Confirm` 為例——這個 use case 只依賴 Repository 和 in-process 事件,兩者都不需要 fallback mock:

```go
//go:build integration

package booking

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"<basePackage>/internal/adapter/inbound/http/middleware"
	"<basePackage>/internal/adapter/outbound/repository"
	"<basePackage>/internal/adapter/outbound/repository/datamodel"
	"<basePackage>/internal/domain/booking"
	"<basePackage>/internal/testsupport"
	"<basePackage>/internal/usecase/booking"
	"<basePackage>/internal/usecase/booking/event"
)

func TestHandler_Confirm(t *testing.T) {
	gin.SetMode(gin.TestMode)

	db := testsupport.NewMariaDBTestDB(t, &datamodel.BookingDataModel{})
	repo := repository.NewBookingRepositoryImpl(db)
	publisher := event.NewInProcessEventPublisher() // 這個情境不需要額外 handler

	seed, err := domain.NewBooking(0, "field", domain.StatusPending)
	require.NoError(t, err)
	saved, err := repo.Save(context.Background(), seed)
	require.NoError(t, err)

	confirmUseCase := usecase.NewConfirmBookingUseCaseImpl(repo, publisher)
	handler := NewHandler(nil, confirmUseCase, nil)

	router := gin.New()
	router.Use(middleware.ErrorHandler())
	router.PUT("/bookings/:id/confirm", handler.Confirm)

	req := httptest.NewRequest(http.MethodPut, fmt.Sprintf("/bookings/%d/confirm", saved.ID()), nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)

	// 不能只看回應——直接查資料庫確認狀態真的被寫進去
	persisted, err := repo.GetByID(context.Background(), saved.ID())
	require.NoError(t, err)
	assert.Equal(t, domain.StatusConfirmed, persisted.Status())
}
```

### 有第三方 SaaS 依賴的情境(hybrid:真實 Repository + mock Client)

假設 `Create` 這個 use case 除了 `BookingRepository` 還依賴 `PaymentClient`(對照表分類在 `client`,沒有可信賴的 testcontainers 映像)。Repository 仍然接真實 MariaDB,只有 `PaymentClient` 用 `testify/mock` 假冒,注入同一個真實的 UseCase Impl:

```go
//go:build integration

package booking

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"<basePackage>/internal/adapter/inbound/http/middleware"
	"<basePackage>/internal/adapter/outbound/repository"
	"<basePackage>/internal/adapter/outbound/repository/datamodel"
	"<basePackage>/internal/domain/booking"
	"<basePackage>/internal/testsupport"
	"<basePackage>/internal/usecase/booking"
	"<basePackage>/internal/usecase/booking/event"
)

type mockPaymentClient struct {
	mock.Mock
}

func (m *mockPaymentClient) Charge(ctx context.Context, b *domain.Booking) (string, error) {
	args := m.Called(ctx, b)
	return args.String(0), args.Error(1)
}

func TestHandler_Create(t *testing.T) {
	gin.SetMode(gin.TestMode)

	db := testsupport.NewMariaDBTestDB(t, &datamodel.BookingDataModel{})
	repo := repository.NewBookingRepositoryImpl(db)
	publisher := event.NewInProcessEventPublisher()

	paymentClient := new(mockPaymentClient)
	paymentClient.On("Charge", mock.Anything, mock.Anything).Return("charge_123", nil)

	createUseCase := usecase.NewCreateBookingUseCaseImpl(repo, paymentClient, publisher)
	handler := NewHandler(createUseCase, nil, nil)

	router := gin.New()
	router.Use(middleware.ErrorHandler())
	router.POST("/bookings", handler.Create)

	body := `{"field":"value"}`
	req := httptest.NewRequest(http.MethodPost, "/bookings", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusCreated, rec.Code)
	paymentClient.AssertExpectations(t)

	// 真實 Repository 落地確認:資料庫裡確實多了一筆
	var count int64
	require.NoError(t, db.Model(&datamodel.BookingDataModel{}).Count(&count).Error)
	assert.Equal(t, int64(1), count)
}
```
