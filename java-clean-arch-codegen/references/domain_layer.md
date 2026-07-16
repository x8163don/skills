# Domain 層 — 領域實體與核心業務

## 規則

1. 只 import `java.*`(`java.time`, `java.util` 等);維持純 POJO。
2. 業務邏輯寫在實體的行為方法內(充血模型);每條 Business Rule 對應一個方法。
3. 建構子中所有參考型別欄位以 `Objects.requireNonNull(<field>, "<field> cannot be null")` 保護。
4. 所有欄位提供 getter;不可變欄位標 `final`;僅在業務方法內變更狀態(不提供 setter)。
5. 狀態列舉 `<Entity>Status` 與實體定義在同一個 domain package。
6. 行為隨型別變化時,定義策略介面 `<Concept>` 與多個實作類別,以多型取代 if-else。
7. 唯讀值物件(如外部系統查回的資料)使用 `record`。
8. 業務規則違反時拋出標準例外:狀態轉移錯誤拋 `IllegalStateException`、參數不合法拋 `IllegalArgumentException`。

## 產出檔案(依序)

1. `<Entity>Status.java`(如有狀態欄位)
2. `<Concept>.java` + 各實作(如有策略介面)
3. `<Entity>.java`

## 模板

### 狀態列舉 `<Entity>Status.java`

```java
package <basePackage>.domain.<entity>;

public enum <Entity>Status {
    <VALUE_1>,
    <VALUE_2>,
    <VALUE_3>
}
```

### 核心實體 `<Entity>.java`

```java
package <basePackage>.domain.<entity>;

import java.util.Objects;

public class <Entity> {
    private final Long id;
    private final <Type> <immutableField>;
    private <Entity>Status status;          // 可變狀態欄位不加 final

    public <Entity>(Long id, <Type> <immutableField>, <Entity>Status status) {
        this.id = id;
        this.<immutableField> = Objects.requireNonNull(<immutableField>, "<immutableField> cannot be null");
        this.status = Objects.requireNonNull(status, "status cannot be null");
    }

    // 業務行為:每條 Business Rule 產生一個方法,狀態檢查失敗拋 IllegalStateException
    public void <businessMethod>() {
        if (this.status != <Entity>Status.<REQUIRED_STATE>) {
            throw new IllegalStateException("Only <REQUIRED_STATE> <entity> can <businessMethod>");
        }
        this.status = <Entity>Status.<NEXT_STATE>;
    }

    // 查詢型業務方法回傳 boolean,不變更狀態
    public boolean can<BusinessQuery>() {
        return this.status == <Entity>Status.<REQUIRED_STATE>;
    }

    public Long getId() { return id; }
    public <Type> get<ImmutableField>() { return <immutableField>; }
    public <Entity>Status getStatus() { return status; }
}
```

### 策略介面(行為隨型別變化時)

```java
package <basePackage>.domain.<entity>;

public interface <Concept> {
    <Concept>Type getType();
    <ReturnType> <behavior>();
}
```

各實作類別(如 `Free<Concept>` / `Standard<Concept>`)實作同一介面,差異行為封裝在各自的方法內。

### 唯讀值物件

```java
package <basePackage>.domain.<entity>;

public record <ValueObject>(
    <Type> <field1>,
    <Type> <field2>
) {}
```
