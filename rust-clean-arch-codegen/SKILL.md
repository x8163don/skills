---
name: rust-clean-arch-codegen
description: Use when the user wants to implement a new feature or entity in a Rust Tauri project using Clean Architecture / Hexagonal Architecture layers (Domain/Entities, Usecase, Adapter — split into Outbound and Inbound sides of Interface Adapters). Triggers on an entity spec with fields/business rules, "generate Rust layers for X", "implement X with clean architecture in Rust", "scaffold X entity in Rust", "write TDD implementation for X in Rust", a Tauri command that needs backend logic, or requirement + test descriptions in a Rust/Tauri project. Invoke even for partial specs — ask only for missing critical info (entity name or fields).
---

# Rust Clean Architecture Code Generator

## 目的

根據實體規格(Entity Spec)產生完整、可編譯的 Rust 分層程式碼(Domain → Usecase → Adapter/Outbound → Adapter/Inbound),對應 Clean Architecture 的 Entities → Use Cases → Interface Adapters 三圈(Adapter 依方向拆為 Outbound/Inbound 兩側,合稱 Interface Adapters;Frameworks & Drivers 第四圈不獨立成 module,詳見 `references/architecture.md`)。技術選型固定為 **Tauri v2**(inbound command)+ **rusqlite**(outbound persistence)+ **thiserror**(錯誤)+ **mockall**(僅第三方 SaaS Client 需要時的測試替身,見 `references/testing_principles.md`)。所有型別名稱、module 路徑、檔案位置皆由固定模板推導,確保多次產出結果高度一致,且是這個技術棧下慣用的 Rust 寫法(trait + 建構子注入、`Result<T, E>` 回傳值、`Arc`/`Mutex` 管理共享狀態、inline `#[cfg(test)]` 測試),不是 Java/Go 語法的機械翻譯。

這是 `java-clean-arch-codegen` / `go-clean-arch-codegen` 的 Rust 版本,分層概念與命名推導邏輯一致,差異只在語言慣用法(見 `references/architecture.md` 的完整對照)。

## 觸發時機

**使用**:在 Rust(尤其 Tauri)專案中實作新實體或新功能、依規格 scaffold Clean Architecture 分層、TDD 實作(規格附測試描述)。

**不使用**:非 Rust 專案、只修改既有單一檔案而不涉及分層、純 SQL/設定檔調整。

## 規則

所有產出必須同時滿足以下規則(各層細節規則見對應 reference):

1. **依賴方向由外向內**:Adapter(Interface Adapters,含 Outbound/Inbound 兩側)→ Usecase → Domain。每一層只 `use` 自己這層與更內層的型別。
2. **Domain 是純 Rust**:零外部 crate 依賴;業務邏輯寫在實體方法內(充血模型);建構子 `pub fn new(...) -> Result<Self, DomainError>`(沒有例外,驗證失敗回傳 `Result`);行為隨型別變化時用策略 trait + 多個實作。
3. **Usecase 用 `Result<T, AppError>` 取代例外**:錯誤是**專案級共用**的 `AppError` enum(`thiserror` derive),只在整個專案第一次使用本 skill 時產生,之後每個 entity 直接重用——不是每個 entity 各自定義例外型別(這點刻意跟 Java 常見的 per-entity Exception 不同,更貼近 Rust 生態慣例,細節見 `references/architecture.md` 規則 8);查詢單筆找不到時 Repository 回傳 `Ok(None)`,UseCaseImpl 轉成 `AppError::NotFound`;先 `save()` 成功、後 `publish()` 事件;依賴一律以 `Arc<dyn Trait + Send + Sync>` 建構子注入;Inbound Port 方法一律回傳 Usecase 自己定義的 `<Entity>Result` 家族型別,方法內部操作完 Domain 才轉換,Domain 物件不可流出 Usecase 邊界。**每個 use case 情境(每條 Business Rule 或查詢需求)各自一個 Inbound Port trait + 一個 Impl struct,不共用一個大 trait/大 struct**;需要輸入資料的 use case,其輸入型別 `<Action>Command` 也定義在本層(跟 `<Entity>Result` 對稱,兩者都是 Usecase 自己擁有的邊界資料結構,也是本層唯二需要 derive `serde::Serialize`/`Deserialize` 的型別,因為要跨 Tauri IPC);`usecase/<entity>/` 目錄下只放這些 use case impl 檔案,trait 收進 `port/`、Result 收進 `result/`、Command 收進 `command/`、事件收進 `event/`。
4. **Adapter/Outbound 隔離技術細節**:rusqlite 沒有 ORM 巨集,`<Entity>DataModel` 是手寫 `from_row()` 對映的純 struct(不叫 `<Entity>Entity`,避免與 Domain 的 `<Entity>` 混淆);`<entity>_mapper` 全部是 module-level 純函式;`<Entity>RepositoryImpl` 包 `Arc<Mutex<rusqlite::Connection>>` 實作 Usecase 的 Outbound Port,多步驟寫入用 `connection.transaction()` 保護;非 DB 的外部依賴(API/SDK、訊息佇列、快取、通知、檔案儲存)一律命名 `<Provider><Concept>Adapter`,分類到 `client/`、`messaging/`、`cache/`、`notification/`、`storage/` 子 module;事件發送固定用**專案級共用**的 `TauriEventPublisher`(以 `AppHandle::emit` 實作),只產生一次。
5. **Adapter/Inbound 只做轉換**:`#[tauri::command]` 函式僅接收參數 → 呼叫 UseCase → 包裝 Response;寫入型輸入物件 `<Action>Command` 是從 usecase 層 import 使用(不在本層重複定義一份);**沒有**跟 Spring/Gin 對等的全域例外處理中介層(Tauri command 沒有中介層鏈)——每個 command 直接回傳 `Result<T, AppErrorPayload>`,等價的統一轉換效果由 `AppErrorPayload` 的 `kind` 欄位在前端分流達成,不要硬套一個 Tauri 沒有的中介層結構;`<Entity>Response` 包裝 Usecase 回傳的 `<Entity>Result` 後回傳(不是 Domain,不叫 Dto);本層一律不 `use` `domain` module。
6. **命名一律依推導表**:所有型別名稱與檔案路徑依 `references/architecture.md` 的命名推導表從 Entity 名稱產生,不自創命名。
7. **每個檔案完整可編譯**:含完整 `use` 宣告(逐一明確列出,不用萬用字元)、完整方法實作,零 TODO、零 `unimplemented!()`。
8. **產生順序固定**:(專案級共用檔案,如未生成 →)(Domain 測試 →)Domain → Usecase → Adapter/Outbound → Adapter/Inbound(→ Command-level 整合測試)。有測試描述時,Domain 測試先於 Domain 實作產生;Command-level 整合測試則相反,必須等四層都產生完成才能寫(它要串起 Repository、UseCaseImpl、command 函式全部真實運作),固定放在最後一步。只有這兩層測試,理由見 `references/testing_principles.md`。

## 固定輸出格式

整體輸出依序包含三個部分:(1) crate root 路徑註記一行、(2) 產出檔案清單(相對路徑,依產生順序,含各層 `mod.rs` 更新)、(3) 各檔案內容。檢查清單為內部步驟,不出現在輸出中。

每個檔案一律使用以下標頭,讓用戶可直接放置:

```
// === <Layer> Layer ===
// File: src-tauri/src/<layer 路徑>/<file>.rs

<完整 Rust 原始碼>
```

未提供 crate root 時,一律假設是 `src-tauri/src`(標準 Tauri 專案結構)並在輸出開頭註明。若某個檔案是對既有 `mod.rs` 的**修改**(新增一行 `pub mod xxx;`)而非新檔案,標頭改為 `// === <Layer> Layer (edit) ===` 並只顯示要新增的那一行,不重印整個檔案。

## 工作流程

1. **解析與確認**:從輸入提取 Entity 名稱(PascalCase)、Fields(Rust 型別)、Business Rules(→ 方法簽名)、Outbound Dependencies、Tauri Commands、Tests。輸入為段落描述時,自行整理成規格並請用戶確認;僅在 Entity 名稱或 Fields 完全缺失時才暫停詢問。輸入格式見 `references/architecture.md`。
2. **確認專案級共用檔案**:詢問或依上下文判斷這是否是專案第一次使用本 skill;若是,先產生 `usecase/error.rs`(`AppError` + `AppErrorPayload`)、`adapter/outbound/event/tauri_event_publisher.rs`(如這個 entity 有事件)。若專案已有這些檔案,跳過此步驟,直接重用。
3. **(TDD)先產 Domain 測試**:規格含測試描述時,在 Domain 檔案底部加 `#[cfg(test)] mod tests`(每條業務規則一個正常案例 + 至少一個邊界案例)。Usecase 層本身不產生獨立測試,理由見 `references/testing_principles.md`。
4. **依序產生四層**:每層產生前先讀取對應 reference 的模板:

   | 層 | Reference | 產出檔案 |
   |---|---|---|
   | 共用 | `references/architecture.md` | module 結構、命名推導表、輸入格式 |
   | 測試原則 | `references/testing_principles.md` | 兩層測試策略(Domain test + Command-level 整合測試)與理由 |
   | Domain | `references/domain_layer.md` | Entity、Status enum、策略 trait(如適用) |
   | Usecase | `references/usecase_layer.md` | `AppError`(如未產生)、Outbound Ports、Result、Command、每個 use case 情境的 Inbound Port + Impl、事件 |
   | Adapter/Outbound | `references/adapter_outbound_layer.md` | DataModel、Mapper、RepositoryImpl、(Client/Messaging/Cache/Notification/Storage Adapter)、`TauriEventPublisher`(如未產生) |
   | Adapter/Inbound | `references/adapter_inbound_layer.md` | Response、Command 函式(Command struct 已在 Usecase 產出,此處直接 import)、Command-level 整合測試(四層都完成後才產生) |

5. **逐層檢查**:每層完成後對照該 reference 的「規則」小節與本文件「產出前檢查」。
6. **產生 Command-level 整合測試**:四層都產生完成後,在 `commands.rs` 底部補上 `#[cfg(test)] mod tests`,用真實 in-memory rusqlite 連線串起 Repository → UseCaseImpl → command 函式,只 mock 第三方 SaaS Client;模板與 `State` 解包技巧見 `references/adapter_inbound_layer.md` 文件末尾。
7. **提醒手動接線**:輸出結尾一定要提醒使用者,新的 command 需要加進 `lib.rs`/`main.rs` 的 `tauri::generate_handler![...]` 清單,對應的 UseCaseImpl 依賴需要在 app 啟動時組裝並 `app.manage(...)`——這兩處因為涉及既有專案的組裝邏輯,本 skill 不自動改寫 `lib.rs`,只提供對照範例(見 `references/adapter_inbound_layer.md` 的「註冊 command」段落)。

## 簡單範例

輸入:

```
Entity: Booking
Fields:
  - id (i64)
  - accountId (i64)
  - status (enum: Pending / Confirmed / Cancelled)
Business Rules:
  - confirm(): 只有 Pending 可確認,否則回傳 AppError::InvalidState
Outbound Dependencies:
  - BookingRepository: 預約持久化
Tauri Commands:
  - confirm_booking: 確認預約
```

產出檔案清單(命名全部由推導表產生;假設專案已有 `usecase/error.rs`):

```
domain/booking/status.rs
domain/booking/mod.rs
usecase/booking/port/booking_repository.rs          ← Outbound Port
usecase/booking/result/booking_result.rs             ← Usecase 輸出型別(不回傳 Domain)
usecase/booking/port/confirm_booking_use_case.rs     ← Inbound Port(對應 confirm() 這個 use case)
usecase/booking/confirm_booking.rs                    ← 直接放在 usecase/booking/ 目錄下
usecase/booking/mod.rs                                (edit — 新增子模組宣告)
adapter/outbound/repository/data_model/booking_data_model.rs
adapter/outbound/repository/mapper/booking_mapper.rs
adapter/outbound/repository/booking_repository_impl.rs
adapter/inbound/tauri/booking/response.rs
adapter/inbound/tauri/booking/commands.rs
```

其中 Domain 實體產出樣貌(對應規則 2 與固定輸出格式):

```rust
// === Domain Layer ===
// File: src-tauri/src/domain/booking/mod.rs

mod status;

pub use status::BookingStatus;

use crate::usecase::error::DomainError;

pub struct Booking {
    id: i64,
    account_id: i64,
    status: BookingStatus,
}

impl Booking {
    pub fn new(id: i64, account_id: i64, status: BookingStatus) -> Result<Self, DomainError> {
        Ok(Self { id, account_id, status })
    }

    /// 業務行為:確認預約
    pub fn confirm(&mut self) -> Result<(), DomainError> {
        if self.status != BookingStatus::Pending {
            return Err(DomainError::InvalidState {
                entity: "Booking",
                reason: format!("only Pending booking can be confirmed, current status is {:?}", self.status),
            });
        }
        self.status = BookingStatus::Confirmed;
        Ok(())
    }

    pub fn id(&self) -> i64 { self.id }
    pub fn account_id(&self) -> i64 { self.account_id }
    pub fn status(&self) -> BookingStatus { self.status }
}
```

## 產出前檢查

- [ ] Domain 檔案零外部 crate 依賴,建構子與業務方法都回傳 `Result<_, DomainError>`,沒有 `panic!`
- [ ] 錯誤一律用專案級共用的 `AppError`,沒有為這個 entity 新開一個例外/錯誤型別
- [ ] 事件在 `save()` 之後 publish
- [ ] rusqlite 對映邏輯只在 `<Entity>DataModel::from_row` 與 `<entity>_mapper`;Mapper 全是 module-level 純函式
- [ ] 每個 use case 情境各自一個 Inbound Port trait(只宣告一個方法)+ 一個 Impl struct,沒有共用的大 trait/大 struct;方法皆回傳 `<Entity>Result` 家族型別,不直接回傳 Domain `<Entity>`
- [ ] `usecase/<entity>/` 目錄下只有 use case impl 檔案(每個 use case 一個);trait 在 `port/`、Result 在 `result/`、Command 在 `command/`、事件在 `event/`
- [ ] `<Action>Command` 定義在 usecase 層,不在 Adapter/Inbound 重複定義一份;`<Entity>Result`/`<Action>Command` 是本層唯二 derive `Serialize`/`Deserialize` 的型別
- [ ] Repository/Adapter 依賴 `Arc<Mutex<rusqlite::Connection>>`,多步驟寫入包在 `connection.transaction()` 內
- [ ] `#[tauri::command]` 函式無 if/else 業務邏輯;沒有生出一個假的全域例外處理中介層;回傳皆為 `Result<Response, AppErrorPayload>`;輸入物件皆為 `<Action>Command`(無 Request/Dto 命名);不 `use` `domain` module
- [ ] `usecase/error.rs`、`adapter/outbound/event/tauri_event_publisher.rs` 若專案已存在則未重複產生
- [ ] 所有型別名稱符合命名推導表
- [ ] 每個檔案有輸出標頭、完整 `use` 宣告(無未使用 import)、零 TODO
- [ ] 輸出結尾提醒使用者手動把新 command 加進 `generate_handler![...]` 並在 `setup`/組裝處 `app.manage(...)` 對應的 UseCaseImpl
- [ ] 只有兩層測試:Domain aggregate test(無 mock)+ Command-level 整合測試(真實 in-memory rusqlite,只 mock 第三方 SaaS Client);沒有為 usecase 層另外產生 `mockall` mock test
- [ ] Command-level 整合測試的寫入案例有再查一次資料庫確認狀態落地,不是只看回傳的 `Result`
