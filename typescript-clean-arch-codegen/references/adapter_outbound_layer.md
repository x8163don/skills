# Adapter/Outbound 層 — 外部基礎設施整合(Interface Adapters,驅動內層依賴的一側)

## 規則

1. TypeORM decorator(`@Entity`, `@Column`, `@PrimaryGeneratedColumn`)只出現在 `<Entity>DataModel`;Domain class 保持零 decorator、零第三方 import。命名一律叫 `<Entity>DataModel`,不叫 `<Entity>Entity`——避免跟 TypeORM 自己的 `@Entity()` decorator 和 Domain 的 `<Entity>` 三方撞名混淆。
2. `<Entity>DataModel` 用 `@Column({ name: '<snake_case>' })` 指定欄位名,`@Entity('<snake_case_plural>')` 指定資料表名;所有欄位顯式宣告(用 `!` non-null assertion,因為值一律由 TypeORM 填入,不需要建構子),跟 Domain 欄位一一對應,方便 Mapper 轉換時一眼看出對應關係。
3. `<Entity>Mapper` 全部是 class 上的 `static` 方法(`toDomain` / `toDataModel`),不標 `@Injectable()`、不被注入;兩個方法開頭皆做 null 檢查,輸入為 `null` 時回傳 `null`。
4. `<Entity>RepositoryImpl` 標 `@Injectable()`,實作 Usecase 的 `<Entity>Repository`(Outbound Port),透過 `@InjectRepository(<Entity>DataModel)` 注入 TypeORM 的 `Repository<<Entity>DataModel>`,內部呼叫 TypeORM API 並經 Mapper 轉換;`getById` 用 `findOneBy({ id })`,TypeORM 找不到時回傳 `null`(剛好對映 Usecase 層規則 4 的「找不到不是錯誤」,不需要額外 catch)。
5. 外部 SDK(Stripe、Kafka、Redis 等)只在對應的 `adapter/outbound/<category>` 子目錄 import;SDK 丟出的例外在此層捕捉,轉為自訂例外(如 `PaymentClientError`,`extends Error` 並保留原始 `cause`)後 `throw`,不讓 SDK 的原始例外型別外流到 Usecase。
6. 每個外部依賴 Adapter 的建構子接收已經解析好的設定值(API key、endpoint 等字串/數值),不在 Adapter 內部直接讀 `process.env`——設定值統一在 Module 的 provider 工廠(`useFactory` + `ConfigService`)或 `main.ts` 讀取後注入,Adapter 本身保持可測試、不依賴全域狀態。
7. 依外部依賴的性質分類到對應子目錄,Outbound Port 與 Adapter 命名對照:

   | 子目錄 | Outbound Port(usecase 層介面) | Adapter 實作 | 例外命名 | 範例 |
   |---|---|---|---|---|
   | `client/` | `<Concept>Client` | `<Provider><Concept>Adapter` | `<Concept>ClientError` | `PaymentClient` → `StripePaymentAdapter` |
   | `messaging/` | `<Concept>MessagePublisher` | `<Provider><Concept>Adapter` | `<Concept>MessagingError` | `OrderMessagePublisher` → `KafkaOrderAdapter` |
   | `cache/` | `<Concept>CacheStore` | `<Provider><Concept>Adapter` | `<Concept>CacheError` | `BookingCacheStore` → `RedisBookingAdapter` |
   | `notification/` | `<Concept>NotificationSender` | `<Provider><Concept>Adapter` | `<Concept>NotificationError` | `SmsNotificationSender` → `TwilioSmsAdapter` |
   | `storage/` | `<Concept>FileStorage` | `<Provider><Concept>Adapter` | `<Concept>StorageError` | `AttachmentFileStorage` → `S3AttachmentAdapter` |

   五類結構完全相同(見下方模板),只有子目錄、Port 介面名稱、例外名稱不同。
8. 事件發送使用共用的 `NestDomainEventPublisherAdapter`(見 `references/architecture.md`),不要每個 entity 各自產生一份——這是 in-process 的 domain event,跟 `messaging/`(對外部訊息佇列發送)是不同用途,不可混用。
9. **測試**:`<entity>.mapper.spec.ts` 是純函式測試,不需要任何測試替身;`<entity>.repository-impl.spec.ts` 不 mock TypeORM,改用 `better-sqlite3` 搭配 `type: 'better-sqlite3', database: ':memory:', synchronize: true` 起一個真實的記憶體 `DataSource` 跑真實查詢——避免手動比對 TypeORM 產生的 SQL 語句這種脆弱的斷言方式。外部依賴 Adapter(`client`/`messaging`/`cache`/`notification`/`storage`)預設不產生測試:這層是薄薄的第三方 SDK 轉接層,要測就得先把 SDK 呼叫包成可注入的欄位、再用 `vi.mock` 假冒,做法因 SDK 而異,不強行套統一模板。

## 產出檔案(依序)

1. `datamodel/<entity>.data-model.ts`
2. `mapper/<entity>.mapper.ts`(+ `mapper/<entity>.mapper.spec.ts`,如有測試描述)
3. `<entity>.repository-impl.ts`(+ `<entity>.repository-impl.spec.ts`,如有測試描述)
4. `<category>/<provider>-<concept>.adapter.ts`(如有 Client/Messaging/Cache/Notification/Storage Port,`<category>` 依規則 7 的分類表擇一)

`event/nest-event-publisher.adapter.ts` 是共用基礎設施(見 `references/architecture.md`),僅專案第一次使用本 skill 時產生,本層不重複產出。

## 模板

### TypeORM DataModel `datamodel/<entity>.data-model.ts`

```typescript
import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity('bookings')
export class BookingDataModel {
  @PrimaryGeneratedColumn()
  id!: number;

  @Column({ name: 'field' })
  field!: string;

  @Column({ name: 'status' })
  status!: string;               // enum 一律以字串儲存
}
```

### 對映器 `mapper/<entity>.mapper.ts`

```typescript
import { Booking } from '../../../../domain/booking/booking';
import { BookingStatus } from '../../../../domain/booking/booking-status';
import { BookingDataModel } from '../datamodel/booking.data-model';

export class BookingMapper {
  static toDomain(dataModel: BookingDataModel | null): Booking | null {
    if (!dataModel) return null;
    return new Booking(dataModel.id, dataModel.field, dataModel.status as BookingStatus);
  }

  static toDataModel(domain: Booking | null): BookingDataModel | null {
    if (!domain) return null;
    const dataModel = new BookingDataModel();
    dataModel.id = domain.id ?? undefined!;
    dataModel.field = domain.field;
    dataModel.status = domain.status;
    return dataModel;
  }
}
```

### Outbound Port 實作 `<entity>.repository-impl.ts`

```typescript
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Booking } from '../../../domain/booking/booking';
import { BookingRepository } from '../../../usecase/booking/port/booking.repository';
import { BookingDataModel } from './datamodel/booking.data-model';
import { BookingMapper } from './mapper/booking.mapper';

@Injectable()
export class BookingRepositoryImpl implements BookingRepository {
  constructor(
    @InjectRepository(BookingDataModel)
    private readonly repository: Repository<BookingDataModel>,
  ) {}

  async getById(id: number): Promise<Booking | null> {
    const dataModel = await this.repository.findOneBy({ id });
    return BookingMapper.toDomain(dataModel);
  }

  async save(booking: Booking): Promise<Booking> {
    const saved = await this.repository.save(BookingMapper.toDataModel(booking)!);
    return BookingMapper.toDomain(saved)!;
  }
}
```

### 外部依賴 Adapter `<category>/<provider>-<concept>.adapter.ts`

以 `client/` 為例(`messaging/`、`cache/`、`notification/`、`storage/` 套用同一個模板,只換子目錄、Port 介面、例外類別名稱):

```typescript
import { Inject, Injectable } from '@nestjs/common';
import { Booking } from '../../../domain/booking/booking';
import { PaymentClient } from '../../../usecase/booking/port/payment.client';

export class PaymentClientError extends Error {
  constructor(message: string, readonly cause?: unknown) {
    super(message);
    this.name = 'PaymentClientError';
  }
}

@Injectable()
export class StripePaymentAdapter implements PaymentClient {
  constructor(@Inject('STRIPE_API_KEY') private readonly apiKey: string) {}

  async charge(booking: Booking): Promise<string> {
    try {
      // 呼叫 Stripe SDK
      return await stripeSdkCharge(this.apiKey, booking);
    } catch (err) {
      throw new PaymentClientError('Failed to charge via Stripe', err);
    }
  }
}
```

`@Inject('STRIPE_API_KEY')` 這類純值 token 由 entity 的 Module 用 `{ provide: 'STRIPE_API_KEY', useValue: configService.get('STRIPE_API_KEY') }` 提供(見 `references/adapter_inbound_layer.md` 的 Module 模板),設定值來源用 `@nestjs/config` 的 `ConfigService`,不在 Adapter 內部直接讀 `process.env`。

## 單元測試模板(規格含測試描述時產生)

### Mapper 測試 `mapper/<entity>.mapper.spec.ts`

純函式,不需要任何測試替身:

```typescript
import { describe, expect, it } from 'vitest';
import { Booking } from '../../../../domain/booking/booking';
import { BookingStatus } from '../../../../domain/booking/booking-status';
import { BookingDataModel } from '../datamodel/booking.data-model';
import { BookingMapper } from './booking.mapper';

describe('BookingMapper', () => {
  it('toDomain converts a data model', () => {
    const dataModel = new BookingDataModel();
    dataModel.id = 1;
    dataModel.field = 'value';
    dataModel.status = 'PENDING';

    const domain = BookingMapper.toDomain(dataModel);

    expect(domain?.id).toBe(1);
    expect(domain?.status).toBe(BookingStatus.PENDING);
  });

  it('toDomain returns null for null input', () => {
    expect(BookingMapper.toDomain(null)).toBeNull();
  });

  it('toDataModel converts a domain entity', () => {
    const domain = new Booking(1, 'value', BookingStatus.PENDING);

    const dataModel = BookingMapper.toDataModel(domain);

    expect(dataModel?.field).toBe('value');
    expect(dataModel?.status).toBe('PENDING');
  });
});
```

### Repository 測試 `<entity>.repository-impl.spec.ts`

用記憶體 SQLite(`better-sqlite3`)起真實的 TypeORM `DataSource` 跑真實查詢,不 mock `Repository`:

```typescript
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DataSource } from 'typeorm';
import { Booking } from '../../../domain/booking/booking';
import { BookingStatus } from '../../../domain/booking/booking-status';
import { BookingDataModel } from './datamodel/booking.data-model';
import { BookingRepositoryImpl } from './booking.repository-impl';

describe('BookingRepositoryImpl', () => {
  let dataSource: DataSource;
  let repository: BookingRepositoryImpl;

  beforeEach(async () => {
    dataSource = new DataSource({
      type: 'better-sqlite3',
      database: ':memory:',
      entities: [BookingDataModel],
      synchronize: true,
    });
    await dataSource.initialize();
    repository = new BookingRepositoryImpl(dataSource.getRepository(BookingDataModel));
  });

  afterEach(async () => {
    await dataSource.destroy();
  });

  it('saves and retrieves a booking', async () => {
    const booking = new Booking(null, 'value', BookingStatus.PENDING);

    const saved = await repository.save(booking);
    const found = await repository.getById(saved.id!);

    expect(found?.id).toBe(saved.id);
    expect(found?.status).toBe(BookingStatus.PENDING);
  });

  it('returns null when not found', async () => {
    const found = await repository.getById(999);

    expect(found).toBeNull();
  });
});
```
