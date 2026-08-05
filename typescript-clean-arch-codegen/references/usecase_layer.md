# Usecase 層 — 業務案例與介面合約

## 規則

1. 只 import Domain 目錄(`domain/<entity>`)、本層自己的子目錄(`port`/`result`/`command`/`event`)、共用的 `usecase/errors.ts`、`usecase/event-publisher.port.ts`;`@nestjs/common` 的 `Injectable`/`Inject` decorator 是本層唯一允許的 NestJS import(拿掉它們程式碼在邏輯上仍然完全正確,只是失去 DI 能力——這一點刻意跟 Java 版本的 `@Transactional` 不同,因為 TypeScript 沒有宣告式交易,加這兩個 decorator純粹是為了讓 Nest 的 DI 容器認得這個 class)。
2. 先定義 Outbound Ports(Repository、Client/Messaging/Cache/Notification/Storage 等外部依賴)為介面,再定義 Inbound Port,最後實作對應的 UseCaseImpl。**每個 use case 情境(每條 Business Rule 或每個查詢需求)各自一個 Inbound Port 介面 + 一個 Impl,不共用一個大介面**:介面命名 `<Action><Entity>UseCase`(如 `CreateBookingUseCase`、`ConfirmBookingUseCase`、`GetBookingUseCase`),各自只宣告一個方法;Impl 命名 `<Action><Entity>UseCaseImpl`,只依賴自己需要的 Outbound Port,不共用一個大 Impl。
3. 所有依賴透過建構子注入,每個依賴搭配 `@Inject(<TOKEN>)`(見 `references/architecture.md` 規則 10);Impl class 標 `@Injectable()`,本身無狀態,可安全跨請求重用(Nest 預設 provider 是 singleton)。
4. 查詢單筆一律:`repository.getById(id)` 回傳 `Promise<Booking | null>`,查無資料時回傳 `null`(不是 throw)——呼叫端(UseCaseImpl)檢查 `if (!booking)` 後 `throw new NotFoundError('<entity>', id)`。找不到本身不是錯誤,是查詢結果的一種(有 vs. 沒有);是否要把它當成錯誤處理,由呼叫端決定。
5. 領域事件在 `save()` 成功之後 publish(`await eventPublisher.publish(new XxxEvent(...))`);事件用 plain class 定義在 `usecase/<entity>/event/`。
6. 找不到資料時一律 `throw new NotFoundError('<entity>', id)`(共用型別,見 `references/architecture.md`),不用每個 entity 各自定義一個新的例外類別——這個型別的欄位已經足以表達任何 entity 的 not-found 情境。
7. Repository Port 的標準方法簽名:`getById(id: number): Promise<Booking | null>`、`save(entity: Booking): Promise<Booking>`,查詢條件方法命名為 `getBy<Field>`。
8. **Inbound Port 的方法一律回傳 `<Entity>Result` 家族型別,不直接回傳 Domain `Booking`**:Domain 物件(及其業務方法)只能在 Usecase 內部與 Repository 之間流動,絕不可流出 Usecase 邊界。UseCaseImpl 內部正常操作 Domain(呼叫業務方法、`save()`),方法回傳前才用 `XxxResult.from(domain)` 轉換。Result 用 plain class(無業務方法、欄位皆 `readonly`)定義,命名依用途:
   - 預設(單筆查詢/寫入後回傳完整資料):`<Entity>Result`
   - 列表查詢、欄位精簡:`<Entity>SummaryResult`
   - 特定 use case 需要客製欄位(如包含關聯資料):依實際需求命名,不勉強套單一模板
9. **`usecase/<entity>/` 目錄下只放 `<action>-<entity>.usecase.ts`(每個 use case 情境一個檔案)**,其餘依類型分子目錄,點進去就能一眼看到這個 entity 有哪些 use case、各自的設計內容而不必打開實作:
   - `port/`:所有介面——每個 use case 的 Inbound Port(`<Action><Entity>UseCase`)與這個 entity 專屬的 Outbound Port(`<Entity>Repository`、`<Concept>Client` 等;共用的 `DomainEventPublisher` 不在這裡,見 `references/architecture.md`)
   - `result/`:`<Entity>Result` 家族(Usecase 輸出型別)
   - `command/`:`<Action>Command` 家族(Usecase 輸入型別,規則 10)
   - `event/`:領域事件
10. **寫入型 endpoint 的輸入型別 `<Action>Command` 定義在本層**(`usecase/<entity>/command/`),不在 Adapter/Inbound:跟 Result 對稱,同樣是 Usecase 自己擁有的邊界資料結構,用 Zod schema 驗證欄位(`z.object({...})`,搭配 `z.infer<typeof Schema>` 推導出型別)——`<Action>Command` 這個檔案是本層唯一允許 import `zod` 的地方。Inbound Port 方法直接以 `<Action>Command` 為參數(不拆欄位傳原始型別),Adapter 層的 Controller 直接 import 這個 Command 使用,不自己另外定義一份。單一 ID 這種簡單查詢/狀態變更(如 `confirm(bookingId: number)`、`getById(bookingId: number)`)不需要包 Command,直接傳 `number` 即可。

## 產出檔案(依序)

1. `port/<entity>.repository.ts`(Outbound Port)
2. `port/<concept>.client.ts` / `port/<concept>.message-publisher.ts` / `port/<concept>.cache-store.ts` / `port/<concept>.notification-sender.ts` / `port/<concept>.file-storage.ts`(Outbound Port,依外部依賴性質擇一,如有)
3. `event/<entity>-<action>.event.ts`(如有事件)
4. `result/<entity>.result.ts`(+ 其他 Result 變體,如 `result/<entity>-summary.result.ts`,依規則 8 擇一或並存)
5. `command/<action>-<entity>.command.ts`(每個需要 request body 的 use case 一個,依規則 10)
6. 對每個 use case 情境重複:`port/<action>-<entity>.usecase-port.ts`(Inbound Port)+ `<action>-<entity>.usecase.ts`(直接放在 `usecase/<entity>/` 目錄下)

## 模板

### Outbound Port — Repository

```typescript
// usecase/booking/port/booking.repository.ts
import { Booking } from '../../../domain/booking/booking';

export const BOOKING_REPOSITORY = Symbol('BookingRepository');

export interface BookingRepository {
  getById(id: number): Promise<Booking | null>;
  save(booking: Booking): Promise<Booking>;
}
```

### Outbound Port — 外部依賴(Client / Messaging / Cache / Notification / Storage)

依外部依賴的性質選擇介面命名(見 `references/adapter_outbound_layer.md` 的分類表),方法簽名皆相同模式,以 Client(呼叫外部 API/SDK)為例:

```typescript
// usecase/booking/port/payment.client.ts
import { Booking } from '../../../domain/booking/booking';

export const PAYMENT_CLIENT = Symbol('PaymentClient');

export interface PaymentClient {
  charge(booking: Booking): Promise<string>;
}
```

其餘分類介面命名同樣模式:`<Concept>MessagePublisher`(訊息佇列)、`<Concept>CacheStore`(快取)、`<Concept>NotificationSender`(通知)、`<Concept>FileStorage`(檔案儲存),都放在 `usecase/<entity>/port/`。

### 領域事件

```typescript
// usecase/booking/event/booking-confirmed.event.ts
export class BookingConfirmedEvent {
  constructor(
    readonly bookingId: number,
    readonly payloadField: Type,
  ) {}
}
```

### Result(Usecase 輸出型別,取代直接回傳 Domain)

```typescript
// usecase/booking/result/booking.result.ts
import { Booking } from '../../../domain/booking/booking';

export class BookingResult {
  constructor(
    readonly id: number,
    readonly field: Type,
    readonly status: string,
  ) {}

  static from(booking: Booking): BookingResult {
    return new BookingResult(booking.id!, booking.field, booking.status);
  }
}
```

列表查詢用的精簡變體(欄位依實際需求增減):

```typescript
// usecase/booking/result/booking-summary.result.ts
import { Booking } from '../../../domain/booking/booking';

export class BookingSummaryResult {
  constructor(
    readonly id: number,
    readonly status: string,
  ) {}

  static from(booking: Booking): BookingSummaryResult {
    return new BookingSummaryResult(booking.id!, booking.status);
  }
}
```

### Command(Usecase 輸入型別,與 Result 對稱)

用 Zod schema 定義,型別用 `z.infer` 推導出來,不手寫重複的 interface:

```typescript
// usecase/booking/command/create-booking.command.ts
import { z } from 'zod';

export const CreateBookingCommandSchema = z.object({
  field: z.string({ required_error: 'field must not be null' }),
});

export type CreateBookingCommand = z.infer<typeof CreateBookingCommandSchema>;
```

### Inbound Port(每個 use case 情境一個檔案)

每個介面只宣告**一個方法**,不 import Domain `Booking`——方法簽名只暴露 Result(和需要時的 Command),呼叫方(Controller)因此也不需要認識 Domain。以帶 request body 的寫入型(`CreateBookingUseCase`)、只靠路徑參數的寫入型(`ConfirmBookingUseCase` 風格)、查詢型(`GetBookingUseCase`)各一個為例:

```typescript
// usecase/booking/port/create-booking.usecase-port.ts
import { CreateBookingCommand } from '../command/create-booking.command';
import { BookingResult } from '../result/booking.result';

export const CREATE_BOOKING_USE_CASE = Symbol('CreateBookingUseCase');

export interface CreateBookingUseCase {
  create(command: CreateBookingCommand): Promise<BookingResult>;
}
```

```typescript
// usecase/booking/port/confirm-booking.usecase-port.ts
import { BookingResult } from '../result/booking.result';

export const CONFIRM_BOOKING_USE_CASE = Symbol('ConfirmBookingUseCase');

export interface ConfirmBookingUseCase {
  confirm(bookingId: number): Promise<BookingResult>;
}
```

```typescript
// usecase/booking/port/get-booking.usecase-port.ts
import { BookingResult } from '../result/booking.result';

export const GET_BOOKING_USE_CASE = Symbol('GetBookingUseCase');

export interface GetBookingUseCase {
  getById(bookingId: number): Promise<BookingResult>;
}
```

### UseCase 實作(每個 use case 情境一個檔案,直接放在 `usecase/<entity>/` 目錄下)

帶 Command 的寫入型 Impl:

```typescript
// usecase/booking/create-booking.usecase.ts
import { Inject, Injectable } from '@nestjs/common';
import { Booking } from '../../domain/booking/booking';
import { BookingStatus } from '../../domain/booking/booking-status';
import { CreateBookingCommand } from './command/create-booking.command';
import { BOOKING_REPOSITORY, BookingRepository } from './port/booking.repository';
import { CreateBookingUseCase } from './port/create-booking.usecase-port';
import { BookingResult } from './result/booking.result';

@Injectable()
export class CreateBookingUseCaseImpl implements CreateBookingUseCase {
  constructor(
    @Inject(BOOKING_REPOSITORY) private readonly bookingRepository: BookingRepository,
  ) {}

  async create(command: CreateBookingCommand): Promise<BookingResult> {
    const booking = new Booking(null, command.field, BookingStatus.PENDING);
    const saved = await this.bookingRepository.save(booking);
    return BookingResult.from(saved);
  }
}
```

只靠路徑參數、不需要 Command 的寫入型 Impl,只依賴自己需要的 Outbound Port(不強塞其他 use case 用不到的依賴):

```typescript
// usecase/booking/confirm-booking.usecase.ts
import { Inject, Injectable } from '@nestjs/common';
import { DOMAIN_EVENT_PUBLISHER, DomainEventPublisher } from '../event-publisher.port';
import { NotFoundError } from '../errors';
import { BookingConfirmedEvent } from './event/booking-confirmed.event';
import { BOOKING_REPOSITORY, BookingRepository } from './port/booking.repository';
import { ConfirmBookingUseCase } from './port/confirm-booking.usecase-port';
import { BookingResult } from './result/booking.result';

@Injectable()
export class ConfirmBookingUseCaseImpl implements ConfirmBookingUseCase {
  constructor(
    @Inject(BOOKING_REPOSITORY) private readonly bookingRepository: BookingRepository,
    @Inject(DOMAIN_EVENT_PUBLISHER) private readonly eventPublisher: DomainEventPublisher,
  ) {}

  async confirm(bookingId: number): Promise<BookingResult> {
    const booking = await this.bookingRepository.getById(bookingId);
    if (!booking) {
      throw new NotFoundError('booking', bookingId);
    }

    booking.businessMethod();                                    // 1. 呼叫 Domain 業務方法
    const saved = await this.bookingRepository.save(booking);    // 2. 持久化

    // 3. 保存成功後發送領域事件
    await this.eventPublisher.publish(new BookingConfirmedEvent(saved.id!, saved.field));

    // 4. Domain 到此為止,轉成 Result 才回傳給外層(Adapter 不可見 Domain)
    return BookingResult.from(saved);
  }
}
```

查詢型 Impl:不呼叫 `save()`、不 publish 事件、不需要 `DomainEventPublisher` 依賴:

```typescript
// usecase/booking/get-booking.usecase.ts
import { Inject, Injectable } from '@nestjs/common';
import { NotFoundError } from '../errors';
import { BOOKING_REPOSITORY, BookingRepository } from './port/booking.repository';
import { GetBookingUseCase } from './port/get-booking.usecase-port';
import { BookingResult } from './result/booking.result';

@Injectable()
export class GetBookingUseCaseImpl implements GetBookingUseCase {
  constructor(
    @Inject(BOOKING_REPOSITORY) private readonly bookingRepository: BookingRepository,
  ) {}

  async getById(bookingId: number): Promise<BookingResult> {
    const booking = await this.bookingRepository.getById(bookingId);
    if (!booking) {
      throw new NotFoundError('booking', bookingId);
    }
    return BookingResult.from(booking);
  }
}
```

## 單元測試模板(TDD 時先產)

一個 use case 一個測試檔,命名 `<action>-<entity>.usecase.spec.ts`,用 `vi.fn()` 手寫該 use case 真正用到的 Outbound Port 的假物件——不需要透過 Nest 的 `Test.createTestingModule` 起一個完整 DI 容器,UseCaseImpl 的建構子是 plain constructor,直接 `new` 並傳入 mock 物件即可,跑得更快:

```typescript
// usecase/booking/confirm-booking.usecase.spec.ts
import { describe, expect, it, vi } from 'vitest';
import { Booking } from '../../domain/booking/booking';
import { BookingStatus } from '../../domain/booking/booking-status';
import { DomainEventPublisher } from '../event-publisher.port';
import { NotFoundError } from '../errors';
import { ConfirmBookingUseCaseImpl } from './confirm-booking.usecase';
import { BookingRepository } from './port/booking.repository';

function createMockRepository(): BookingRepository {
  return { getById: vi.fn(), save: vi.fn() };
}

function createMockPublisher(): DomainEventPublisher {
  return { publish: vi.fn() };
}

describe('ConfirmBookingUseCaseImpl', () => {
  it('confirms a pending booking and publishes an event', async () => {
    const repository = createMockRepository();
    const publisher = createMockPublisher();
    const booking = new Booking(1, 'field', BookingStatus.PENDING);
    vi.mocked(repository.getById).mockResolvedValue(booking);
    vi.mocked(repository.save).mockImplementation(async (b) => b);

    const useCase = new ConfirmBookingUseCaseImpl(repository, publisher);
    const result = await useCase.confirm(1);

    expect(result.status).toBe(BookingStatus.CONFIRMED);
    expect(publisher.publish).toHaveBeenCalledOnce();
  });

  it('throws NotFoundError when the booking does not exist', async () => {
    const repository = createMockRepository();
    const publisher = createMockPublisher();
    vi.mocked(repository.getById).mockResolvedValue(null);

    const useCase = new ConfirmBookingUseCaseImpl(repository, publisher);

    await expect(useCase.confirm(99)).rejects.toThrow(NotFoundError);
  });
});
```
