# Adapter 層 — 外部基礎設施整合

## 規則

1. JPA 註解(`@Entity`, `@Table`, `@Column`)只出現在 `<Entity>Entity.java`;Domain 類別保持零註解。
2. `<Entity>Entity` 使用 snake_case 資料表名(`@Table(name = "<entities>")`)與欄位名(`@Column(name = "<snake_case>")`);提供無參建構子 + 全欄位 getter/setter。
3. `<Entity>Mapper` 全部為 static 方法(`toDomain` / `toEntity`),不是 Spring bean、不被注入;兩個方法開頭皆做 null 檢查回傳 null。
4. `<Entity>RepositoryImpl` 標 `@Component`,實作 Usecase 的 `<Entity>Repository`(Outbound Port),內部委派 `<Entity>JpaRepository` 並經 Mapper 轉換。
5. 外部 SDK(Stripe、Redis 等)只在本層 import;SDK 例外在此層捕捉,轉為自訂例外(如 `PaymentGatewayException`,含 `(String message, Throwable cause)` 建構子)後上拋。
6. 外部服務實作標 `@Service`,命名為 `<Provider><Concept>ServiceImpl`;設定值以 `@Value("${...}")` 從建構子注入。
7. 事件發送使用 `SpringDomainEventPublisher`(`@Component`),以 Spring `ApplicationEventPublisher` 實作 Usecase 的 `DomainEventPublisher`。

## 產出檔案(依序)

1. `entity/<Entity>Entity.java`
2. `mapper/<Entity>Mapper.java`
3. `<Entity>JpaRepository.java`
4. `<Entity>RepositoryImpl.java`
5. `service/<Provider><Concept>ServiceImpl.java`(如有外部服務 Port)
6. `event/SpringDomainEventPublisher.java`(如有事件 Port)

## 模板

### JPA 實體 `<Entity>Entity.java`

```java
package <basePackage>.adapter.repository.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "<entities>")
public class <Entity>Entity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "<snake_case_field>", nullable = false)
    private <Type> <field>;

    @Column(name = "status", nullable = false)
    private String status;              // enum 一律以 String 儲存(name())

    public <Entity>Entity() {}

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
package <basePackage>.adapter.repository.mapper;

import <basePackage>.adapter.repository.entity.<Entity>Entity;
import <basePackage>.domain.<entity>.<Entity>;
import <basePackage>.domain.<entity>.<Entity>Status;

public class <Entity>Mapper {

    public static <Entity> toDomain(<Entity>Entity entity) {
        if (entity == null) return null;
        return new <Entity>(
            entity.getId(),
            entity.get<Field>(),
            <Entity>Status.valueOf(entity.getStatus())
        );
    }

    public static <Entity>Entity toEntity(<Entity> domain) {
        if (domain == null) return null;
        <Entity>Entity entity = new <Entity>Entity();
        entity.setId(domain.getId());
        entity.set<Field>(domain.get<Field>());
        entity.setStatus(domain.getStatus().name());
        return entity;
    }
}
```

### Spring Data JPA 介面 `<Entity>JpaRepository.java`

```java
package <basePackage>.adapter.repository;

import <basePackage>.adapter.repository.entity.<Entity>Entity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface <Entity>JpaRepository extends JpaRepository<<Entity>Entity, Long> {
    // 依 Outbound Port 的 getBy<Field> 需求宣告 findBy<Field> 方法
}
```

### Outbound Port 實作 `<Entity>RepositoryImpl.java`

```java
package <basePackage>.adapter.repository;

import <basePackage>.adapter.repository.entity.<Entity>Entity;
import <basePackage>.adapter.repository.mapper.<Entity>Mapper;
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
        <Entity>Entity saved = jpaRepository.save(<Entity>Mapper.toEntity(<entity>));
        return <Entity>Mapper.toDomain(saved);
    }
}
```

### 外部服務實作 `<Provider><Concept>ServiceImpl.java`

```java
package <basePackage>.adapter.service;

import <basePackage>.domain.<entity>.<Entity>;
import <basePackage>.usecase.<entity>.<Concept>Service;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class <Provider><Concept>ServiceImpl implements <Concept>Service {

    private final String <configField>;

    public <Provider><Concept>ServiceImpl(@Value("${<provider>.<config.key>}") String <configField>) {
        this.<configField> = <configField>;
    }

    @Override
    public <ReturnType> <serviceMethod>(<Entity> <entity>) {
        try {
            // 呼叫 <Provider> SDK
            return <sdkCallResult>;
        } catch (Exception e) {
            throw new <Concept>GatewayException("Failed to <serviceMethod> via <Provider>", e);
        }
    }
}
```

### 自訂例外 `<Concept>GatewayException.java`

```java
package <basePackage>.adapter.service;

public class <Concept>GatewayException extends RuntimeException {
    public <Concept>GatewayException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

### 事件發送器 `SpringDomainEventPublisher.java`

```java
package <basePackage>.adapter.event;

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
