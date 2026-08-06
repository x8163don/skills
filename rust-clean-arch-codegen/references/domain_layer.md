# Domain 層 — 領域實體與核心業務

## 規則

1. 只 `use` 標準函式庫(`std::*`)與同層其他 domain 型別;維持純 Rust,零外部 crate 依賴(不 derive `serde::Serialize`,Domain 物件不跨 usecase 邊界,見 `references/architecture.md` 規則 5)。
2. 業務邏輯寫在實體的方法內(充血模型);每條 Business Rule 對應一個方法。
3. 建構子固定命名 `pub fn new(...) -> Result<Self, DomainError>`,不是 `Self` 直接回傳——Rust 沒有例外,驗證失敗一律用 `Result` 表達,不 `panic!`。`DomainError` 是 `usecase::error` 定義的專案級共用 `AppError` 的子集或直接複用(見 `references/usecase_layer.md` 規則 7);Domain 層本身不定義新的錯誤型別。
4. 所有欄位 `private`(不加 `pub`);對外只提供 `pub fn <field>(&self) -> &<Type>` 這種 accessor(回傳參考,除非是 `Copy` 型別如 `i64`/`enum` 則直接回傳值),不提供 setter——狀態只能透過業務方法變更。Rust 沒有欄位層級的 `final`,不可變性是「沒有對應的 mutator 方法」這件事本身保證的,不是語法關鍵字。
5. 狀態 enum `<Entity>Status` 與實體定義在同一個 `domain::<entity>` module,獨立檔案 `status.rs`。
6. 行為隨型別變化時,定義策略 trait `<Concept>`,多個 struct 各自 `impl <Concept> for <Variant>`,以多型取代 if-else(對應 Java 的策略介面、Go 的策略 interface)。
7. 業務規則違反時,回傳 `DomainError` 對應的 variant:狀態轉移錯誤用 `InvalidState`、參數不合法用 `InvalidArgument`。方法簽名固定 `pub fn <business_method>(&mut self) -> Result<(), DomainError>`(有副作用、可能失敗)或 `pub fn can_<business_query>(&self) -> bool`(查詢型,不變更狀態、不失敗)。

## 產出檔案(依序)

1. `status.rs`(如有狀態欄位)
2. `<concept>.rs` + 各實作(如有策略 trait)
3. `mod.rs`(核心實體,`pub mod status;` 等宣告寫在檔案開頭)

## 模板

### 狀態列舉 `domain/<entity>/status.rs`

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BookingStatus {
    Pending,
    Confirmed,
    Cancelled,
}
```

### 核心實體 `domain/<entity>/mod.rs`

```rust
mod status;

pub use status::BookingStatus;

use crate::usecase::error::DomainError;

pub struct Booking {
    id: i64,
    account_id: i64,        // 不可變:只有 accessor,沒有對應的 mutator
    status: BookingStatus,  // 可變狀態:透過業務方法變更
}

impl Booking {
    pub fn new(id: i64, account_id: i64, status: BookingStatus) -> Result<Self, DomainError> {
        if account_id <= 0 {
            return Err(DomainError::InvalidArgument {
                field: "account_id",
                reason: "must be positive".into(),
            });
        }
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

    /// 查詢型業務方法:不變更狀態、不失敗
    pub fn can_cancel(&self) -> bool {
        self.status == BookingStatus::Pending
    }

    pub fn id(&self) -> i64 { self.id }
    pub fn account_id(&self) -> i64 { self.account_id }
    pub fn status(&self) -> BookingStatus { self.status }
}
```

`id`/`account_id` 是 `Copy` 型別(`i64`),accessor 直接回傳值;若欄位是 `String` 等非 `Copy` 型別,accessor 回傳 `&str`/`&Type`(借用),避免不必要的 clone。

### 策略 trait(行為隨型別變化時)

```rust
pub trait Plan {
    fn plan_type(&self) -> PlanType;
    fn monthly_fee(&self) -> u32;
}

pub struct FreePlan;
impl Plan for FreePlan {
    fn plan_type(&self) -> PlanType { PlanType::Free }
    fn monthly_fee(&self) -> u32 { 0 }
}

pub struct StandardPlan;
impl Plan for StandardPlan {
    fn plan_type(&self) -> PlanType { PlanType::Standard }
    fn monthly_fee(&self) -> u32 { 999 }
}
```

各實作的差異行為封裝在各自的方法內;呼叫端持有 `Box<dyn Plan>` 或 `&dyn Plan`,不用 if-else 判斷型別。
