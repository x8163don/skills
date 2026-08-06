# Adapter/Inbound 層 — 通訊與應用進入點(Interface Adapters,被外部驅動的一側)

這一層產完之後,還要產生 Controller-level 整合測試(見文末章節),是整個 skill 唯二兩層測試中的第二層——完整原則見 `references/testing_principles.md`。

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
4. `<Entity>ControllerIntegrationTest.java`(Controller-level 整合測試,四層都產生完、確定可編譯後才產,見文末章節)

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

## Controller-level 整合測試(Testcontainers)

這是整個 skill 唯二兩層測試(見 `references/testing_principles.md`)裡的第二層,四層都產生完、確定可以編譯之後才產生。目標是把 HTTP → Controller → UseCase → Repository → 真實資料庫這條完整路線串起來測一次,不 mock Repository、不用 H2/sqlite 這種 in-memory 替代品——用 [Testcontainers](https://testcontainers.com/) 起一個跟正式環境同一種 image 的 DB(以下用 Postgres 示範,實際專案是 MySQL/MariaDB 時把 `PostgreSQLContainer` 換成對應 module,其餘寫法相同)。

只有第三方 SaaS 依賴(如 `PaymentClient` 這種 `client/` 分類、沒有可信賴 testcontainers image 的外部 API)才用 `@MockBean` 蓋掉那一個 Outbound Port,其餘(Repository、in-process 事件)全部真實。斷言不能只看 HTTP 回應——寫入操作要再用 `<Entity>JpaRepository` 查一次,確認資料真的落地。

需要的 test 依賴(`pom.xml`,`<scope>test</scope>`):`org.testcontainers:junit-jupiter`、`org.testcontainers:postgresql`(或對應 DB 的 module)。

```java
// === Adapter/Inbound Layer ===
// File: src/test/java/<basePackage 路徑>/adapter/inbound/web/<entity>/<Entity>ControllerIntegrationTest.java

package <basePackage>.adapter.inbound.web.<entity>;

import <basePackage>.adapter.outbound.repository.<Entity>JpaRepository;
import <basePackage>.adapter.outbound.repository.datamodel.<Entity>DataModel;
import <basePackage>.usecase.<entity>.port.<Concept>Client;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class <Entity>ControllerIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void registerDatasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private <Entity>JpaRepository <entity>JpaRepository;

    // 沒有可信賴 testcontainers image 的第三方 SaaS 依賴,才 mock 這一個 Outbound Port
    @MockBean
    private <Concept>Client <concept>Client;

    @LocalServerPort
    private int port;

    @Test
    void <action>_persistsNewStatusToDatabase() {
        when(<concept>Client.<clientMethod>(any())).thenReturn(<stubResult>);

        <Entity>DataModel saved = <entity>JpaRepository.save(
            new <Entity>DataModel(null, <args>, "<INITIAL_STATE>"));

        ResponseEntity<<Entity>Response> response = restTemplate.exchange(
            "/api/<entities>/" + saved.getId() + "/<action>",
            org.springframework.http.HttpMethod.PUT, null, <Entity>Response.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody().getStatus()).isEqualTo("<EXPECTED_STATE>");

        // 不能只看回應——再查一次資料庫確認狀態真的被更新
        <Entity>DataModel refetched = <entity>JpaRepository.findById(saved.getId()).orElseThrow();
        assertThat(refetched.getStatus()).isEqualTo("<EXPECTED_STATE>");
    }

    @Test
    void getById_returns404_whenMissing() {
        ResponseEntity<String> response = restTemplate.getForEntity("/api/<entities>/999999", String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    }
}
```
