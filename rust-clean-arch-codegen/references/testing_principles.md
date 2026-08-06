# Testing Principles（語言無關的測試原則）

## 核心規則：只有兩個測試層級

Clean Architecture 分了很多層（domain / usecase / adapter-outbound / adapter-inbound），但這不代表每一層都要各自寫一份獨立測試。層數一多，常見的後果是：

- usecase 層的 mock port test，測的其實只是「有沒有正確呼叫 mock」，不是系統的真實行為——一旦 mock 跟真實 adapter 的行為兜不起來（該回傳的 error 沒回傳、真實 DB 的 constraint 沒模擬到），這些測試全綠也救不了你。
- adapter-outbound 層的 mapper/repository test，如果測的是「跟真實 DB 一樣的行為」，那它跟 command-level 整合測試在驗證同一件事，只是晚一層才發現問題，還多一份要維護的程式碼。

所以這份原則只要求兩個測試層級，其餘不寫：

### Layer 1 — Domain Aggregate Test

- 對象：entity / aggregate root 的業務規則（狀態轉換、invariant、value object 驗證）。
- 完全不碰任何基礎設施、不 mock 任何東西——建構子把資料丟進去，呼叫方法，斷言最終狀態或回傳的 `DomainError`。
- 目的是把「業務規則本身對不對」跟「這個規則有沒有被正確接到 command/DB」這兩件事分開驗證，讓業務邏輯測試可以跑得極快、極穩定。

### Layer 2 — Command-level Integration Test

- 對象：從 `#[tauri::command]` 進入點一路走到真實資料庫，以及這個專案實際依賴的其他有狀態外部元件（例如 Redis）。
- 一般語言的做法是用 testcontainer 起跟正式環境同一種 DB image；**但這個 skill 的正式環境資料庫本來就是內嵌的 SQLite（`rusqlite`），不是需要另外起 server 的 Postgres/MySQL 這類技術**，所以這裡不需要、也不應該用 testcontainer 起一個正式環境根本不存在的 DB——測試直接用真實的 `rusqlite::Connection`（暫存檔案或 `:memory:`）就已經是跟正式環境完全相同的引擎，不是替代品。「用跟正式環境一致的技術測試、不用會導致行為落差的替代品」才是這條原則的核心精神，testcontainer 只是這個精神在有獨立 DB server 的技術棧下的具體實作方式；在 SQLite 這種內嵌引擎上，`:memory:`/暫存檔案就已經完整滿足這個精神,不必再疊加一層 container。
- 如果專案有其他有狀態的外部依賴（例如 Redis 快取、訊息佇列），那才是需要 [testcontainers-rs](https://docs.rs/testcontainers) 起真實 container 的地方。
- 只 mock 這層「管不到」的東西：第三方 SaaS API（例如金流)——這些依賴不屬於專案能控制的基礎設施，也沒有 testcontainer 可以起。
- 斷言不能只看回傳的 `Result`——涉及寫入的操作要再查一次（呼叫對應的查詢 command,或直接查 `Connection`），確認狀態真的落地到資料庫。

## 為什麼不需要 usecase 層 mock test 和 adapter-outbound 層獨立 test

- usecase 層本身只做 orchestration，不該藏業務規則，所以它的邏輯已經被 domain aggregate test 涵蓋；它有沒有正確呼叫 port，則由 command-level test 涵蓋。
- adapter-outbound 層的 mapper/repository 已經在 command-level test 裡用真實 rusqlite 連線跑過一次；再用 `mockall` 假物件寫一份獨立 test，是重複勞動，也容易在假物件測試綠燈但真實 SQL/型別轉換行為不一致時被蓋牌。

## Rust/Tauri 這個 skill 的測試對應

### 用真實 rusqlite 連線,不 mock Repository

Command-level test 在同一個 `commands.rs` 檔案底部的 `#[cfg(test)] mod tests`(維持 Rust 慣例,不另開檔案)裡:

1. 用 `rusqlite::Connection::open_in_memory()` 開一條全新的記憶體 SQLite 連線。
2. 執行跟正式環境相同的建表 SQL(`CREATE TABLE bookings (...)`),讓 schema 跟 migration 保持一致——如果專案已經有 migration 腳本,直接在測試裡重放同一份 SQL,不要手key 一份不同步的建表語句。
3. 用這條連線組裝真實的 `BookingRepositoryImpl::new(Arc::new(Mutex::new(connection)))`,再組裝真實的 `CreateBookingUseCaseImpl::new(repository.clone())`。
4. 第三方 SaaS Client(如 `PaymentClient`)才用 `mockall` 產生假物件頂替;`BookingRepository`、`DomainEventPublisher` 這類專案自己能控制的依賴一律用真實實作(`TauriEventPublisher` 需要 `AppHandle`,測試環境沒有真的視窗時可以額外提供一個不做事的測試替身,只有這個是例外——因為它是「發通知」的 side effect,不是這個 use case 要驗證的核心行為)。

### `State` 解包技巧(繞開 `tauri::State` 在單元測試裡不易建構的限制)

`tauri::State<T>` 只能由 Tauri runtime 建構,測試裡沒有 runtime、無法直接 new 一個 `State`。解法是讓 `#[tauri::command]` 函式維持極薄的一層,把實際邏輯拆進一個吃 `Arc<dyn Xxx>` 的 private 函式,測試直接呼叫 private 函式,略過 `State`:

```rust
use std::sync::Arc;

use tauri::State;

use crate::adapter::inbound::tauri::booking::response::BookingResponse;
use crate::usecase::booking::command::create_booking_command::CreateBookingCommand;
use crate::usecase::booking::port::create_booking_use_case::CreateBookingUseCase;
use crate::usecase::error::AppErrorPayload;

#[tauri::command]
pub fn create_booking(
    command: CreateBookingCommand,
    use_case: State<Arc<dyn CreateBookingUseCase>>,
) -> Result<BookingResponse, AppErrorPayload> {
    create_booking_inner(command, use_case.inner().clone())
}

fn create_booking_inner(
    command: CreateBookingCommand,
    use_case: Arc<dyn CreateBookingUseCase>,
) -> Result<BookingResponse, AppErrorPayload> {
    use_case
        .create(command)
        .map(BookingResponse::from)
        .map_err(|e| AppErrorPayload::from(&e))
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
        let use_case: Arc<dyn CreateBookingUseCase> = Arc::new(CreateBookingUseCaseImpl::new(repository.clone()));

        let response = create_booking_inner(
            CreateBookingCommand { account_id: 42 },
            use_case,
        )
        .unwrap();

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

這樣寫的好處是 `#[tauri::command]` 公開函式本身完全不需要在測試裡建構,`create_booking_inner` 才是真正被測試涵蓋的邏輯,兩者行為完全一致(公開函式只是多解一層 `State`)。

### 有 Redis/Kafka 等外部服務依賴時

`adapter/outbound/cache/`、`messaging/` 這些分類如果接的是真的網路服務(不是內嵌引擎),command-level test 就該用 [testcontainers-rs](https://docs.rs/testcontainers) 啟動對應的真實 image(例如 Redis 官方 image),注入真實的 `<Provider><Concept>Adapter`,原理跟其他語言 skill 的 testcontainer 做法一致——只有 SQLite 這個內嵌持久化引擎是例外。
