# Usecase 層 — 業務案例與介面合約

## 規則

1. 只 import Domain 類別與本層(usecase)類別;`@Transactional` 是本層唯一允許的 Spring import。
2. 先定義 Outbound Ports(Repository、Client/Messaging/Cache/Notification/Storage 等外部依賴、事件發送)為介面,再定義 Inbound Port,最後實作對應的 UseCaseImpl。**每個 use case 情境(每條 Business Rule 或每個查詢需求)各自一個 Inbound Port 介面 + 一個 Impl,不共用一個大介面**:介面命名 `<Action><Entity>UseCase`(如 `CreateBookingUseCase`、`ConfirmBookingUseCase`、`GetBookingUseCase`),各自只宣告一個方法;Impl 命名 `<Action><Entity>UseCaseImpl`,只依賴自己需要的 Outbound Port,不共用一個大 Impl。
3. 所有依賴透過建構子注入;實作類別為無狀態單例。
4. 每個寫入方法(呼叫 `save()` 或變更狀態)標 `@Transactional`(`org.springframework.transaction.annotation.Transactional`);純查詢方法(不呼叫 `save()`)標 `@Transactional(readOnly = true)`。
5. 查詢單筆一律 `repository.getById(id).orElseThrow(() -> new <Entity>NotFoundException(...))`。
6. 領域事件在 `save()` 成功之後 publish;事件用 `record` 定義在 `usecase.<entity>.event` package。
7. 領域例外 `<Entity>NotFoundException` 定義在本層、繼承 `RuntimeException`、提供 `(String message)` 建構子。
8. Repository Port 的標準方法簽名:`Optional<<Entity>> getById(Long id)`、`<Entity> save(<Entity> <entity>)`,查詢條件方法命名為 `getBy<Field>`。
9. **Inbound Port 的方法一律回傳 `<Entity>Result` 家族型別,不直接回傳 Domain `<Entity>`**:Domain 物件(及其業務方法)只能在 Usecase 內部與 Repository 之間流動,絕不可流出 Usecase 邊界。UseCaseImpl 內部正常操作 Domain(呼叫業務方法、`save()`),方法回傳前才用 `<Entity>Result.from(domain)` 轉換。Result 用 `record` 定義,無業務方法,命名依用途:
   - 預設(單筆查詢/寫入後回傳完整資料):`<Entity>Result`
   - 列表查詢、欄位精簡:`<Entity>SummaryResult`
   - 特定 use case 需要客製欄位(如包含關聯資料):依實際需求命名,不勉強套單一模板
10. **`usecase/<entity>/` 目錄下只放 `<Action><Entity>UseCaseImpl.java`(每個 use case 情境一個檔案)**,其餘依類型分子目錄,點進去就能一眼看到這個 entity 有哪些 use case、各自的設計內容而不必打開實作:
    - `port/`:所有介面——每個 use case 的 Inbound Port(`<Action><Entity>UseCase`)與全部 Outbound Port(`<Entity>Repository`、`<Concept>Client` 等、`DomainEventPublisher`)
    - `result/`:`<Entity>Result` 家族(Usecase 輸出型別)
    - `command/`:`<Action>Command` 家族(Usecase 輸入型別,規則 11)
    - `exception/`:`<Entity>NotFoundException`
    - `event/`:領域事件(既有規則,不變)
11. **寫入型 endpoint 的輸入型別 `<Action>Command` 定義在本層**(`usecase.<entity>.command`),不在 Adapter/Inbound:跟 Result 對稱,同樣是 Usecase 自己擁有的邊界資料結構,用 `jakarta.validation` 註解(`@NotNull` 等)驗證欄位;`<Action>Command` 是本層唯一允許 import `jakarta.validation` 的類別。Inbound Port 方法直接以 `<Action>Command` 為參數(不拆欄位傳原始型別),Adapter 層的 Controller 直接 import 這個 Command 使用,不自己另外定義一份。單一 ID 這種簡單查詢/狀態變更(如 `confirm(Long id)`、`getById(Long id)`)不需要包 Command,直接傳 `Long` 即可。

## 產出檔案(依序)

1. `port/<Entity>Repository.java`(Outbound Port)
2. `port/<Concept>Client.java` / `port/<Concept>MessagePublisher.java` / `port/<Concept>CacheStore.java` / `port/<Concept>NotificationSender.java` / `port/<Concept>FileStorage.java`(Outbound Port,依外部依賴性質擇一,如有)
3. `port/DomainEventPublisher.java`(Outbound Port,如有事件)
4. `event/<Entity><Action>Event.java`(如有事件)
5. `exception/<Entity>NotFoundException.java`
6. `result/<Entity>Result.java`(+ 其他 Result 變體,如 `result/<Entity>SummaryResult.java`,依規則 9 擇一或並存)
7. `command/<Action>Command.java`(每個需要 request body 的 use case 一個,依規則 11)
8. 對每個 use case 情境重複:`port/<Action><Entity>UseCase.java`(Inbound Port)+ `<Action><Entity>UseCaseImpl.java`(直接放在 `usecase/<entity>/` 目錄下)

## 模板

### Outbound Port — Repository

```java
package <basePackage>.usecase.<entity>.port;

import <basePackage>.domain.<entity>.<Entity>;
import java.util.Optional;

public interface <Entity>Repository {
    Optional<<Entity>> getById(Long id);
    <Entity> save(<Entity> <entity>);
}
```

### Outbound Port — 外部依賴(Client / Messaging / Cache / Notification / Storage)

依外部依賴的性質選擇介面命名(見 `references/adapter_outbound_layer.md` 的分類表),方法簽名皆相同模式,以 Client(呼叫外部 API/SDK)為例:

```java
package <basePackage>.usecase.<entity>.port;

import <basePackage>.domain.<entity>.<Entity>;

public interface <Concept>Client {
    <ReturnType> <clientMethod>(<Entity> <entity>);
}
```

其餘分類介面命名同樣模式:`<Concept>MessagePublisher`(訊息佇列)、`<Concept>CacheStore`(快取)、`<Concept>NotificationSender`(通知)、`<Concept>FileStorage`(檔案儲存),package 皆為 `usecase.<entity>.port`。

### Outbound Port — 事件發送

```java
package <basePackage>.usecase.<entity>.port;

public interface DomainEventPublisher {
    void publish(Object event);
}
```

### 領域事件

```java
package <basePackage>.usecase.<entity>.event;

public record <Entity><Action>Event(
    Long <entity>Id,
    <Type> <payloadField>
) {}
```

### 領域例外

```java
package <basePackage>.usecase.<entity>.exception;

public class <Entity>NotFoundException extends RuntimeException {
    public <Entity>NotFoundException(String message) {
        super(message);
    }
}
```

### Result(Usecase 輸出型別,取代直接回傳 Domain)

```java
package <basePackage>.usecase.<entity>.result;

import <basePackage>.domain.<entity>.<Entity>;

public record <Entity>Result(Long id, <Type> <field>, String status) {
    public static <Entity>Result from(<Entity> <entity>) {
        return new <Entity>Result(
            <entity>.getId(),
            <entity>.get<Field>(),
            <entity>.getStatus().name()
        );
    }
}
```

列表查詢用的精簡變體(欄位依實際需求增減):

```java
package <basePackage>.usecase.<entity>.result;

import <basePackage>.domain.<entity>.<Entity>;

public record <Entity>SummaryResult(Long id, String status) {
    public static <Entity>SummaryResult from(<Entity> <entity>) {
        return new <Entity>SummaryResult(<entity>.getId(), <entity>.getStatus().name());
    }
}
```

### Command(Usecase 輸入型別,與 Result 對稱)

跟 Result 一樣用 `record` 定義,無業務方法;欄位驗證直接標在這裡:

```java
package <basePackage>.usecase.<entity>.command;

import jakarta.validation.constraints.NotNull;

public record <Action>Command(
    @NotNull(message = "<field> must not be null") <Type> <field>
) {}
```

### Inbound Port(每個 use case 情境一個檔案)

每個介面只宣告**一個方法**,不 import Domain `<Entity>`——方法簽名只暴露 Result(和需要時的 Command),呼叫方(Controller)因此也不需要認識 Domain。以帶 request body 的寫入型(`Create<Entity>UseCase`)、只靠路徑參數的寫入型(`ConfirmBookingUseCase` 風格)、查詢型(`GetBookingUseCase`)各一個為例:

```java
package <basePackage>.usecase.<entity>.port;

import <basePackage>.usecase.<entity>.command.<Action>Command;
import <basePackage>.usecase.<entity>.result.<Entity>Result;

public interface Create<Entity>UseCase {
    <Entity>Result create(<Action>Command command);
}
```

```java
package <basePackage>.usecase.<entity>.port;

import <basePackage>.usecase.<entity>.result.<Entity>Result;

public interface <Action><Entity>UseCase {
    <Entity>Result <useCaseMethod>(Long <entity>Id);
}
```

```java
package <basePackage>.usecase.<entity>.port;

import <basePackage>.usecase.<entity>.result.<Entity>Result;

public interface Get<Entity>UseCase {
    <Entity>Result getById(Long <entity>Id);
}
```

### UseCase 實作(每個 use case 情境一個檔案,直接放在 `usecase/<entity>/` 目錄下)

帶 Command 的寫入型 Impl:Command 是 `record`,用 accessor(`command.<field>()`)取值,不是 `getX()`:

```java
package <basePackage>.usecase.<entity>;

import <basePackage>.domain.<entity>.<Entity>;
import <basePackage>.domain.<entity>.<Entity>Status;
import <basePackage>.usecase.<entity>.command.<Action>Command;
import <basePackage>.usecase.<entity>.port.Create<Entity>UseCase;
import <basePackage>.usecase.<entity>.port.<Entity>Repository;
import <basePackage>.usecase.<entity>.result.<Entity>Result;
import org.springframework.transaction.annotation.Transactional;

public class Create<Entity>UseCaseImpl implements Create<Entity>UseCase {

    private final <Entity>Repository <entity>Repository;

    public Create<Entity>UseCaseImpl(<Entity>Repository <entity>Repository) {
        this.<entity>Repository = <entity>Repository;
    }

    @Override
    @Transactional
    public <Entity>Result create(<Action>Command command) {
        <Entity> <entity> = new <Entity>(null, command.<field>(), <Entity>Status.<INITIAL_STATE>);
        <Entity> saved = <entity>Repository.save(<entity>);
        return <Entity>Result.from(saved);
    }
}
```

只靠路徑參數、不需要 Command 的寫入型 Impl,只依賴自己需要的 Outbound Port(不強塞其他 use case 用不到的依賴):

```java
package <basePackage>.usecase.<entity>;

import <basePackage>.domain.<entity>.<Entity>;
import <basePackage>.usecase.<entity>.port.<Action><Entity>UseCase;
import <basePackage>.usecase.<entity>.port.<Entity>Repository;
import <basePackage>.usecase.<entity>.port.DomainEventPublisher;
import <basePackage>.usecase.<entity>.result.<Entity>Result;
import <basePackage>.usecase.<entity>.exception.<Entity>NotFoundException;
import <basePackage>.usecase.<entity>.event.<Entity><Action>Event;
import org.springframework.transaction.annotation.Transactional;

public class <Action><Entity>UseCaseImpl implements <Action><Entity>UseCase {

    private final <Entity>Repository <entity>Repository;
    private final DomainEventPublisher eventPublisher;

    public <Action><Entity>UseCaseImpl(
            <Entity>Repository <entity>Repository,
            DomainEventPublisher eventPublisher) {
        this.<entity>Repository = <entity>Repository;
        this.eventPublisher = eventPublisher;
    }

    @Override
    @Transactional
    public <Entity>Result <useCaseMethod>(Long <entity>Id) {
        <Entity> <entity> = <entity>Repository.getById(<entity>Id)
                .orElseThrow(() -> new <Entity>NotFoundException("<Entity> not found for ID: " + <entity>Id));

        <entity>.<businessMethod>();                       // 1. 呼叫 Domain 業務方法
        <Entity> saved = <entity>Repository.save(<entity>); // 2. 持久化

        // 3. 保存成功後發送領域事件
        eventPublisher.publish(new <Entity><Action>Event(saved.getId(), saved.get<PayloadField>()));

        // 4. Domain 到此為止,轉成 Result 才回傳給外層(Adapter 不可見 Domain)
        return <Entity>Result.from(saved);
    }
}
```

查詢型 Impl:不呼叫 `save()`、不 publish 事件、不需要 `DomainEventPublisher` 依賴,標 `@Transactional(readOnly = true)`:

```java
package <basePackage>.usecase.<entity>;

import <basePackage>.domain.<entity>.<Entity>;
import <basePackage>.usecase.<entity>.port.Get<Entity>UseCase;
import <basePackage>.usecase.<entity>.port.<Entity>Repository;
import <basePackage>.usecase.<entity>.result.<Entity>Result;
import <basePackage>.usecase.<entity>.exception.<Entity>NotFoundException;
import org.springframework.transaction.annotation.Transactional;

public class Get<Entity>UseCaseImpl implements Get<Entity>UseCase {

    private final <Entity>Repository <entity>Repository;

    public Get<Entity>UseCaseImpl(<Entity>Repository <entity>Repository) {
        this.<entity>Repository = <entity>Repository;
    }

    @Override
    @Transactional(readOnly = true)
    public <Entity>Result getById(Long <entity>Id) {
        <Entity> <entity> = <entity>Repository.getById(<entity>Id)
                .orElseThrow(() -> new <Entity>NotFoundException("<Entity> not found for ID: " + <entity>Id));
        return <Entity>Result.from(<entity>);
    }
}
```

## 單元測試模板(TDD 時先產)

一個 use case 一個測試類別,命名 `<Action><Entity>UseCaseImplTest`,只 `@Mock` 這個 use case 真正用到的 Outbound Port:

```java
package <basePackage>.usecase.<entity>;

import <basePackage>.domain.<entity>.*;
import <basePackage>.usecase.<entity>.port.<Entity>Repository;
import <basePackage>.usecase.<entity>.port.DomainEventPublisher;
import <basePackage>.usecase.<entity>.result.<Entity>Result;
import <basePackage>.usecase.<entity>.exception.<Entity>NotFoundException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class <Action><Entity>UseCaseImplTest {

    @Mock
    private <Entity>Repository <entity>Repository;

    @Mock
    private DomainEventPublisher eventPublisher;

    @InjectMocks
    private <Action><Entity>UseCaseImpl <entity>UseCase;

    @Test
    void <useCaseMethod>_success() {
        <Entity> <entity> = new <Entity>(1L, <args>);
        when(<entity>Repository.getById(1L)).thenReturn(Optional.of(<entity>));
        when(<entity>Repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        <Entity>Result result = <entity>UseCase.<useCaseMethod>(1L);

        assertEquals(<expected>, result.<field>());   // record accessor,不是 get<Field>()
        verify(eventPublisher).publish(any());
    }

    @Test
    void <useCaseMethod>_notFound_throws() {
        when(<entity>Repository.getById(99L)).thenReturn(Optional.empty());

        assertThrows(<Entity>NotFoundException.class, () -> <entity>UseCase.<useCaseMethod>(99L));
    }
}
```
