# Adapter/Inbound 層 — 通訊與應用進入點(Interface Adapters,被外部驅動的一側)

這一層產生完之後,還要產生本層的 command-level 整合測試(見文件末尾),這是本 skill 唯二的兩個測試層級之一,細節與原則見 `references/testing_principles.md`。

## 規則

1. `#[tauri::command]` 巨集只出現在本層。每個函式固定三步:接收參數(Tauri 自動用 serde 反序列化前端傳來的 JSON)→ 呼叫 UseCase(Inbound Port)→ 包裝 Response 回傳;函式內零業務判斷。
2. 函式依賴 UseCase trait(不是 Impl),透過 `tauri::State` 取得——每個 use case 情境是獨立的窄 trait(`<Action><Entity>UseCase`),有幾個 command 就注入幾個對應的 trait object,不共用一個大 trait。
3. `<Action>Command` 定義在 **usecase 層**(`usecase::<entity>::command`,見 `references/usecase_layer.md`),不在本層;command 函式直接 `use` 它當參數型別,不自己另外定義一份。
4. Response 包裝 Usecase 回傳的 `<Entity>Result`(不是 Domain 物件);Domain 物件與其業務方法不可流出 Usecase 邊界,本層一律不 `use` `domain` module。**若 `<Entity>Result`/`TaskNode` 這類型別本身已經是刻意設計給外部消費的扁平 DTO,線路格式跟 Result 完全一致時,可以直接讓 command 函式回傳 `<Entity>Result`,不強制包一層欄位逐一複製的 `<Entity>Response`**——那種包裝除了名稱不同、沒有任何行為差異,是純儀式性樣板(YAGNI);只有當 Tauri 回傳給前端的線路格式需要跟 Result 的內部欄位不同(例如要隱藏某欄位、要合併多個 Result)時才值得包一層,這時才叫 `<Entity>Response` 並提供 `impl From<XxxResult> for XxxResponse`,不叫 `Dto`。
5. **沒有跟 Spring `@RestControllerAdvice`/Gin middleware 對等的「全域例外處理器」**——Tauri command 沒有中介層鏈,每個 command 直接回傳 `Result<T, AppErrorPayload>`(`AppErrorPayload` 定義在 `usecase::error`,見 `references/usecase_layer.md` 的 `error.rs` 模板);等價的「統一轉換」效果由 `AppErrorPayload` 的 `kind` 欄位在**前端**分流達成(見規則 6),不要在這層生出一個假的中介層結構硬套 Java/Go 的模式。
6. 命令函式回傳型別固定 `Result<<Entity>Response, AppErrorPayload>`;成功時 Tauri 自動序列化為 `{ ...fields }`,失敗時序列化為 `{ "kind": "...", "message": "..." }`,前端的 `invoke()` 呼叫在 `.catch()` 或 TanStack Query 的 `onError` 裡依 `kind` 分流(對應本專案 design.md「前端能依錯誤類型區分處理」的決定)。
7. 命令函式命名:`snake_case`,直接沿用 use case 的動詞語意(如 `confirm_booking`、`get_booking`),不用 REST 動詞前綴(沒有 HTTP path,不需要);所有同一個 entity 的 command 函式放在同一個 `commands.rs`。

## 產出檔案(依序)

1. `<entity>/response.rs`
2. `<entity>/commands.rs`(四層都完成後,在檔案底部補上 `#[cfg(test)] mod tests` 的 command-level 整合測試,見文件末尾)
3. `mod.rs`(宣告子模組)

`<Action>Command.rs` 在 usecase 層產生(見 `references/usecase_layer.md`),本層不重複產出。

## 模板

### Response `tauri/<entity>/response.rs`

```rust
use crate::usecase::booking::result::booking_result::BookingResult;

#[derive(Debug, Clone, serde::Serialize)]
pub struct BookingResponse {
    pub id: i64,
    pub account_id: i64,
    pub status: String,
}

impl From<BookingResult> for BookingResponse {
    fn from(result: BookingResult) -> Self {
        Self { id: result.id, account_id: result.account_id, status: result.status }
    }
}
```

### Command 函式 `tauri/<entity>/commands.rs`

每個函式對應一個獨立的 `<Action><Entity>UseCase` trait,透過 `tauri::State<Arc<dyn Xxx>>` 取得,不共用一個大 trait。Command 物件整個直接傳給 UseCase 方法,不在這層拆欄位:

```rust
use std::sync::Arc;

use tauri::State;

use crate::adapter::inbound::tauri::booking::response::BookingResponse;
use crate::usecase::booking::command::create_booking_command::CreateBookingCommand;
use crate::usecase::booking::port::confirm_booking_use_case::ConfirmBookingUseCase;
use crate::usecase::booking::port::create_booking_use_case::CreateBookingUseCase;
use crate::usecase::booking::port::get_booking_use_case::GetBookingUseCase;
use crate::usecase::error::AppErrorPayload;

#[tauri::command]
pub fn create_booking(
    command: CreateBookingCommand,
    use_case: State<Arc<dyn CreateBookingUseCase>>,
) -> Result<BookingResponse, AppErrorPayload> {
    use_case
        .create(command)
        .map(BookingResponse::from)
        .map_err(|e| AppErrorPayload::from(&e))
}

#[tauri::command]
pub fn confirm_booking(
    booking_id: i64,
    use_case: State<Arc<dyn ConfirmBookingUseCase>>,
) -> Result<BookingResponse, AppErrorPayload> {
    use_case
        .confirm(booking_id)
        .map(BookingResponse::from)
        .map_err(|e| AppErrorPayload::from(&e))
}

#[tauri::command]
pub fn get_booking(
    booking_id: i64,
    use_case: State<Arc<dyn GetBookingUseCase>>,
) -> Result<BookingResponse, AppErrorPayload> {
    use_case
        .get_by_id(booking_id)
        .map(BookingResponse::from)
        .map_err(|e| AppErrorPayload::from(&e))
}
```

### 註冊 command(不是本 skill 逐 entity 產生的檔案,而是既有 `lib.rs`/`main.rs` 的必要修改)

每個新 command 都必須加進 `tauri::generate_handler![...]` 清單,以及對應的 UseCaseImpl 都必須在 app 啟動時組裝好依賴並 `app.manage(...)` 注入,不然 `State<Arc<dyn Xxx>>` 會在執行期 panic。本 skill 產生新 entity 的 command 之後,**一定要在回覆最後提醒使用者**這兩處需要手動接上(組裝依賴的位置因專案而異,不強行產生一份可能覆蓋既有內容的 `lib.rs`):

```rust
// lib.rs 內大致形狀(僅供對照,不是本 skill 每次都要重新產出的檔案)
tauri::Builder::default()
    .manage(Arc::new(Mutex::new(connection)))
    .setup(|app| {
        let connection = /* 從 .manage() 取回或另外持有 */;
        let booking_repository: Arc<dyn BookingRepository> =
            Arc::new(BookingRepositoryImpl::new(connection.clone()));
        let event_publisher: Arc<dyn DomainEventPublisher> =
            Arc::new(TauriEventPublisher::new(app.handle().clone()));

        app.manage::<Arc<dyn CreateBookingUseCase>>(
            Arc::new(CreateBookingUseCaseImpl::new(booking_repository.clone())),
        );
        app.manage::<Arc<dyn ConfirmBookingUseCase>>(
            Arc::new(ConfirmBookingUseCaseImpl::new(booking_repository.clone(), event_publisher.clone())),
        );
        Ok(())
    })
    .invoke_handler(tauri::generate_handler![
        create_booking,
        confirm_booking,
        get_booking,
    ])
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
```

## Command-level 整合測試

本 skill 只要求兩個測試層級,這是第二層(第一層是 Domain aggregate test,見 `references/domain_layer.md`);完整原則與理由見 `references/testing_principles.md`。跟其他語言 skill 不同的是,這裡**不用 testcontainer**——因為這個 Tauri app 正式環境用的持久化技術本來就是內嵌的 rusqlite/SQLite,不是需要另外起 server 的資料庫,測試直接用真實的 `rusqlite::Connection`(`:memory:` 或暫存檔案)就已經是跟正式環境完全相同的引擎。

測試對象是 `#[tauri::command]` 進入點一路到真實資料庫的完整路線:組裝真實的 `RepositoryImpl`(接一條 in-memory `rusqlite::Connection`,先跑一次建表 SQL)、真實的 `UseCaseImpl`,只有第三方 SaaS Client 才用 `mockall` 頂替。斷言不能只看回傳的 `Result`——寫入操作要再查一次(呼叫對應的查詢邏輯,或直接查 `Connection`)確認資料真的落地。

`tauri::State<T>` 只能由 Tauri runtime 建構,測試裡沒辦法直接 new 一個。解法是讓 `#[tauri::command]` 公開函式維持極薄的一層,把邏輯拆進一個吃 `Arc<dyn Xxx>` 的 private 函式,測試直接呼叫 private 函式,略過 `State`——公開函式跟 private 函式行為完全一致,只是多解一層 `State`:

```rust
// commands.rs 檔案底部,緊接在 create_booking 之後

fn create_booking_inner(
    command: CreateBookingCommand,
    use_case: Arc<dyn CreateBookingUseCase>,
) -> Result<BookingResponse, AppErrorPayload> {
    use_case
        .create(command)
        .map(BookingResponse::from)
        .map_err(|e| AppErrorPayload::from(&e))
}

#[tauri::command]
pub fn create_booking(
    command: CreateBookingCommand,
    use_case: State<Arc<dyn CreateBookingUseCase>>,
) -> Result<BookingResponse, AppErrorPayload> {
    create_booking_inner(command, use_case.inner().clone())
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use rusqlite::Connection;

    use super::*;
    use crate::adapter::outbound::repository::booking_repository_impl::BookingRepositoryImpl;
    use crate::usecase::booking::create_booking::CreateBookingUseCaseImpl;

    fn setup_in_memory_db() -> Arc<Mutex<Connection>> {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute(
            "CREATE TABLE bookings (id INTEGER PRIMARY KEY, account_id INTEGER NOT NULL, status TEXT NOT NULL)",
            [],
        )
        .unwrap();
        Arc::new(Mutex::new(conn))
    }

    #[test]
    fn create_booking_persists_and_returns_pending_status() {
        let connection = setup_in_memory_db();
        let repository = Arc::new(BookingRepositoryImpl::new(connection.clone()));
        let use_case: Arc<dyn CreateBookingUseCase> =
            Arc::new(CreateBookingUseCaseImpl::new(repository.clone()));

        let response =
            create_booking_inner(CreateBookingCommand { account_id: 42 }, use_case).unwrap();

        assert_eq!(response.status, "Pending");

        // 不能只看回傳值——再用同一條連線查一次,確認資料真的落地
        let conn = connection.lock().unwrap();
        let persisted_status: String = conn
            .query_row(
                "SELECT status FROM bookings WHERE id = ?1",
                [response.id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(persisted_status, "Pending");
    }
}
```

若這個 use case 依賴 Redis/Kafka 這類真的網路服務(`adapter/outbound/cache/`、`messaging/` 分類),command-level test 改用 [testcontainers-rs](https://docs.rs/testcontainers) 啟動對應的真實 image 並注入真實 Adapter,原理跟其他語言 skill 一致——只有 SQLite 這個內嵌引擎是例外,不需要 container。
