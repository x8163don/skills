---
name: typescript-clean-arch-codegen
description: Use when the user wants to implement a new feature or entity in a TypeScript/Node.js project using Clean Architecture / Hexagonal Architecture layers (Domain/Entities, Usecase, Adapter — split into Outbound and Inbound sides of Interface Adapters), generating idiomatic TypeScript code on a NestJS + TypeORM + Zod + Vitest stack (NestJS controllers wired through DI injection tokens, TypeORM repositories, Zod-validated commands, Vitest domain unit tests and testcontainers-backed controller-level integration tests). Triggers on an entity spec with fields/business rules, "generate TypeScript layers for X", "implement X with clean architecture in Node/NestJS", "scaffold X entity in TypeScript", "write TDD implementation for X in TypeScript", or requirement + test descriptions in a Node/TypeScript project. Invoke even for partial specs — ask only for missing critical info (entity name or fields).
---

# TypeScript Clean Architecture Code Generator

## 目的

根據實體規格(Entity Spec)產生完整、可編譯的 TypeScript 分層程式碼(Domain → Usecase → Adapter/Outbound → Adapter/Inbound),對應 Clean Architecture 的 Entities → Use Cases → Interface Adapters 三圈(Adapter 依方向拆為 Outbound/Inbound 兩側,合稱 Interface Adapters;Frameworks & Drivers 第四圈不獨立成目錄,詳見 `references/architecture.md`)。技術選型固定為 **NestJS**(HTTP + DI 容器)+ **TypeORM**(持久化)+ **Zod**(輸入驗證)+ **Vitest**(測試)。所有型別名稱、目錄路徑、檔案位置皆由固定模板推導,確保多次產出結果高度一致,且是這個技術棧下慣用的 TypeScript 寫法(interface + DI token 注入、`async`/`await`、`throw` 表達錯誤、Zod schema 推導型別)。

## 觸發時機

**使用**:在 TypeScript/Node.js 專案中實作新實體或新功能、依規格 scaffold Clean Architecture 分層、TDD 實作(規格附測試描述)。

**不使用**:非 TypeScript/Node.js 專案、只修改既有單一檔案而不涉及分層、純 SQL/設定檔調整。

## 規則

所有產出必須同時滿足以下規則(各層細節規則見對應 reference):

1. **依賴方向由外向內**:Adapter(Interface Adapters,含 Outbound/Inbound 兩側)→ Usecase → Domain。每一層只 import 自己這層與更內層的模組。
2. **Domain 是純 TypeScript**:不 import 任何 npm 套件,只 import 同層檔案與共用的 `domain/errors.ts`;業務邏輯寫在實體方法內(充血模型);建構子驗證所有輸入,失敗時 `throw new InvalidArgumentError(...)`;行為隨型別變化時用策略介面 + 多個實作。
3. **Usecase 用 `throw` 表達錯誤,搭配 DI token**:每個依賴透過建構子 `@Inject(<TOKEN>)` 注入(TypeScript interface 執行期不存在,單靠型別無法讓 Nest 找到實作,詳見 `references/architecture.md` 規則 2、10);查詢單筆找不到時 Repository 回傳 `null`,UseCaseImpl 轉成共用的 `NotFoundError`;先 `save()` 成功、後 `publish()` 事件;Inbound Port 方法一律回傳 Usecase 自己定義的 `<Entity>Result` 家族型別,方法內部操作完 Domain 才轉換,Domain 物件不可流出 Usecase 邊界。**每個 use case 情境(每條 Business Rule 或查詢需求)各自一個 Inbound Port 介面 + 一個 Impl,不共用一個大介面/大 class**;需要 request body 的 use case,其輸入型別 `<Action>Command` 也定義在本層(跟 `<Entity>Result` 對稱,用 Zod schema);`usecase/<entity>/` 目錄下只放這些 `<action>-<entity>.usecase.ts`,介面收進 `port/`、Result 收進 `result/`、Command 收進 `command/`、事件收進 `event/`。
4. **Adapter/Outbound 隔離技術細節**:TypeORM decorator 只出現在 `<Entity>DataModel`(不叫 `<Entity>Entity`,避免與 TypeORM 自己的 `@Entity()` 和 Domain 的 `<Entity>` 三方撞名);`<Entity>Mapper` 全部為 static 方法;`<Entity>RepositoryImpl` 透過 `@InjectRepository` 實作 Usecase 的 Outbound Port;非 DB 的外部依賴(API/SDK、訊息佇列、快取、通知、檔案儲存)一律命名 `<Provider><Concept>Adapter`,分類到 `client/`、`messaging/`、`cache/`、`notification/`、`storage/` 子目錄,SDK 例外在此層捕捉並轉為自訂例外(如 `PaymentClientError`)後 `throw`。
5. **Adapter/Inbound 只做轉換**:Controller 僅解析參數 → 呼叫 UseCase → 包裝 Response;寫入型輸入物件 `<Action>Command` 是從 usecase 層 import 使用(不叫 Dto,本層不自己定義一份),搭配 `@Body(new ZodValidationPipe(XxxCommandSchema))`;`GlobalExceptionFilter` 統一轉換:`NotFoundError` → 404、`ZodError` → 400、`InvalidStateError`/`InvalidArgumentError` → 400、Nest 內建 `HttpException`(如 `ParseIntPipe` 失敗)→ 照自己狀態碼、其他 → 500;`<Entity>Response` 包裝 Usecase 回傳的 `<Entity>Result` 後回傳(不是 Domain);本層一律不 import `domain/` 底下的型別;每個 entity 一個 `<Entity>Module` 負責把 Port token 繫結到 Impl class(Nest 沒有 classpath 掃描,繫結必須顯式寫出來)。
6. **共用基礎設施只生成一次**:`domain/errors.ts`、`usecase/errors.ts`、`usecase/event-publisher.port.ts`、`adapter/outbound/event/nest-event-publisher.adapter.ts`、`adapter/inbound/http/pipes/zod-validation.pipe.ts`、`adapter/inbound/http/filters/global-exception.filter.ts` 是專案級檔案,不是 per-entity 檔案——第一次在這個專案使用本 skill 時產生,之後每個新 entity 直接重用,不要重複產出(見 `references/architecture.md`)。
7. **命名一律依推導表**:所有型別名稱與檔案路徑依 `references/architecture.md` 的命名推導表從 Entity 名稱產生,不自創命名。
8. **每個檔案完整可編譯**:含完整 import、完整方法實作,零 TODO、零丟出 `Error('not implemented')` 這類佔位程式碼。
9. **產生順序固定**:(共用基礎設施,如未生成 →)(Domain test →)Domain → Usecase → Adapter/Outbound → Adapter/Inbound(→ Controller-level 整合測試)。只有兩個測試層級,詳見 `references/testing_principles.md`:Domain aggregate test 在 Domain 實作前先產(TDD);Controller-level 整合測試要等四層都產完才能產,因為它需要真的組出一個可以跑的 `<Entity>Module` 對它發 HTTP request。usecase 層與 adapter-outbound 層不再各自產生獨立測試。

## 固定輸出格式

整體輸出依序包含三個部分:(1) 專案根目錄註記一行(預設 `src/`)、(2) 產出檔案清單(相對路徑,依產生順序)、(3) 各檔案內容。檢查清單為內部步驟,不出現在輸出中。

每個檔案一律使用以下標頭,讓用戶可直接放置:

```
// === <Layer> Layer ===
// File: src/<layer 路徑>/<file>.ts

<完整 TypeScript 原始碼>
```

## 工作流程

1. **解析與確認**:從輸入提取 Entity 名稱(PascalCase)、Fields(TypeScript 型別)、Business Rules(→ 方法簽名)、Outbound Dependencies、API Endpoints、Tests。輸入為段落描述時,自行整理成規格並請用戶確認;僅在 Entity 名稱或 Fields 完全缺失時才暫停詢問。輸入格式見 `references/architecture.md`。
2. **確認共用基礎設施**:詢問或依上下文判斷這是否是專案第一次使用本 skill;若是,先產生 `src/domain/errors.ts`、`src/usecase/errors.ts`、`src/usecase/event-publisher.port.ts`、`src/adapter/outbound/event/nest-event-publisher.adapter.ts`、`src/adapter/inbound/http/pipes/zod-validation.pipe.ts`、`src/adapter/inbound/http/filters/global-exception.filter.ts`(模板見 `references/architecture.md`),並提醒使用者在 `main.ts`/`AppModule` 掛上 `app.useGlobalFilters(...)`、`EventEmitterModule.forRoot()`。若專案已有這些檔案,跳過此步驟。
3. **(TDD)先產 Domain test**:規格含測試描述時,產生 `<entity>.spec.ts`(Vitest、無 mock、每條業務規則一個正常案例 + 至少一個邊界案例)。這是兩個測試層級中唯一在實作之前產生的一層,詳見 `references/testing_principles.md`。
4. **依序產生四層**:每層產生前先讀取對應 reference 的模板:

   | 層 | Reference | 產出檔案 |
   |---|---|---|
   | 共用 | `references/architecture.md` | 目錄結構、命名推導表、輸入格式、共用基礎設施 |
   | Domain | `references/domain_layer.md` | Entity、Status enum、策略介面(如適用) |
   | Usecase | `references/usecase_layer.md` | Outbound Ports、Result、Command、每個 use case 情境的 Inbound Port + Impl、事件 |
   | Adapter/Outbound | `references/adapter_outbound_layer.md` | TypeORM DataModel、Mapper、RepositoryImpl、(Client/Messaging/Cache/Notification/Storage Adapter) |
   | Adapter/Inbound | `references/adapter_inbound_layer.md` | Response、Controller、Module(Command 已在 Usecase 產出,此處直接 import) |

5. **產生 Controller-level 整合測試**:規格含測試描述時,四層都產生完後,產生 `<entity>.controller.e2e-spec.ts`(用 testcontainers 起真實 DB,見 `references/adapter_inbound_layer.md`)。這是唯一的第二層測試,涵蓋 usecase 串接與 repository 正確性,不再另外產生 usecase mock test 或 adapter-outbound test。
6. **逐層檢查**:每層完成後對照該 reference 的「規則」小節與本文件「產出前檢查」。

## 簡單範例

輸入:

```
Entity: Booking
Fields:
  - id (number)
  - accountId (number)
  - status (enum: PENDING / CONFIRMED / CANCELLED)
Business Rules:
  - confirm(): 只有 PENDING 可確認,否則 throw InvalidStateError
Outbound Dependencies:
  - BookingRepository: 預約持久化
API Endpoints:
  - PUT /api/bookings/{id}/confirm: 確認預約
```

產出檔案清單(命名全部由推導表產生;假設專案已有共用基礎設施):

```
src/domain/booking/booking-status.ts
src/domain/booking/booking.ts
src/usecase/booking/port/booking.repository.ts          ← Outbound Port
src/usecase/booking/result/booking.result.ts            ← Usecase 輸出型別(不回傳 Domain)
src/usecase/booking/port/confirm-booking.usecase-port.ts ← Inbound Port(對應 confirm() 這個 use case)
src/usecase/booking/confirm-booking.usecase.ts           ← 直接放在 usecase/booking/ 目錄下
src/adapter/outbound/repository/datamodel/booking.data-model.ts
src/adapter/outbound/repository/mapper/booking.mapper.ts
src/adapter/outbound/repository/booking.repository-impl.ts
src/adapter/inbound/http/booking/booking.response.ts
src/adapter/inbound/http/booking/booking.controller.ts
src/adapter/inbound/http/booking/booking.module.ts
```

其中 Domain 實體產出樣貌(對應規則 2 與固定輸出格式):

```typescript
// === Domain Layer ===
// File: src/domain/booking/booking.ts

import { InvalidArgumentError, InvalidStateError } from '../errors';
import { BookingStatus } from './booking-status';

export class Booking {
  private readonly _id: number | null;
  private readonly _accountId: number;
  private _status: BookingStatus;

  constructor(id: number | null, accountId: number, status: BookingStatus) {
    if (accountId === null || accountId === undefined) {
      throw new InvalidArgumentError('accountId must not be null');
    }
    if (!status) {
      throw new InvalidArgumentError('status must not be null');
    }
    this._id = id;
    this._accountId = accountId;
    this._status = status;
  }

  // 業務行為:確認預約
  confirm(): void {
    if (this._status !== BookingStatus.PENDING) {
      throw new InvalidStateError('Only PENDING booking can be confirmed');
    }
    this._status = BookingStatus.CONFIRMED;
  }

  get id(): number | null { return this._id; }
  get accountId(): number { return this._accountId; }
  get status(): BookingStatus { return this._status; }
}
```

## 產出前檢查

- [ ] Domain 檔案不 import 任何 npm 套件,只 import 同層檔案與 `domain/errors.ts`
- [ ] 每個 Outbound Port 方法回傳 `Promise<T>`;Domain 方法不是 `async`
- [ ] 事件在 `save()` 之後 publish
- [ ] TypeORM decorator 只在 `<Entity>DataModel`;Mapper 全 static
- [ ] 每個 use case 情境各自一個 Inbound Port(只宣告一個方法)+ 一個 Impl,沒有共用的大介面/大 class;方法皆回傳 `<Entity>Result` 家族型別,不直接回傳 Domain
- [ ] `usecase/<entity>/` 目錄下只有 `<action>-<entity>.usecase.ts`(每個 use case 一個);介面在 `port/`、Result 在 `result/`、Command 在 `command/`、事件在 `event/`
- [ ] `<Action>Command` 定義在 usecase 層(Zod schema),不在 Adapter/Inbound 重複定義一份
- [ ] 每個 Port 介面旁邊都有對應的 `Symbol` token 匯出;UseCaseImpl / Controller 用 `@Inject(TOKEN)` 取得依賴,不是單靠型別
- [ ] 找不到資料一律 `throw new NotFoundError(...)`(共用型別),不是每個 entity 各自定義的例外類別
- [ ] Controller 無 if/else 業務邏輯;回傳皆為 `<Entity>Response`;輸入物件皆為 `<Action>Command`(無 Dto 命名);不 import `domain/` 底下的型別
- [ ] 每個 entity 有對應的 `<Entity>Module` 把 Port token 繫結到 Impl class
- [ ] 所有型別名稱符合命名推導表
- [ ] 每個檔案有輸出標頭、完整 import、零 TODO
- [ ] 只有兩個測試層級:Domain test(無 mock)+ Controller-level 整合測試(testcontainers 起真實 DB);沒有另外產生 usecase mock test 或 adapter-outbound 獨立 test
- [ ] Controller-level 整合測試的寫入類斷言不是只看 HTTP 回應,而是再查一次資料確認真的落地
