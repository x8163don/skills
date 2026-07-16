# Application 層 — 通訊與應用進入點

## 規則

1. Spring MVC 註解(`@RestController`, `@RequestMapping` 等)只出現在本層。
2. Controller 方法固定三步:解析參數 → 呼叫 UseCase(Inbound Port)→ 包裝 Response DTO 回傳;方法內零業務判斷。
3. Controller 依賴 UseCase 介面(不是 Impl),建構子注入。
4. Request DTO 使用 `jakarta.validation` 註解(`@NotBlank`, `@NotNull`, `@Min` 等),Controller 參數標 `@Valid @RequestBody`。
5. Response DTO 包裝 Domain 物件的欄位;提供 static factory `from(<Entity>)`;Domain 物件本身一律不直接回傳。
6. 回傳型別一律 `ResponseEntity<T>`:建立回 `201`、查詢/更新回 `200`、刪除回 `204`。
7. `GlobalExceptionHandler` 標 `@RestControllerAdvice`,固定處理四類:`<Entity>NotFoundException` → 404、`MethodArgumentNotValidException` → 400、`IllegalArgumentException` / `IllegalStateException` → 400、`Exception` → 500;錯誤回應格式固定為 `{"error": "<message>"}`。
8. URL 命名:`/api/<entities>`(複數、kebab-case);路徑參數標 `@PathVariable("<name>")`。

## 產出檔案(依序)

1. `dto/<Action>Request.java`(每個寫入型 endpoint 一個)
2. `dto/<Entity>Response.java`
3. `<Entity>Controller.java`
4. `exception/GlobalExceptionHandler.java`

## 模板

### Request DTO `<Action>Request.java`

```java
package <basePackage>.application.<entity>.dto;

import jakarta.validation.constraints.NotNull;

public class <Action>Request {

    @NotNull(message = "<field> must not be null")
    private <Type> <field>;

    public <Type> get<Field>() { return <field>; }
    public void set<Field>(<Type> <field>) { this.<field> = <field>; }
}
```

### Response DTO `<Entity>Response.java`

```java
package <basePackage>.application.<entity>.dto;

import <basePackage>.domain.<entity>.<Entity>;

public class <Entity>Response {

    private final Long id;
    private final <Type> <field>;
    private final String status;

    private <Entity>Response(Long id, <Type> <field>, String status) {
        this.id = id;
        this.<field> = <field>;
        this.status = status;
    }

    public static <Entity>Response from(<Entity> <entity>) {
        return new <Entity>Response(
            <entity>.getId(),
            <entity>.get<Field>(),
            <entity>.getStatus().name()
        );
    }

    public Long getId() { return id; }
    public <Type> get<Field>() { return <field>; }
    public String getStatus() { return status; }
}
```

### 控制器 `<Entity>Controller.java`

```java
package <basePackage>.application.<entity>;

import <basePackage>.application.<entity>.dto.<Action>Request;
import <basePackage>.application.<entity>.dto.<Entity>Response;
import <basePackage>.domain.<entity>.<Entity>;
import <basePackage>.usecase.<entity>.<Entity>UseCase;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/<entities>")
public class <Entity>Controller {

    private final <Entity>UseCase <entity>UseCase;

    public <Entity>Controller(<Entity>UseCase <entity>UseCase) {
        this.<entity>UseCase = <entity>UseCase;
    }

    // POST 建立 → 201
    @PostMapping
    public ResponseEntity<<Entity>Response> create(@Valid @RequestBody <Action>Request request) {
        <Entity> <entity> = <entity>UseCase.create(request.get<Field>());
        return ResponseEntity.status(HttpStatus.CREATED).body(<Entity>Response.from(<entity>));
    }

    // PUT 狀態變更 → 200
    @PutMapping("/{id}/<action>")
    public ResponseEntity<<Entity>Response> <action>(@PathVariable("id") Long id) {
        <Entity> <entity> = <entity>UseCase.<useCaseMethod>(id);
        return ResponseEntity.ok(<Entity>Response.from(<entity>));
    }
}
```

### 全域例外處理器 `GlobalExceptionHandler.java`

```java
package <basePackage>.application.exception;

import <basePackage>.usecase.<entity>.<Entity>NotFoundException;
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
