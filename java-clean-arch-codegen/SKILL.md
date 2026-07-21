---
name: java-clean-arch-codegen
description: Use when the user wants to implement a new feature or entity in a Java Spring Boot project using Clean Architecture / Hexagonal Architecture layers (Domain/Entities, Usecase, Adapter — split into Outbound and Inbound sides of Interface Adapters). Triggers on an entity spec with fields/business rules, "generate Java layers for X", "implement X with clean architecture", "scaffold X entity", "write TDD implementation for X in Java", or requirement + test descriptions in a Java project. Invoke even for partial specs — ask only for missing critical info (entity name or fields).
---

# Java Clean Architecture Code Generator

## 目的

根據實體規格(Entity Spec)產生完整、可編譯的 Java Spring Boot 分層程式碼(Domain → Usecase → Adapter/Outbound → Adapter/Inbound),對應 Clean Architecture 的 Entities → Use Cases → Interface Adapters 三圈(Adapter 依方向拆為 Outbound/Inbound 兩側,合稱 Interface Adapters;Frameworks & Drivers 第四圈不獨立成 package,詳見 `references/architecture.md`)。所有類別名稱、package 路徑、註解位置皆由固定模板推導,確保多次產出結果高度一致。

## 觸發時機

**使用**:在 Java 專案中實作新實體或新功能、依規格 scaffold Clean Architecture 分層、TDD 實作(規格附測試描述)。

**不使用**:非 Java 專案、只修改既有單一類別而不涉及分層、純 SQL/設定檔調整。

## 規則

所有產出必須同時滿足以下規則(各層細節規則見對應 reference):

1. **依賴方向由外向內**:Adapter(Interface Adapters,含 Outbound/Inbound 兩側)→ Usecase → Domain。每一層只 import 自己這層與更內層的類別。
2. **Domain 是純 Java**:只 import `java.*`;業務邏輯寫在實體方法內(充血模型);建構子以 `Objects.requireNonNull()` 保護參考型別;行為隨型別變化時用策略介面 + 多個實作。
3. **Usecase 掌控交易與事件**:每個寫入方法(呼叫 `save()` 或變更狀態)標 `@Transactional`;先 `save()` 成功、後 `publish()` 事件;依賴一律建構子注入;領域例外(如 `<Entity>NotFoundException`)定義在 usecase package 並繼承 `RuntimeException`。
4. **Adapter/Outbound 隔離技術細節**:JPA 註解只出現在 `<Entity>DataModel.java`(不叫 `<Entity>Entity`,避免與 Domain 的 `<Entity>` 混淆);`<Entity>Mapper` 全部為 static 方法;`<Entity>RepositoryImpl` 實作 Usecase 的 Outbound Port;非 DB 的外部依賴(API/SDK、訊息佇列、快取、通知、檔案儲存)一律命名 `<Provider><Concept>Adapter`(不用 `*ServiceImpl`),分類到 `client/`、`messaging/`、`cache/`、`notification/`、`storage/` 子目錄,SDK 例外在此層捕捉並轉為自訂例外(如 `PaymentClientException`)後上拋。
5. **Adapter/Inbound 只做轉換**:Controller 僅路由 → 呼叫 UseCase → 包裝 Response;寫入型輸入物件叫 `<Action>Command`(不叫 Request/Dto)用 `jakarta.validation` + `@Valid`;`GlobalExceptionHandler`(`@RestControllerAdvice`)統一轉換:NotFound → 404、`IllegalArgumentException` 與驗證失敗 → 400、其他 → 500;`<Entity>Response` 包裝 Domain 物件後回傳(不叫 Dto)。
6. **命名一律依推導表**:所有類別名稱與 package 路徑依 `references/architecture.md` 的命名推導表從 Entity 名稱產生,不自創命名。
7. **每個檔案完整可編譯**:含 package 宣告、全部 import(逐一明確列出,不使用萬用字元 `*`)、完整方法實作,零 TODO、零 `UnsupportedOperationException`。
8. **產生順序固定**:(測試 →)Domain → Usecase → Adapter/Outbound → Adapter/Inbound;有測試描述時,測試先於實作產生。

## 固定輸出格式

整體輸出依序包含三個部分:(1) base package 註記一行、(2) 產出檔案清單(相對路徑,依產生順序)、(3) 各檔案內容。檢查清單為內部步驟,不出現在輸出中。

每個檔案一律使用以下標頭,讓用戶可直接放置:

```
// === <Layer> Layer ===
// File: src/main/java/<basePackage 路徑/layer/package/ClassName.java>

<完整 Java 原始碼>
```

未提供 base package 時,一律使用 `com.example.<project>` 並在輸出開頭註明。

## 工作流程

1. **解析與確認**:從輸入提取 Entity 名稱(PascalCase)、Fields(Java 型別)、Business Rules(→ 方法簽名)、Outbound Dependencies、API Endpoints、Tests。輸入為段落描述時,自行整理成規格並請用戶確認;僅在 Entity 名稱或 Fields 完全缺失時才暫停詢問。輸入格式見 `references/architecture.md`。
2. **(TDD)先產測試**:規格含測試描述時,產生 `<Entity>Test.java`(JUnit 5、無 mock、每條業務規則一個正常案例 + 至少一個邊界案例)與 `<Entity>UseCaseImplTest.java`(JUnit 5 + Mockito,`@Mock` 所有 Outbound Port、`@InjectMocks` Impl、每個用例方法一個測試)。
3. **依序產生四層**:每層產生前先讀取對應 reference 的模板:

   | 層 | Reference | 產出檔案 |
   |---|---|---|
   | 共用 | `references/architecture.md` | package 結構、命名推導表、輸入格式 |
   | Domain | `references/domain_layer.md` | Entity、Status enum、策略介面(如適用) |
   | Usecase | `references/usecase_layer.md` | Outbound Ports、Inbound Port、Impl、例外、事件 |
   | Adapter/Outbound | `references/adapter_outbound_layer.md` | JPA Entity、Mapper、JpaRepository、RepositoryImpl、(Client/Messaging/Cache/Notification/Storage Adapter) |
   | Adapter/Inbound | `references/adapter_inbound_layer.md` | Command、Response、Controller、GlobalExceptionHandler |

4. **逐層檢查**:每層完成後對照該 reference 的「規則」小節與本文件「產出前檢查」。

## 簡單範例

輸入:

```
Entity: Booking
Fields:
  - id (Long)
  - accountId (Long)
  - status (enum: PENDING / CONFIRMED / CANCELLED)
Business Rules:
  - confirm(): 只有 PENDING 可確認,否則拋 IllegalStateException
Outbound Dependencies:
  - BookingRepository: 預約持久化
API Endpoints:
  - PUT /api/bookings/{id}/confirm: 確認預約
```

產出檔案清單(命名全部由推導表產生):

```
domain/booking/BookingStatus.java
domain/booking/Booking.java
usecase/booking/BookingRepository.java        ← Outbound Port
usecase/booking/BookingUseCase.java           ← Inbound Port
usecase/booking/BookingUseCaseImpl.java
usecase/booking/BookingNotFoundException.java
adapter/outbound/repository/datamodel/BookingDataModel.java
adapter/outbound/repository/mapper/BookingMapper.java
adapter/outbound/repository/BookingJpaRepository.java
adapter/outbound/repository/BookingRepositoryImpl.java
adapter/inbound/web/booking/BookingResponse.java
adapter/inbound/web/booking/BookingController.java
adapter/inbound/web/exception/GlobalExceptionHandler.java
```

其中 Domain 實體產出樣貌(對應規則 2 與固定輸出格式):

```java
// === Domain Layer ===
// File: src/main/java/com/example/booking/domain/booking/Booking.java

package com.example.booking.domain.booking;

import java.util.Objects;

public class Booking {
    private final Long id;
    private final Long accountId;
    private BookingStatus status;

    public Booking(Long id, Long accountId, BookingStatus status) {
        this.id = id;
        this.accountId = Objects.requireNonNull(accountId, "accountId cannot be null");
        this.status = Objects.requireNonNull(status, "status cannot be null");
    }

    // 業務行為:確認預約
    public void confirm() {
        if (this.status != BookingStatus.PENDING) {
            throw new IllegalStateException("Only PENDING booking can be confirmed");
        }
        this.status = BookingStatus.CONFIRMED;
    }

    public Long getId() { return id; }
    public Long getAccountId() { return accountId; }
    public BookingStatus getStatus() { return status; }
}
```

## 產出前檢查

- [ ] Domain 檔案只 import `java.*`
- [ ] UseCaseImpl 的寫入方法都有 `@Transactional`,且不 import adapter(inbound/outbound)類別
- [ ] 事件在 `save()` 之後 publish
- [ ] JPA 註解只在 `<Entity>DataModel.java`;Mapper 全 static
- [ ] Controller 無 if/else 業務邏輯;回傳皆為 `<Entity>Response`;輸入物件皆為 `<Action>Command`(無 Request/Dto 命名)
- [ ] 所有類別名稱符合命名推導表
- [ ] 每個檔案有輸出標頭、完整 import、零 TODO
