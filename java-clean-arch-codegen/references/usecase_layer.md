# Usecase 層 — 業務案例與介面合約

## 規則

1. 只 import Domain 類別與本層(usecase)類別;`@Transactional` 是本層唯一允許的 Spring import。
2. 先定義 Outbound Ports(Repository、Client/Messaging/Cache/Notification/Storage 等外部依賴、事件發送)為介面,再定義 Inbound Port(`<Entity>UseCase`),最後實作 `<Entity>UseCaseImpl`。
3. 所有依賴透過建構子注入;實作類別為無狀態單例。
4. 每個寫入方法(呼叫 `save()` 或變更狀態)標 `@Transactional`(`org.springframework.transaction.annotation.Transactional`)。
5. 查詢單筆一律 `repository.getById(id).orElseThrow(() -> new <Entity>NotFoundException(...))`。
6. 領域事件在 `save()` 成功之後 publish;事件用 `record` 定義在 `usecase.<entity>.event` package。
7. 領域例外 `<Entity>NotFoundException` 定義在本層、繼承 `RuntimeException`、提供 `(String message)` 建構子。
8. Repository Port 的標準方法簽名:`Optional<<Entity>> getById(Long id)`、`<Entity> save(<Entity> <entity>)`,查詢條件方法命名為 `getBy<Field>`。

## 產出檔案(依序)

1. `<Entity>Repository.java`(Outbound Port)
2. `<Concept>Client.java` / `<Concept>MessagePublisher.java` / `<Concept>CacheStore.java` / `<Concept>NotificationSender.java` / `<Concept>FileStorage.java`(Outbound Port,依外部依賴性質擇一,如有)
3. `DomainEventPublisher.java`(Outbound Port,如有事件)
4. `event/<Entity><Action>Event.java`(如有事件)
5. `<Entity>NotFoundException.java`
6. `<Entity>UseCase.java`(Inbound Port)
7. `<Entity>UseCaseImpl.java`

## 模板

### Outbound Port — Repository

```java
package <basePackage>.usecase.<entity>;

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
package <basePackage>.usecase.<entity>;

import <basePackage>.domain.<entity>.<Entity>;

public interface <Concept>Client {
    <ReturnType> <clientMethod>(<Entity> <entity>);
}
```

其餘分類介面命名同樣模式:`<Concept>MessagePublisher`(訊息佇列)、`<Concept>CacheStore`(快取)、`<Concept>NotificationSender`(通知)、`<Concept>FileStorage`(檔案儲存)。

### Outbound Port — 事件發送

```java
package <basePackage>.usecase.<entity>;

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
package <basePackage>.usecase.<entity>;

public class <Entity>NotFoundException extends RuntimeException {
    public <Entity>NotFoundException(String message) {
        super(message);
    }
}
```

### Inbound Port

```java
package <basePackage>.usecase.<entity>;

import <basePackage>.domain.<entity>.<Entity>;

public interface <Entity>UseCase {
    <Entity> <useCaseMethod>(Long <entity>Id);
}
```

### UseCase 實作

```java
package <basePackage>.usecase.<entity>;

import <basePackage>.domain.<entity>.<Entity>;
import <basePackage>.usecase.<entity>.event.<Entity><Action>Event;
import org.springframework.transaction.annotation.Transactional;

public class <Entity>UseCaseImpl implements <Entity>UseCase {

    private final <Entity>Repository <entity>Repository;
    private final DomainEventPublisher eventPublisher;

    public <Entity>UseCaseImpl(
            <Entity>Repository <entity>Repository,
            DomainEventPublisher eventPublisher) {
        this.<entity>Repository = <entity>Repository;
        this.eventPublisher = eventPublisher;
    }

    @Override
    @Transactional
    public <Entity> <useCaseMethod>(Long <entity>Id) {
        <Entity> <entity> = <entity>Repository.getById(<entity>Id)
                .orElseThrow(() -> new <Entity>NotFoundException("<Entity> not found for ID: " + <entity>Id));

        <entity>.<businessMethod>();                       // 1. 呼叫 Domain 業務方法
        <Entity> saved = <entity>Repository.save(<entity>); // 2. 持久化

        // 3. 保存成功後發送領域事件
        eventPublisher.publish(new <Entity><Action>Event(saved.getId(), saved.get<PayloadField>()));

        return saved;
    }
}
```

## 單元測試模板(TDD 時先產)

```java
package <basePackage>.usecase.<entity>;

import <basePackage>.domain.<entity>.*;
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
class <Entity>UseCaseImplTest {

    @Mock
    private <Entity>Repository <entity>Repository;

    @Mock
    private DomainEventPublisher eventPublisher;

    @InjectMocks
    private <Entity>UseCaseImpl <entity>UseCase;

    @Test
    void <useCaseMethod>_success() {
        <Entity> <entity> = new <Entity>(1L, <args>);
        when(<entity>Repository.getById(1L)).thenReturn(Optional.of(<entity>));
        when(<entity>Repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        <Entity> result = <entity>UseCase.<useCaseMethod>(1L);

        assertEquals(<expected>, result.get<Field>());
        verify(eventPublisher).publish(any());
    }

    @Test
    void <useCaseMethod>_notFound_throws() {
        when(<entity>Repository.getById(99L)).thenReturn(Optional.empty());

        assertThrows(<Entity>NotFoundException.class, () -> <entity>UseCase.<useCaseMethod>(99L));
    }
}
```
