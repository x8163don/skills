# Usecase 層 — 業務案例與介面合約

## 規則

1. 只 `use` Domain 型別、本層(usecase)型別、`std::sync::Arc`;不 `use` `tauri::*`(Tauri command 屬於 adapter/inbound,見 `references/adapter_inbound_layer.md`)也不 `use` `rusqlite::*`(屬於 adapter/outbound)。這是本層唯一的框架邊界規則:usecase 只認識 trait,不認識 trait 背後的技術實作。
2. 先定義 Outbound Ports(Repository、外部依賴、事件發送)為 trait,再定義 Inbound Port,最後實作對應的 UseCaseImpl。**每個 use case 情境(每條 Business Rule 或每個查詢需求)各自一個 Inbound Port trait + 一個 Impl struct,不共用一個大 trait**:trait 命名 `<Action><Entity>UseCase`(如 `CreateBookingUseCase`、`ConfirmBookingUseCase`、`GetBookingUseCase`),各自只宣告一個方法;Impl 命名 `<Action><Entity>UseCaseImpl`,只依賴自己需要的 Outbound Port,不共用一個大 Impl。
3. 所有依賴以 `Arc<dyn Trait + Send + Sync>` 欄位持有,建構子 `pub fn new(...) -> Self` 注入;Impl struct 本身無內部可變狀態(狀態都在 Repository 背後的資料庫)。`Send + Sync` 是必要的,因為 Tauri command 可能在不同執行緒被呼叫,`tauri::State` 要求其管理的型別滿足 `Send + Sync`。
4. **錯誤一律回傳專案級共用的 `AppError`**(本檔案 `error.rs`,只在整個專案第一次使用本 skill 時產生一次,後續 entity 直接 `use crate::usecase::error::AppError;` 重用),不是每個 entity 各自定義例外型別。查詢單筆一律 `repository.get_by_id(id)?.ok_or(AppError::NotFound { entity: "Booking", id })`——Repository 的 `Result<Option<T>, AppError>` 用 `?` 往上傳遞底層錯誤,`None` 才轉成 `NotFound`。
5. 領域事件在寫入成功之後 publish;事件用 `#[derive(Debug, Clone)]` struct 定義在 `usecase::<entity>::event`。
6. Repository Port 的標準方法簽名:`fn get_by_id(&self, id: i64) -> Result<Option<Booking>, AppError>`、`fn save(&self, booking: Booking) -> Result<Booking, AppError>`,查詢條件方法命名為 `get_by_<field>`。樹狀結構等需要交易保護的操作(如本專案 focuson 的 nested-set 任務樹),Outbound Port 直接宣告該操作的完整方法(如 `fn insert_node(&self, ...) -> Result<Task, AppError>`),交易邊界的管理留在 Adapter/Outbound 的實作內(`Connection::transaction()`),Usecase 層不需要知道底層用不用交易。
7. **Inbound Port 的方法一律回傳 `<Entity>Result` 家族型別,不直接回傳 Domain `<Entity>`**:Domain 物件(及其業務方法)只能在 Usecase 內部與 Repository 之間流動,絕不可流出 Usecase 邊界。UseCaseImpl 內部正常操作 Domain(呼叫業務方法、`save()`),方法回傳前才用 `<Entity>Result::from(&domain)` 轉換。Result 用 struct 定義,無業務方法,`#[derive(Debug, Clone, serde::Serialize)]`(要跨 Tauri IPC 回傳給前端,這是本層唯一需要 derive `Serialize` 的理由);命名依用途:
   - 預設(單筆查詢/寫入後回傳完整資料):`<Entity>Result`
   - 列表查詢、欄位精簡:`<Entity>SummaryResult`
   - 特定 use case 需要客製欄位(如包含關聯資料):依實際需求命名,不勉強套單一模板
8. **`usecase/<entity>/` 目錄下只放 use case impl 檔案(`<action>_<entity>.rs`,一個 use case 一個)**,其餘依類型分子目錄,點進去就能一眼看到這個 entity 有哪些 use case、各自的設計內容而不必打開實作:
   - `port/`:所有 trait——每個 use case 的 Inbound Port(`<Action><Entity>UseCase`)與全部 Outbound Port(`<Entity>Repository`、`<Concept>Client` 等、`DomainEventPublisher`)
   - `result/`:`<Entity>Result` 家族(Usecase 輸出型別)
   - `command/`:`<Action>Command` 家族(Usecase 輸入型別,規則 9)
   - `event/`:領域事件
9. **寫入型 use case 的輸入型別 `<Action>Command` 定義在本層**(`usecase::<entity>::command`),不在 Adapter/Inbound:跟 Result 對稱,同樣是 Usecase 自己擁有的邊界資料結構,`#[derive(Debug, Clone, serde::Deserialize)]`(從 Tauri 前端傳入,這是本層唯一需要 derive `Deserialize` 的理由)。Inbound Port 方法直接以 `<Action>Command` 為參數(不拆欄位傳原始型別),Adapter 層的 `#[tauri::command]` 函式直接 import 這個 Command 使用,不自己另外定義一份。單一 ID 這種簡單查詢/狀態變更(如 `confirm(id: i64)`、`get_by_id(id: i64)`)不需要包 Command,直接傳 `i64` 即可。

## 產出檔案(依序)

0. `error.rs`(**專案級共用,只在第一次使用本 skill 時產生**;已存在則跳過,見下方模板)
1. `port/<entity>_repository.rs`(Outbound Port)
2. `port/<concept>_client.rs` 等(Outbound Port,依外部依賴性質擇一,如有;見 `references/adapter_outbound_layer.md` 的分類表)
3. `port/domain_event_publisher.rs`(Outbound Port,**專案級共用**,如有事件且尚未產生過)
4. `event/<entity>_<action>_event.rs`(如有事件)
5. `result/<entity>_result.rs`(+ 其他 Result 變體,依規則 7 擇一或並存)
6. `command/<action>_command.rs`(每個需要輸入資料的 use case 一個,依規則 9)
7. 對每個 use case 情境重複:`port/<action>_<entity>_use_case.rs`(Inbound Port)+ `<action>_<entity>.rs`(Impl,直接放在 `usecase/<entity>/` 目錄下)
8. `mod.rs`(宣告以上所有子模組)

## 模板

### 專案級共用錯誤 `usecase/error.rs`(只產生一次)

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("{entity} not found for id {id}")]
    NotFound { entity: &'static str, id: i64 },

    #[error("invalid state for {entity}: {reason}")]
    InvalidState { entity: &'static str, reason: String },

    #[error("invalid argument {field}: {reason}")]
    InvalidArgument { field: &'static str, reason: String },

    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
}

/// Domain 層專用的錯誤子集——建構子與業務方法只可能觸發驗證類錯誤,
/// 不會觸碰資料庫,因此不需要看到 `AppError::Db`/`NotFound`。
pub type DomainError = AppError;
```

若專案的 Domain 錯誤情境跟 Usecase/Adapter 錯誤情境需要更嚴格分開(例如 Domain 完全不該知道 `rusqlite::Error` 存在),可以把 `DomainError` 拆成獨立的 enum,再由 Usecase 層用 `impl From<DomainError> for AppError` 轉換;預設先用型別別名保持簡單,专案變複雜時再拆分。

`AppError` 未 derive `Serialize`——Tauri v2 要求 command 的 `Err` 型別實作 `Serialize`,因此**每個使用本 skill 的專案**還需要在這個檔案補一個序列化轉換,固定做法是額外定義一個「錯誤代碼」struct:

```rust
#[derive(Debug, Clone, serde::Serialize)]
pub struct AppErrorPayload {
    pub kind: &'static str,   // "NotFound" | "InvalidState" | "InvalidArgument" | "Db"
    pub message: String,
}

impl From<&AppError> for AppErrorPayload {
    fn from(err: &AppError) -> Self {
        let kind = match err {
            AppError::NotFound { .. } => "NotFound",
            AppError::InvalidState { .. } => "InvalidState",
            AppError::InvalidArgument { .. } => "InvalidArgument",
            AppError::Db(_) => "Db",
        };
        Self { kind, message: err.to_string() }
    }
}
```

`#[tauri::command]` 函式回傳 `Result<T, AppErrorPayload>`(見 `references/adapter_inbound_layer.md`),讓前端能依 `kind` 分流處理,而不是字串比對。

### Outbound Port — Repository

```rust
use crate::domain::booking::Booking;
use crate::usecase::error::AppError;

pub trait BookingRepository: Send + Sync {
    fn get_by_id(&self, id: i64) -> Result<Option<Booking>, AppError>;
    fn save(&self, booking: Booking) -> Result<Booking, AppError>;
}
```

### Outbound Port — 外部依賴(Client / Messaging / Cache / Notification / Storage)

依外部依賴的性質選擇 trait 命名(見 `references/adapter_outbound_layer.md` 的分類表),方法簽名皆相同模式,以 Client(呼叫外部 API/SDK)為例:

```rust
use crate::domain::booking::Booking;
use crate::usecase::error::AppError;

pub trait PaymentClient: Send + Sync {
    fn charge(&self, booking: &Booking) -> Result<String, AppError>;
}
```

其餘分類 trait 命名同樣模式:`<Concept>MessagePublisher`(訊息佇列)、`<Concept>CacheStore`(快取)、`<Concept>NotificationSender`(通知)、`<Concept>FileStorage`(檔案儲存),module 皆為 `usecase::<entity>::port`。

### Outbound Port — 事件發送(專案級共用,只產生一次)

方法簽名不能用 `impl Serialize` 這種泛型參數——那會讓 trait 失去物件安全(object safety),導致 `Arc<dyn DomainEventPublisher>` 這種建構子注入寫法直接編譯失敗。改用 `serde_json::Value`(呼叫端自行先 `serde_json::to_value(&event)` 轉換好再傳入),trait 才能被當成 trait object 使用:

```rust
pub trait DomainEventPublisher: Send + Sync {
    fn publish(&self, event_name: &str, payload: serde_json::Value);
}
```

### 領域事件

```rust
#[derive(Debug, Clone, serde::Serialize)]
pub struct BookingConfirmedEvent {
    pub booking_id: i64,
    pub account_id: i64,
}
```

### Result(Usecase 輸出型別,取代直接回傳 Domain)

```rust
use crate::domain::booking::Booking;

#[derive(Debug, Clone, serde::Serialize)]
pub struct BookingResult {
    pub id: i64,
    pub account_id: i64,
    pub status: String,
}

impl From<&Booking> for BookingResult {
    fn from(booking: &Booking) -> Self {
        Self {
            id: booking.id(),
            account_id: booking.account_id(),
            status: format!("{:?}", booking.status()),
        }
    }
}
```

列表查詢用的精簡變體(欄位依實際需求增減):

```rust
#[derive(Debug, Clone, serde::Serialize)]
pub struct BookingSummaryResult {
    pub id: i64,
    pub status: String,
}

impl From<&Booking> for BookingSummaryResult {
    fn from(booking: &Booking) -> Self {
        Self { id: booking.id(), status: format!("{:?}", booking.status()) }
    }
}
```

### Command(Usecase 輸入型別,與 Result 對稱)

跟 Result 一樣用 struct 定義,無業務方法;欄位驗證在 Impl 內用 Domain 的 `new()`/業務方法天然完成(Rust 生態沒有等同 `jakarta.validation` 的欄位級註解慣例,驗證邏輯留給 Domain 層負責,不在 Command 上重複一份):

```rust
#[derive(Debug, Clone, serde::Deserialize)]
pub struct CreateBookingCommand {
    pub account_id: i64,
}
```

### Inbound Port(每個 use case 情境一個檔案)

每個 trait 只宣告**一個方法**,不 `use` Domain `Booking`——方法簽名只暴露 Result(和需要時的 Command),呼叫方(Tauri command 函式)因此也不需要認識 Domain。以帶輸入資料的寫入型(`CreateBookingUseCase`)、只靠 id 的寫入型(`ConfirmBookingUseCase` 風格)、查詢型(`GetBookingUseCase`)各一個為例:

```rust
use crate::usecase::booking::command::create_booking_command::CreateBookingCommand;
use crate::usecase::booking::result::booking_result::BookingResult;
use crate::usecase::error::AppError;

pub trait CreateBookingUseCase: Send + Sync {
    fn create(&self, command: CreateBookingCommand) -> Result<BookingResult, AppError>;
}
```

```rust
use crate::usecase::booking::result::booking_result::BookingResult;
use crate::usecase::error::AppError;

pub trait ConfirmBookingUseCase: Send + Sync {
    fn confirm(&self, booking_id: i64) -> Result<BookingResult, AppError>;
}
```

```rust
use crate::usecase::booking::result::booking_result::BookingResult;
use crate::usecase::error::AppError;

pub trait GetBookingUseCase: Send + Sync {
    fn get_by_id(&self, booking_id: i64) -> Result<BookingResult, AppError>;
}
```

### UseCase 實作(每個 use case 情境一個檔案,直接放在 `usecase/<entity>/` 目錄下)

帶 Command 的寫入型 Impl:

```rust
use std::sync::Arc;

use crate::domain::booking::{Booking, BookingStatus};
use crate::usecase::booking::command::create_booking_command::CreateBookingCommand;
use crate::usecase::booking::port::booking_repository::BookingRepository;
use crate::usecase::booking::port::create_booking_use_case::CreateBookingUseCase;
use crate::usecase::booking::result::booking_result::BookingResult;
use crate::usecase::error::AppError;

pub struct CreateBookingUseCaseImpl {
    booking_repository: Arc<dyn BookingRepository>,
}

impl CreateBookingUseCaseImpl {
    pub fn new(booking_repository: Arc<dyn BookingRepository>) -> Self {
        Self { booking_repository }
    }
}

impl CreateBookingUseCase for CreateBookingUseCaseImpl {
    fn create(&self, command: CreateBookingCommand) -> Result<BookingResult, AppError> {
        let booking = Booking::new(0, command.account_id, BookingStatus::Pending)?;
        let saved = self.booking_repository.save(booking)?;
        Ok(BookingResult::from(&saved))
    }
}
```

只靠 id、不需要 Command 的寫入型 Impl,只依賴自己需要的 Outbound Port(不強塞其他 use case 用不到的依賴):

```rust
use std::sync::Arc;

use crate::usecase::booking::event::booking_confirmed_event::BookingConfirmedEvent;
use crate::usecase::booking::port::booking_repository::BookingRepository;
use crate::usecase::booking::port::confirm_booking_use_case::ConfirmBookingUseCase;
use crate::usecase::booking::port::domain_event_publisher::DomainEventPublisher;
use crate::usecase::booking::result::booking_result::BookingResult;
use crate::usecase::error::AppError;

pub struct ConfirmBookingUseCaseImpl {
    booking_repository: Arc<dyn BookingRepository>,
    event_publisher: Arc<dyn DomainEventPublisher>,
}

impl ConfirmBookingUseCaseImpl {
    pub fn new(
        booking_repository: Arc<dyn BookingRepository>,
        event_publisher: Arc<dyn DomainEventPublisher>,
    ) -> Self {
        Self { booking_repository, event_publisher }
    }
}

impl ConfirmBookingUseCase for ConfirmBookingUseCaseImpl {
    fn confirm(&self, booking_id: i64) -> Result<BookingResult, AppError> {
        let mut booking = self
            .booking_repository
            .get_by_id(booking_id)?
            .ok_or(AppError::NotFound { entity: "Booking", id: booking_id })?;

        booking.confirm()?;                                    // 1. 呼叫 Domain 業務方法
        let saved = self.booking_repository.save(booking)?;     // 2. 持久化

        // 3. 保存成功後發送領域事件
        self.event_publisher.publish(
            "booking-confirmed",
            &BookingConfirmedEvent { booking_id: saved.id(), account_id: saved.account_id() },
        );

        // 4. Domain 到此為止,轉成 Result 才回傳給外層(Adapter 不可見 Domain)
        Ok(BookingResult::from(&saved))
    }
}
```

查詢型 Impl:不呼叫 `save()`、不 publish 事件、不需要 `DomainEventPublisher` 依賴:

```rust
use std::sync::Arc;

use crate::usecase::booking::port::booking_repository::BookingRepository;
use crate::usecase::booking::port::get_booking_use_case::GetBookingUseCase;
use crate::usecase::booking::result::booking_result::BookingResult;
use crate::usecase::error::AppError;

pub struct GetBookingUseCaseImpl {
    booking_repository: Arc<dyn BookingRepository>,
}

impl GetBookingUseCaseImpl {
    pub fn new(booking_repository: Arc<dyn BookingRepository>) -> Self {
        Self { booking_repository }
    }
}

impl GetBookingUseCase for GetBookingUseCaseImpl {
    fn get_by_id(&self, booking_id: i64) -> Result<BookingResult, AppError> {
        let booking = self
            .booking_repository
            .get_by_id(booking_id)?
            .ok_or(AppError::NotFound { entity: "Booking", id: booking_id })?;
        Ok(BookingResult::from(&booking))
    }
}
```

## 測試

Usecase 層本身不產生獨立測試檔案。它只做 orchestration(呼叫 Outbound Port、串業務規則、決定何時 publish 事件),不藏業務邏輯,所以它的正確性由兩個更值得投資的測試層級涵蓋:業務規則本身由 Domain aggregate test 驗證,它有沒有正確呼叫 Repository/Publisher 則由 Adapter/Inbound 層的 command-level 整合測試(用真實 rusqlite 連線,不 mock)驗證。用 `mockall` 對 Outbound Port 做假物件測試,測的只是「有沒有呼叫到 mock」,一旦 mock 行為跟真實 `RepositoryImpl` 兜不起來就會產生假陽性——完整理由與另外兩層測試該怎麼寫,見 `references/testing_principles.md`。
