# Adapter/Inbound 層 — 通訊與應用進入點(Interface Adapters,被外部驅動的一側)

## 規則

1. NestJS 的 HTTP decorator(`@Controller`, `@Get`, `@Post`, `@Put`, `@Delete`, `@Body`, `@Param`)只出現在本層。
2. Controller 方法固定三步:解析參數(`@Param`/`@Body` + Pipe)→ 呼叫 UseCase(Inbound Port)→ 回傳 Response;方法內零業務判斷,錯誤直接讓例外往上拋(不在 Controller `try/catch`),統一交給全域的 `GlobalExceptionFilter` 處理(見 `references/architecture.md`)。
3. Controller 依賴 UseCase **介面**(不是 Impl),用 `@Inject(<TOKEN>)` 建構子注入(見 `references/architecture.md` 規則 2、10);每個 use case 情境是獨立的窄介面,Controller 有幾個 endpoint 就注入幾個對應的 UseCase 介面欄位,不共用一個大介面。
4. `<Action>Command` 定義在 **usecase 層**(`usecase/<entity>/command/`,見 `references/usecase_layer.md`),不在本層;Controller 直接 import 使用,不自己另外定義一份,搭配 `@Body(new ZodValidationPipe(XxxCommandSchema))` 綁定並驗證(`ZodValidationPipe` 是共用基礎設施,見 `references/architecture.md`)。
5. Response 包裝 Usecase 回傳的 `<Entity>Result`(不是 Domain 物件);提供 `static from(result: XxxResult): XxxResponse` 工廠方法;Domain 物件與其業務方法不可流出 Usecase 邊界,本層一律不 import `domain/` 底下的型別;不叫 `Dto`,一律叫 `<Entity>Response`。
6. 狀態碼:Nest 對 `@Post()` 預設回 `201`、其餘方法(`@Get`/`@Put`/`@Patch`)預設回 `200`,不需要每個方法額外標 `@HttpCode`;刪除型 endpoint 才需要顯式 `@HttpCode(HttpStatus.NO_CONTENT)`(204)。
7. 路徑參數用 `@Param('id', ParseIntPipe) id: number` 取得並轉型(Nest 內建 `ParseIntPipe`,轉型失敗會丟 Nest 自己的 `BadRequestException`,一樣交給 `GlobalExceptionFilter` 處理)。
8. URL 命名:`api/<entities>`(複數、kebab-case,不需要開頭斜線,`@Controller()` 裝飾器裡的路徑不加開頭 `/`)。
9. 每個 entity 一個 `<Entity>Module`,負責:`TypeOrmModule.forFeature([<Entity>DataModel])`、註冊 Controller、把每個 Port token 繫結到對應的 Impl class(`{ provide: TOKEN, useClass: Impl }`)。這個 skill 不產生根目錄的 `AppModule`,只提醒使用者把 `<Entity>Module` 加進 `AppModule` 的 `imports`。

## 產出檔案(依序)

1. `<entity>/<entity>.response.ts`
2. `<entity>/<entity>.controller.ts`(+ `<entity>/<entity>.controller.e2e-spec.ts`,如有測試描述)
3. `<entity>/<entity>.module.ts`

`<Action>Command` 在 usecase 層產生(見 `references/usecase_layer.md`),`ZodValidationPipe`、`GlobalExceptionFilter` 是共用基礎設施(見 `references/architecture.md`),本層不重複產出。

## 模板

### Response `<entity>/<entity>.response.ts`

```typescript
import { BookingResult } from '../../../../usecase/booking/result/booking.result';

export class BookingResponse {
  constructor(
    readonly id: number,
    readonly field: Type,
    readonly status: string,
  ) {}

  static from(result: BookingResult): BookingResponse {
    return new BookingResponse(result.id, result.field, result.status);
  }
}
```

### 控制器 `<entity>/<entity>.controller.ts`

Controller 不 import `domain/` 底下的任何型別——它只認識 `<Action>Command`(從 usecase 層 import,不自己定義)、`<Entity>Result`(Usecase 的輸出,只在方法內部經手,不外流)、`<Entity>Response`(自己的輸出),完全看不到 Domain。每個 endpoint 對應一個獨立的 `<Action><Entity>UseCase` 介面,建構子注入時一個 endpoint 一個依賴,不共用一個大介面。Command 物件整個直接傳給 UseCase 方法,不在 Controller 拆欄位:

```typescript
import { Body, Controller, Get, Inject, Param, ParseIntPipe, Post, Put } from '@nestjs/common';
import { ZodValidationPipe } from '../pipes/zod-validation.pipe';
import { CreateBookingCommand, CreateBookingCommandSchema } from '../../../../usecase/booking/command/create-booking.command';
import { CONFIRM_BOOKING_USE_CASE, ConfirmBookingUseCase } from '../../../../usecase/booking/port/confirm-booking.usecase-port';
import { CREATE_BOOKING_USE_CASE, CreateBookingUseCase } from '../../../../usecase/booking/port/create-booking.usecase-port';
import { GET_BOOKING_USE_CASE, GetBookingUseCase } from '../../../../usecase/booking/port/get-booking.usecase-port';
import { BookingResponse } from './booking.response';

@Controller('api/bookings')
export class BookingController {
  constructor(
    @Inject(CREATE_BOOKING_USE_CASE) private readonly createBookingUseCase: CreateBookingUseCase,
    @Inject(CONFIRM_BOOKING_USE_CASE) private readonly confirmBookingUseCase: ConfirmBookingUseCase,
    @Inject(GET_BOOKING_USE_CASE) private readonly getBookingUseCase: GetBookingUseCase,
  ) {}

  // POST 建立 → 201(Nest 預設值,不需要 @HttpCode)
  @Post()
  async create(
    @Body(new ZodValidationPipe(CreateBookingCommandSchema)) command: CreateBookingCommand,
  ): Promise<BookingResponse> {
    const result = await this.createBookingUseCase.create(command);
    return BookingResponse.from(result);
  }

  // PUT 狀態變更 → 200(Nest 預設值)
  @Put(':id/confirm')
  async confirm(@Param('id', ParseIntPipe) id: number): Promise<BookingResponse> {
    const result = await this.confirmBookingUseCase.confirm(id);
    return BookingResponse.from(result);
  }

  // GET 查詢單筆 → 200
  @Get(':id')
  async getById(@Param('id', ParseIntPipe) id: number): Promise<BookingResponse> {
    const result = await this.getBookingUseCase.getById(id);
    return BookingResponse.from(result);
  }
}
```

### Module `<entity>/<entity>.module.ts`

這是這個 entity 的組裝根(composition root):註冊 TypeORM feature、把每個 Port token 繫結到實作 class。Nest 不像 Spring 有 classpath 掃描,所有繫結都要顯式寫在這裡:

```typescript
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BookingDataModel } from '../../../outbound/repository/datamodel/booking.data-model';
import { BookingRepositoryImpl } from '../../../outbound/repository/booking.repository-impl';
import { NestDomainEventPublisherAdapter } from '../../../outbound/event/nest-event-publisher.adapter';
import { DOMAIN_EVENT_PUBLISHER } from '../../../../usecase/event-publisher.port';
import { BOOKING_REPOSITORY } from '../../../../usecase/booking/port/booking.repository';
import { CREATE_BOOKING_USE_CASE } from '../../../../usecase/booking/port/create-booking.usecase-port';
import { CreateBookingUseCaseImpl } from '../../../../usecase/booking/create-booking.usecase';
import { CONFIRM_BOOKING_USE_CASE } from '../../../../usecase/booking/port/confirm-booking.usecase-port';
import { ConfirmBookingUseCaseImpl } from '../../../../usecase/booking/confirm-booking.usecase';
import { GET_BOOKING_USE_CASE } from '../../../../usecase/booking/port/get-booking.usecase-port';
import { GetBookingUseCaseImpl } from '../../../../usecase/booking/get-booking.usecase';
import { BookingController } from './booking.controller';

@Module({
  imports: [TypeOrmModule.forFeature([BookingDataModel])],
  controllers: [BookingController],
  providers: [
    { provide: BOOKING_REPOSITORY, useClass: BookingRepositoryImpl },
    { provide: DOMAIN_EVENT_PUBLISHER, useClass: NestDomainEventPublisherAdapter },
    { provide: CREATE_BOOKING_USE_CASE, useClass: CreateBookingUseCaseImpl },
    { provide: CONFIRM_BOOKING_USE_CASE, useClass: ConfirmBookingUseCaseImpl },
    { provide: GET_BOOKING_USE_CASE, useClass: GetBookingUseCaseImpl },
  ],
})
export class BookingModule {}
```

把 `BookingModule` 加進 `AppModule` 的 `imports`,並確認 `AppModule` 已經有 `TypeOrmModule.forRoot({...})`(真實資料庫連線)與 `EventEmitterModule.forRoot()`(`NestDomainEventPublisherAdapter` 依賴的事件匯流排)——這兩行只需要在整個專案存在一次,不是每個 entity 都要重複加。

全域錯誤處理與驗證 Pipe 的模板與產出時機見 `references/architecture.md` 的「共用基礎設施」章節——`GlobalExceptionFilter` 要在 `main.ts` 用 `app.useGlobalFilters(new GlobalExceptionFilter())` 註冊一次,不是每個 entity 各自的檔案,不要重複產生。

## Controller-level 整合測試(唯一的測試層,規格含測試描述時產生)

**測試走整合測試,不 mock Inbound Port,也不 mock Repository**:`<entity>.controller.e2e-spec.ts` 用 `@nestjs/testing` 的 `Test.createTestingModule` 組出一個真實的 `<Entity>Module`,資料庫用 [`testcontainers`](https://node.testcontainers.org/) 在測試啟動時起一個跟正式環境同一種 image 的真實容器(下面以 Postgres 為例,實際要起哪種 image 依專案技術決策而定,MySQL 就換 `@testcontainers/mysql`),`TypeOrmModule.forRoot` 接容器回傳的連線資訊——不用記憶體 SQLite 這種替代品,因為它在型別轉換、鎖、SQL 方言上都可能跟正式環境的 DB 不一致,測試綠燈救不了正式環境的問題。掛上 `GlobalExceptionFilter`,再用 `supertest` 對它發真實 HTTP request——目標是盡量測完整條路線(HTTP → Controller → UseCase → Repository → DB),不是只測 Controller 這一層的參數轉換。斷言不能只看 HTTP 回應,方便時再查一次資料庫(或用下一個 request 查詢)確認資料真的被寫成預期的樣子。若這個 use case 還依賴 Redis 等其他有狀態外部元件,一併用對應的 testcontainers 模組(如 `@testcontainers/redis`)起真實 container;只有沒有可信賴 image 的第三方 SaaS API(如 Stripe、Twilio)才用 `.overrideProvider(TOKEN).useValue(stub)` 蓋掉那一個 Outbound Port,其餘依賴一律真實。理由與兩層測試原則的完整說明見 `references/testing_principles.md`。

這是這個 skill 產生的**唯一**測試層級——usecase 層與 adapter-outbound 層不再各自產生獨立測試,詳見 `references/testing_principles.md`。

需要先安裝 `testcontainers` 與對應的 module 套件(如 `npm install -D testcontainers`),並確保執行環境有 Docker。

```typescript
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { TypeOrmModule } from '@nestjs/typeorm';
import { EventEmitterModule } from '@nestjs/event-emitter';
import { PostgreSqlContainer, StartedPostgreSqlContainer } from '@testcontainers/postgresql';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { GlobalExceptionFilter } from '../filters/global-exception.filter';
import { BookingDataModel } from '../../../outbound/repository/datamodel/booking.data-model';
import { BookingModule } from './booking.module';

describe('BookingController (e2e)', () => {
  let app: INestApplication;
  let container: StartedPostgreSqlContainer;

  beforeAll(async () => {
    container = await new PostgreSqlContainer('postgres:16-alpine').start();

    const moduleRef = await Test.createTestingModule({
      imports: [
        EventEmitterModule.forRoot(),
        TypeOrmModule.forRoot({
          type: 'postgres',
          host: container.getHost(),
          port: container.getPort(),
          username: container.getUsername(),
          password: container.getPassword(),
          database: container.getDatabase(),
          entities: [BookingDataModel],
          synchronize: true,
        }),
        BookingModule,
      ],
    }).compile();

    app = moduleRef.createNestApplication();
    app.useGlobalFilters(new GlobalExceptionFilter());
    await app.init();
  }, 60_000); // 起 container 需要較長的 timeout

  afterAll(async () => {
    await app.close();
    await container.stop();
  });

  it('POST /api/bookings creates a booking', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/bookings')
      .send({ field: 'value' })
      .expect(201);

    expect(response.body.status).toBe('PENDING');
  });

  it('PUT /api/bookings/:id/confirm confirms a booking and persists the new status', async () => {
    const created = await request(app.getHttpServer()).post('/api/bookings').send({ field: 'value' });

    const response = await request(app.getHttpServer())
      .put(`/api/bookings/${created.body.id}/confirm`)
      .expect(200);
    expect(response.body.status).toBe('CONFIRMED');

    // 不能只看回應——再查一次確認資料庫裡的狀態真的被更新
    const refetched = await request(app.getHttpServer()).get(`/api/bookings/${created.body.id}`);
    expect(refetched.body.status).toBe('CONFIRMED');
  });

  it('GET /api/bookings/:id returns 404 for a missing booking', async () => {
    await request(app.getHttpServer()).get('/api/bookings/999').expect(404);
  });

  it('POST /api/bookings returns 400 for an invalid command', async () => {
    await request(app.getHttpServer()).post('/api/bookings').send({}).expect(400);
  });
});
```
