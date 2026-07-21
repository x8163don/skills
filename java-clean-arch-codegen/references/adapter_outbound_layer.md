# Adapter/Outbound 層 — 外部基礎設施整合(Interface Adapters,驅動內層依賴的一側)

## 規則

1. JPA 註解(`@Entity`, `@Table`, `@Column`)只出現在 `<Entity>DataModel.java`;Domain 類別保持零註解。命名一律叫 `<Entity>DataModel`,不叫 `<Entity>Entity`——避免跟 Domain 的 `<Entity>` 混淆。
2. `<Entity>DataModel` 使用 snake_case 資料表名(`@Table(name = "<entities>")`)與欄位名(`@Column(name = "<snake_case>")`);提供無參建構子 + 全欄位 getter/setter。
3. `<Entity>Mapper` 全部為 static 方法(`toDomain` / `toDataModel`),不是 Spring bean、不被注入;兩個方法開頭皆做 null 檢查回傳 null。
4. `<Entity>RepositoryImpl` 標 `@Component`,實作 Usecase 的 `<Entity>Repository`(Outbound Port),內部委派 `<Entity>JpaRepository` 並經 Mapper 轉換。
5. 外部 SDK(Stripe、Kafka、Redis 等)只在對應的 `adapter/outbound/<category>` 子目錄 import;SDK 例外在此層捕捉,轉為自訂例外(如 `PaymentClientException`,含 `(String message, Throwable cause)` 建構子)後上拋。
6. 除 Repository 外的外部依賴一律標 `@Component`(不用 `@Service`,避免跟 domain/usecase 混淆),命名為 `<Provider><Concept>Adapter`(不用 `*ServiceImpl`/`*Impl`);設定值以 `@Value("${...}")` 從建構子注入。
7. 依外部依賴的性質分類到對應子目錄,Outbound Port 與 Adapter 命名對照:

   | 子目錄 | Outbound Port(usecase 層介面) | Adapter 實作 | 例外命名 | 範例 |
   |---|---|---|---|---|
   | `client/` | `<Concept>Client` | `<Provider><Concept>Adapter` | `<Concept>ClientException` | `PaymentClient` → `StripePaymentAdapter` |
   | `messaging/` | `<Concept>MessagePublisher` | `<Provider><Concept>Adapter` | `<Concept>MessagingException` | `OrderMessagePublisher` → `KafkaOrderAdapter` |
   | `cache/` | `<Concept>CacheStore` | `<Provider><Concept>Adapter` | `<Concept>CacheException` | `BookingCacheStore` → `RedisBookingAdapter` |
   | `notification/` | `<Concept>NotificationSender` | `<Provider><Concept>Adapter` | `<Concept>NotificationException` | `SmsNotificationSender` → `TwilioSmsAdapter` |
   | `storage/` | `<Concept>FileStorage` | `<Provider><Concept>Adapter` | `<Concept>StorageException` | `AttachmentFileStorage` → `S3AttachmentAdapter` |

   五類結構完全相同(見下方模板),只有子目錄、Port 介面名稱、例外名稱不同。
8. 事件發送使用 `SpringDomainEventPublisher`(`@Component`),以 Spring `ApplicationEventPublisher` 實作 Usecase 的 `DomainEventPublisher`;這是 in-process 的 domain event,跟 `messaging/`(對外部訊息佇列發送)是不同用途,不可混用。

## 產出檔案(依序)

1. `datamodel/<Entity>DataModel.java`
2. `mapper/<Entity>Mapper.java`
3. `<Entity>JpaRepository.java`
4. `<Entity>RepositoryImpl.java`
5. `<category>/<Provider><Concept>Adapter.java`(如有 Client/Messaging/Cache/Notification/Storage Port,`<category>` 依規則 7 的分類表擇一)
6. `event/SpringDomainEventPublisher.java`(如有事件 Port)

## 模板

### JPA DataModel `<Entity>DataModel.java`

```java
package <basePackage>.adapter.outbound.repository.datamodel;

import jakarta.persistence.*;

@Entity
@Table(name = "<entities>")
public class <Entity>DataModel {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "<snake_case_field>", nullable = false)
    private <Type> <field>;

    @Column(name = "status", nullable = false)
    private String status;              // enum 一律以 String 儲存(name())

    public <Entity>DataModel() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public <Type> get<Field>() { return <field>; }
    public void set<Field>(<Type> <field>) { this.<field> = <field>; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
}
```

### 對映器 `<Entity>Mapper.java`

```java
package <basePackage>.adapter.outbound.repository.mapper;

import <basePackage>.adapter.outbound.repository.datamodel.<Entity>DataModel;
import <basePackage>.domain.<entity>.<Entity>;
import <basePackage>.domain.<entity>.<Entity>Status;

public class <Entity>Mapper {

    public static <Entity> toDomain(<Entity>DataModel dataModel) {
        if (dataModel == null) return null;
        return new <Entity>(
            dataModel.getId(),
            dataModel.get<Field>(),
            <Entity>Status.valueOf(dataModel.getStatus())
        );
    }

    public static <Entity>DataModel toDataModel(<Entity> domain) {
        if (domain == null) return null;
        <Entity>DataModel dataModel = new <Entity>DataModel();
        dataModel.setId(domain.getId());
        dataModel.set<Field>(domain.get<Field>());
        dataModel.setStatus(domain.getStatus().name());
        return dataModel;
    }
}
```

### Spring Data JPA 介面 `<Entity>JpaRepository.java`

```java
package <basePackage>.adapter.outbound.repository;

import <basePackage>.adapter.outbound.repository.datamodel.<Entity>DataModel;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface <Entity>JpaRepository extends JpaRepository<<Entity>DataModel, Long> {
    // 依 Outbound Port 的 getBy<Field> 需求宣告 findBy<Field> 方法
}
```

### Outbound Port 實作 `<Entity>RepositoryImpl.java`

```java
package <basePackage>.adapter.outbound.repository;

import <basePackage>.adapter.outbound.repository.datamodel.<Entity>DataModel;
import <basePackage>.adapter.outbound.repository.mapper.<Entity>Mapper;
import <basePackage>.domain.<entity>.<Entity>;
import <basePackage>.usecase.<entity>.<Entity>Repository;
import org.springframework.stereotype.Component;

import java.util.Optional;

@Component
public class <Entity>RepositoryImpl implements <Entity>Repository {

    private final <Entity>JpaRepository jpaRepository;

    public <Entity>RepositoryImpl(<Entity>JpaRepository jpaRepository) {
        this.jpaRepository = jpaRepository;
    }

    @Override
    public Optional<<Entity>> getById(Long id) {
        return jpaRepository.findById(id).map(<Entity>Mapper::toDomain);
    }

    @Override
    public <Entity> save(<Entity> <entity>) {
        <Entity>DataModel saved = jpaRepository.save(<Entity>Mapper.toDataModel(<entity>));
        return <Entity>Mapper.toDomain(saved);
    }
}
```

### 外部依賴 Adapter `<Provider><Concept>Adapter.java`

以 `client/` 為例(`messaging/`、`cache/`、`notification/`、`storage/` 套用同一個模板,只換子目錄、Port 介面、例外類別名稱):

```java
package <basePackage>.adapter.outbound.client;

import <basePackage>.domain.<entity>.<Entity>;
import <basePackage>.usecase.<entity>.<Concept>Client;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class <Provider><Concept>Adapter implements <Concept>Client {

    private final String <configField>;

    public <Provider><Concept>Adapter(@Value("${<provider>.<config.key>}") String <configField>) {
        this.<configField> = <configField>;
    }

    @Override
    public <ReturnType> <clientMethod>(<Entity> <entity>) {
        try {
            // 呼叫 <Provider> SDK
            return <sdkCallResult>;
        } catch (Exception e) {
            throw new <Concept>ClientException("Failed to <clientMethod> via <Provider>", e);
        }
    }
}
```

### 自訂例外 `<Concept>ClientException.java`

```java
package <basePackage>.adapter.outbound.client;

public class <Concept>ClientException extends RuntimeException {
    public <Concept>ClientException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

### 事件發送器 `SpringDomainEventPublisher.java`

```java
package <basePackage>.adapter.outbound.event;

import <basePackage>.usecase.<entity>.DomainEventPublisher;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

@Component
public class SpringDomainEventPublisher implements DomainEventPublisher {

    private final ApplicationEventPublisher applicationEventPublisher;

    public SpringDomainEventPublisher(ApplicationEventPublisher applicationEventPublisher) {
        this.applicationEventPublisher = applicationEventPublisher;
    }

    @Override
    public void publish(Object event) {
        if (event != null) {
            applicationEventPublisher.publishEvent(event);
        }
    }
}
```
