# Domain 層 — 領域實體與核心業務

## 規則

1. 只 import 同層(`domain/`)的其他檔案與共用的 `domain/errors.ts`;不 import 任何 npm 套件(NestJS、TypeORM、Zod 一律不出現在這一層)——Domain 是純 TypeScript。
2. 業務邏輯寫在實體的行為方法內(充血模型);每條 Business Rule 對應一個方法。
3. 建構子驗證所有輸入,失敗時 `throw new InvalidArgumentError('<field> must not be null')`;不建構出一個半成品實體。
4. 欄位一律 `private readonly`(不可變欄位)或 `private`(可變狀態欄位);對外只透過 getter(`get <field>(): Type`)存取,沒有 setter——狀態只能透過業務方法變更,呼叫端無法繞過業務規則直接改欄位。
5. 狀態列舉 `<Entity>Status` 與實體定義在同一個 domain 目錄下,用 TypeScript `enum`(字串值),不用數字列舉——字串值可直接對映到 DB 欄位與 JSON,不需要額外轉換表。
6. 行為隨型別變化時,定義策略介面 `<Concept>` 與多個實作 class,以多型取代 if-else。
7. 唯讀值物件(如外部系統查回的資料)用只有 `readonly` 欄位的 plain class 或 interface,不需要驗證邏輯。
8. 業務規則違反時,一律 `throw` 共用的例外類別(`src/domain/errors.ts`,見 `references/architecture.md`):狀態轉移錯誤 `throw new InvalidStateError(...)`、建構參數不合法 `throw new InvalidArgumentError(...)`——不要每個 entity 各自定義新的例外類別,呼叫端才能統一用 `instanceof InvalidStateError` 判斷種類。

## 產出檔案(依序)

1. `<entity>-status.ts`(如有狀態欄位)
2. `<concept>.ts` + 各實作(如有策略介面)
3. `<entity>.ts`

## 模板

### 狀態列舉 `<entity>-status.ts`

```typescript
export enum BookingStatus {
  PENDING = 'PENDING',
  CONFIRMED = 'CONFIRMED',
  CANCELLED = 'CANCELLED',
}
```

### 核心實體 `<entity>.ts`

```typescript
import { InvalidArgumentError, InvalidStateError } from '../errors';
import { BookingStatus } from './booking-status';

export class Booking {
  private readonly _id: number | null;
  private readonly _immutableField: string;   // 建構後不再變動的欄位
  private _status: BookingStatus;             // 可變狀態欄位

  constructor(id: number | null, immutableField: string, status: BookingStatus) {
    if (!immutableField) {
      throw new InvalidArgumentError('immutableField must not be empty');
    }
    if (!status) {
      throw new InvalidArgumentError('status must not be null');
    }
    this._id = id;
    this._immutableField = immutableField;
    this._status = status;
  }

  // 業務行為:每條 Business Rule 產生一個方法,狀態檢查失敗 throw InvalidStateError
  businessMethod(): void {
    if (this._status !== BookingStatus.PENDING) {
      throw new InvalidStateError(
        `Only PENDING booking can businessMethod, current status is ${this._status}`,
      );
    }
    this._status = BookingStatus.CONFIRMED;
  }

  // 查詢型業務方法回傳 boolean,不變更狀態
  canBusinessQuery(): boolean {
    return this._status === BookingStatus.PENDING;
  }

  get id(): number | null { return this._id; }
  get immutableField(): string { return this._immutableField; }
  get status(): BookingStatus { return this._status; }
}
```

### 策略介面(行為隨型別變化時)

```typescript
export interface Concept {
  readonly type: ConceptType;
  behavior(): ReturnType;
}
```

各實作 class(如 `FreeConcept` / `StandardConcept`)`implements Concept`,差異行為封裝在各自的方法內,靠 TypeScript 的結構化型別系統確保實作正確,不需要額外的編譯期檢查語法(對照 Go 版本的 `var _ Concept = (*FreeConcept)(nil)`,TypeScript 的 `implements` 關鍵字在編譯期就會檢查缺漏的方法,不需要多寫一行)。

### 唯讀值物件

```typescript
export class ValueObject {
  constructor(
    readonly field1: Type1,
    readonly field2: Type2,
  ) {}
}
```

## 單元測試模板(TDD 時先產)

一個實體一個測試檔 `<entity>.spec.ts`,不使用 mock(Domain 沒有外部依賴),用 `it.each` 涵蓋每條 Business Rule 的正常案例與至少一個邊界案例:

```typescript
import { describe, expect, it } from 'vitest';
import { Booking } from './booking';
import { BookingStatus } from './booking-status';
import { InvalidStateError } from '../errors';

describe('Booking.businessMethod', () => {
  it.each([
    { name: 'eligible status succeeds', initialStatus: BookingStatus.PENDING, wantErr: false },
    { name: 'ineligible status fails', initialStatus: BookingStatus.CONFIRMED, wantErr: true },
  ])('$name', ({ initialStatus, wantErr }) => {
    const booking = new Booking(1, 'field', initialStatus);

    if (wantErr) {
      expect(() => booking.businessMethod()).toThrow(InvalidStateError);
    } else {
      booking.businessMethod();
      expect(booking.status).toBe(BookingStatus.CONFIRMED);
    }
  });
});
```
