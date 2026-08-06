# Adapter/Outbound 層 — 外部基礎設施整合(Interface Adapters,驅動內層依賴的一側)

本層不產生獨立的 Repository/Mapper 測試——它的正確性由 `references/adapter_inbound_layer.md` 的 command-level 整合測試(用真實 rusqlite 連線)一併涵蓋,原則見 `references/testing_principles.md`。

## 規則

1. rusqlite 沒有 ORM 巨集(不像 JPA `@Entity`、GORM struct tag),所以 `<Entity>DataModel` 是一個普通 struct,對映邏輯是手寫的 `from_row(row: &rusqlite::Row) -> rusqlite::Result<Self>` 關聯函式,不是註解。命名一律叫 `<Entity>DataModel`,不叫 `<Entity>Entity`——避免跟 Domain 的 `<Entity>` 混淆。
2. `<entity>_mapper` 是一個 module,底下是 module-level 純函式(`to_domain` / `to_data_model`),不是 struct、不持有狀態、不需要注入——這跟 Java 的 static 方法、Go 的 package-level 函式是同一個意圖(語言慣用法不同,設計意圖相同)。
3. `<Entity>RepositoryImpl` 實作 Usecase 的 `<Entity>Repository`(Outbound Port),內部持有 `Arc<Mutex<rusqlite::Connection>>`——`rusqlite::Connection` 不是 `Sync`,而 Tauri 的 `#[tauri::command]` 可能在不同執行緒被呼叫,所以連線一定要包在 `Mutex` 裡,並以 `Arc` 讓多個 Repository/Adapter 共享同一條連線(整個 app 通常只開一條 SQLite 連線,由 `tauri::Builder::manage(Arc::new(Mutex::new(connection)))` 統一持有,各 RepositoryImpl 的建構子把它接進來)。
4. 涉及多筆寫入、需要保持一致性的操作(如樹狀結構的插入/搬移/刪除),`<Entity>RepositoryImpl` 內部用 `connection.transaction()?` 開交易,所有寫入呼叫 `tx.execute(...)`,操作完 `tx.commit()?`;任何一步失敗直接用 `?` 提早返回,`Transaction` 的 `Drop` 會自動 rollback,不需要手動處理。
5. 外部 SDK(Stripe、Kafka、Redis 等)只在對應的 `adapter/outbound/<category>` 子 module 內 `use`;SDK 錯誤在此層捕捉,轉為 `AppError`(見 `references/usecase_layer.md` 規則 4)——直接用 `map_err` 轉換,不需要每個 provider 各自定義一個新的錯誤型別,除非該 SDK 錯誤需要保留額外上下文(這種情況才用 `#[error(...)] #[from]` 加一個 variant 到 `AppError`,不是另開新 enum)。
6. 除 Repository 外的外部依賴一律命名為 `<Provider><Concept>Adapter`(不用 `*ServiceImpl`/`*Impl`);設定值透過建構子參數傳入(對應 Java 的 `@Value`、Go 的環境變數讀取,Rust 沒有內建設定注入機制,由呼叫端在 `main.rs`/`lib.rs` 組裝時決定值從哪裡讀,如 `std::env::var` 或 `tauri::Config`)。
7. 依外部依賴的性質分類到對應子 module,Outbound Port 與 Adapter 命名對照:

   | 子 module | Outbound Port(usecase 層 trait) | Adapter 實作 | 範例 |
   |---|---|---|---|
   | `client/` | `<Concept>Client` | `<Provider><Concept>Adapter` | `PaymentClient` → `StripePaymentAdapter` |
   | `messaging/` | `<Concept>MessagePublisher` | `<Provider><Concept>Adapter` | `OrderMessagePublisher` → `KafkaOrderAdapter` |
   | `cache/` | `<Concept>CacheStore` | `<Provider><Concept>Adapter` | `BookingCacheStore` → `RedisBookingAdapter` |
   | `notification/` | `<Concept>NotificationSender` | `<Provider><Concept>Adapter` | `SmsNotificationSender` → `TwilioSmsAdapter` |
   | `storage/` | `<Concept>FileStorage` | `<Provider><Concept>Adapter` | `AttachmentFileStorage` → `S3AttachmentAdapter` |

   五類結構完全相同(見下方模板),只有子 module、Port trait 名稱不同。桌面應用通常用不到這五類(focuson 目前只有 Repository + 事件發送),保留這個分類表是為了讓本 skill 對其他 Rust 專案(不只 focuson)一樣適用。
8. 事件發送使用 `TauriEventPublisher`,以 `tauri::AppHandle::emit` 實作 Usecase 的 `DomainEventPublisher`——這是**專案級共用檔案,只產生一次**,之後每個 use case 的事件發送都重用同一個 struct,不必每個 entity 各自寫一個。

## 產出檔案(依序)

1. `data_model/<entity>_data_model.rs`
2. `mapper/<entity>_mapper.rs`
3. `<entity>_repository_impl.rs`
4. `<category>/<provider>_<concept>_adapter.rs`(如有 Client/Messaging/Cache/Notification/Storage Port,`<category>` 依規則 7 的分類表擇一)
5. `event/tauri_event_publisher.rs`(**專案級共用**,如有事件 Port 且尚未產生過)
6. 各層級 `mod.rs`(宣告子模組)

## 模板

### rusqlite Row 對映 struct `repository/data_model/<entity>_data_model.rs`

```rust
pub struct BookingDataModel {
    pub id: i64,
    pub account_id: i64,
    pub status: String,   // enum 一律以 TEXT 儲存(Debug 或自訂 to_string())
}

impl BookingDataModel {
    pub fn from_row(row: &rusqlite::Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get("id")?,
            account_id: row.get("account_id")?,
            status: row.get("status")?,
        })
    }
}
```

### 對映器 `repository/mapper/<entity>_mapper.rs`

```rust
use crate::adapter::outbound::repository::data_model::booking_data_model::BookingDataModel;
use crate::domain::booking::{Booking, BookingStatus};
use crate::usecase::error::AppError;

pub fn to_domain(data_model: BookingDataModel) -> Result<Booking, AppError> {
    let status = match data_model.status.as_str() {
        "Pending" => BookingStatus::Pending,
        "Confirmed" => BookingStatus::Confirmed,
        "Cancelled" => BookingStatus::Cancelled,
        other => {
            return Err(AppError::InvalidState {
                entity: "Booking",
                reason: format!("unknown status in database: {other}"),
            })
        }
    };
    Booking::new(data_model.id, data_model.account_id, status)
}

pub fn to_data_model(booking: &Booking) -> BookingDataModel {
    BookingDataModel {
        id: booking.id(),
        account_id: booking.account_id(),
        status: format!("{:?}", booking.status()),
    }
}
```

### Outbound Port 實作 `repository/<entity>_repository_impl.rs`

```rust
use std::sync::{Arc, Mutex};

use rusqlite::{params, Connection};

use crate::adapter::outbound::repository::data_model::booking_data_model::BookingDataModel;
use crate::adapter::outbound::repository::mapper::booking_mapper;
use crate::domain::booking::Booking;
use crate::usecase::booking::port::booking_repository::BookingRepository;
use crate::usecase::error::AppError;

pub struct BookingRepositoryImpl {
    connection: Arc<Mutex<Connection>>,
}

impl BookingRepositoryImpl {
    pub fn new(connection: Arc<Mutex<Connection>>) -> Self {
        Self { connection }
    }
}

impl BookingRepository for BookingRepositoryImpl {
    fn get_by_id(&self, id: i64) -> Result<Option<Booking>, AppError> {
        let conn = self.connection.lock().expect("db connection mutex poisoned");
        let mut stmt = conn.prepare("SELECT id, account_id, status FROM bookings WHERE id = ?1")?;
        let mut rows = stmt.query(params![id])?;

        match rows.next()? {
            Some(row) => Ok(Some(booking_mapper::to_domain(BookingDataModel::from_row(row)?)?)),
            None => Ok(None),
        }
    }

    fn save(&self, booking: Booking) -> Result<Booking, AppError> {
        let conn = self.connection.lock().expect("db connection mutex poisoned");
        let data_model = booking_mapper::to_data_model(&booking);

        conn.execute(
            "INSERT INTO bookings (id, account_id, status) VALUES (?1, ?2, ?3)
             ON CONFLICT(id) DO UPDATE SET account_id = excluded.account_id, status = excluded.status",
            params![data_model.id, data_model.account_id, data_model.status],
        )?;

        Ok(booking)
    }
}
```

`AppError` 的 `#[from] rusqlite::Error` variant(見 `references/usecase_layer.md` 的 `error.rs` 模板)讓 `?` 可以直接把 `rusqlite::Error` 轉成 `AppError::Db`,不需要每個方法手動 `map_err`。

### 多步驟寫入的交易範例(以本專案的 nested-set 樹操作為例)

```rust
fn insert_node(&self, parent_id: Option<i64>, project_id: i64, title: String) -> Result<Task, AppError> {
    let mut conn = self.connection.lock().expect("db connection mutex poisoned");
    let tx = conn.transaction()?;

    let parent_rgt: i64 = tx.query_row(
        "SELECT rgt FROM task WHERE id = ?1 AND project_id = ?2",
        params![parent_id, project_id],
        |row| row.get(0),
    )?;

    tx.execute(
        "UPDATE task SET rgt = rgt + 2 WHERE rgt >= ?1 AND project_id = ?2",
        params![parent_rgt, project_id],
    )?;
    tx.execute(
        "UPDATE task SET lft = lft + 2 WHERE lft > ?1 AND project_id = ?2",
        params![parent_rgt, project_id],
    )?;
    tx.execute(
        "INSERT INTO task (project_id, lft, rgt, title, status) VALUES (?1, ?2, ?3, ?4, 'todo')",
        params![project_id, parent_rgt, parent_rgt + 1, title],
    )?;

    let new_id = tx.last_insert_rowid();
    tx.commit()?;

    // 交易已提交,重新用同一個 connection guard 查回剛建立的節點
    // (實務上可直接用上面 insert 的值組出 Task,這裡示意查詢路徑)
    drop(conn);
    self.get_by_id(new_id)?.ok_or(AppError::NotFound { entity: "Task", id: new_id })
}
```

任何一步 `?` 失敗都會讓 `tx` 提早離開作用域並自動 rollback,不需要手動 `ROLLBACK`。

### 外部依賴 Adapter `<category>/<provider>_<concept>_adapter.rs`

以 `client/` 為例(`messaging/`、`cache/`、`notification/`、`storage/` 套用同一個模板,只換子 module、Port trait 名稱):

```rust
use crate::domain::booking::Booking;
use crate::usecase::booking::port::payment_client::PaymentClient;
use crate::usecase::error::AppError;

pub struct StripePaymentAdapter {
    api_key: String,
}

impl StripePaymentAdapter {
    pub fn new(api_key: String) -> Self {
        Self { api_key }
    }
}

impl PaymentClient for StripePaymentAdapter {
    fn charge(&self, booking: &Booking) -> Result<String, AppError> {
        // 呼叫 Stripe SDK,SDK 錯誤在此轉為 AppError
        stripe_sdk::charge(&self.api_key, booking.account_id())
            .map_err(|e| AppError::InvalidState {
                entity: "Booking",
                reason: format!("payment failed: {e}"),
            })
    }
}
```

### 事件發送器 `event/tauri_event_publisher.rs`(專案級共用,只產生一次)

```rust
use tauri::{AppHandle, Emitter};

use crate::usecase::booking::port::domain_event_publisher::DomainEventPublisher;

pub struct TauriEventPublisher {
    app_handle: AppHandle,
}

impl TauriEventPublisher {
    pub fn new(app_handle: AppHandle) -> Self {
        Self { app_handle }
    }
}

impl DomainEventPublisher for TauriEventPublisher {
    fn publish(&self, event_name: &str, payload: serde_json::Value) {
        // emit 失敗(例如所有視窗都已關閉)不該讓寫入操作跟著失敗,記 log 即可
        if let Err(err) = self.app_handle.emit(event_name, payload) {
            eprintln!("failed to emit event {event_name}: {err}");
        }
    }
}
```

這個 struct 直接對應本專案 design.md 決定的雙視窗同步機制:每個 use case 呼叫 `event_publisher.publish("task-updated", &result)` 之後,主視窗與專注小視窗各自的前端用 `listen("task-updated", ...)` 接收並重新整理。
