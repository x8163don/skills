# Adapter/Inbound 層 — 通訊與應用進入點(Interface Adapters,被外部驅動的一側)

## 規則

1. Spring MVC 註解(`@RestController`, `@RequestMapping` 等)只出現在本層。
2. Controller 方法固定三步:解析參數 → 呼叫 UseCase(Inbound Port)→ 包裝 Response 回傳;方法內零業務判斷。
3. Controller 依賴 UseCase 介面(不是 Impl),建構子注入;每個 use case 情境是獨立的窄介面(`<Action><Entity>UseCase`),Controller 有幾個 endpoint 就注入幾個對應的 UseCase 介面,不共用一個大介面。
4. `<Action>Command` 定義在 **usecase 層**(`usecase.<entity>.command`,見 `references/usecase_layer.md`),不在本層;Controller 直接 import 使用,不自己另外定義一份,方法參數標 `@Valid @RequestBody <Action>Command`。
5. Response 包裝 Usecase 回傳的 `<Entity>Result`(不是 Domain 物件);提供 static factory `from(<Entity>Result)`;Domain 物件與其業務方法不可流出 Usecase 邊界,本層一律不 import `domain` package;不叫 `Dto`,一律叫 `<Entity>Response`。
6. 回傳型別一律 `ResponseEntity<T>`:建立回 `201`、查詢/更新回 `200`、刪除回 `204`。
7. `GlobalExceptionHandler` 標 `@RestControllerAdvice`,固定處理四類:`<Entity>NotFoundException` → 404、`MethodArgumentNotValidException` → 400、`IllegalArgumentException` / `IllegalStateException` → 400、`Exception` → 500;錯誤回應格式固定為 `{"error": "<message>"}`。
8. URL 命名:`/api/<entities>`(複數、kebab-case);路徑參數標 `@PathVariable("<name>")`。

## 產出檔案(依序)

1. `<Entity>Response.java`
2. `<Entity>Controller.java`
3. `exception/GlobalExceptionHandler.java`

`<Action>Command.java` 在 usecase 層產生(見 `references/usecase_layer.md`),本層不重複產出。

## 模板

### Response `<Entity>Response.java`

```java
package <basePackage>.adapter.inbound.web.<entity>;

import <basePackage>.usecase.<entity>.result.<Entity>Result;

public class <Entity>Response {

    private final Long id;
    private final <Type> <field>;
    private final String status;

    private <Entity>Response(Long id, <Type> <field>, String status) {
        this.id = id;
        this.<field> = <field>;
        this.status = status;
    }

    public static <Entity>Response from(<Entity>Result result) {
        return new <Entity>Response(
            result.id(),
            result.<field>(),
            result.status()
        );
    }

    public Long getId() { return id; }
    public <Type> get<Field>() { return <field>; }
    public String getStatus() { return status; }
}
```

### 控制器 `<Entity>Controller.java`

Controller 不 import `domain` package——它只認識 `<Action>Command`(從 usecase 層 import,不自己定義)、`<Entity>Result`(Usecase 的輸出)、`<Entity>Response`(自己的輸出),完全看不到 Domain。每個 endpoint 對應一個獨立的 `<Action><Entity>UseCase` 介面,建構子注入時一個 endpoint 一個依賴,不共用一個大介面。Command 物件整個直接傳給 UseCase 方法,不在 Controller 拆欄位:

```java
package <basePackage>.adapter.inbound.web.<entity>;

import <basePackage>.usecase.<entity>.command.<Action>Command;
import <basePackage>.usecase.<entity>.result.<Entity>Result;
import <basePackage>.usecase.<entity>.port.Create<Entity>UseCase;
import <basePackage>.usecase.<entity>.port.<Action><Entity>UseCase;
import <basePackage>.usecase.<entity>.port.Get<Entity>UseCase;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/<entities>")
public class <Entity>Controller {

    private final Create<Entity>UseCase create<Entity>UseCase;
    private final <Action><Entity>UseCase <action><Entity>UseCase;
    private final Get<Entity>UseCase get<Entity>UseCase;

    public <Entity>Controller(
            Create<Entity>UseCase create<Entity>UseCase,
            <Action><Entity>UseCase <action><Entity>UseCase,
            Get<Entity>UseCase get<Entity>UseCase) {
        this.create<Entity>UseCase = create<Entity>UseCase;
        this.<action><Entity>UseCase = <action><Entity>UseCase;
        this.get<Entity>UseCase = get<Entity>UseCase;
    }

    // POST 建立 → 201
    @PostMapping
    public ResponseEntity<<Entity>Response> create(@Valid @RequestBody <Action>Command command) {
        <Entity>Result result = create<Entity>UseCase.create(command);
        return ResponseEntity.status(HttpStatus.CREATED).body(<Entity>Response.from(result));
    }

    // PUT 狀態變更 → 200
    @PutMapping("/{id}/<action>")
    public ResponseEntity<<Entity>Response> <action>(@PathVariable("id") Long id) {
        <Entity>Result result = <action><Entity>UseCase.<useCaseMethod>(id);
        return ResponseEntity.ok(<Entity>Response.from(result));
    }

    // GET 查詢單筆 → 200
    @GetMapping("/{id}")
    public ResponseEntity<<Entity>Response> getById(@PathVariable("id") Long id) {
        <Entity>Result result = get<Entity>UseCase.getById(id);
        return ResponseEntity.ok(<Entity>Response.from(result));
    }
}
```

### 全域例外處理器 `GlobalExceptionHandler.java`

```java
package <basePackage>.adapter.inbound.web.exception;

import <basePackage>.usecase.<entity>.exception.<Entity>NotFoundException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(<Entity>NotFoundException.class)
    public ResponseEntity<Map<String, String>> handleNotFound(<Entity>NotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("error", ex.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, String>> handleValidation(MethodArgumentNotValidException ex) {
        String message = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> e.getField() + ": " + e.getDefaultMessage())
                .findFirst()
                .orElse("Validation failed");
        return ResponseEntity.badRequest().body(Map.of("error", message));
    }

    @ExceptionHandler({IllegalArgumentException.class, IllegalStateException.class})
    public ResponseEntity<Map<String, String>> handleBadRequest(RuntimeException ex) {
        return ResponseEntity.badRequest().body(Map.of("error", ex.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, String>> handleGeneral(Exception ex) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Internal server error"));
    }
}
```
