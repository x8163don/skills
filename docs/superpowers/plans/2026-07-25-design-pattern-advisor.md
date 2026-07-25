# design-pattern-advisor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone `design-pattern-advisor` skill covering 13 design patterns (4-part Context/Forces/Solution/Resulting Context knowledge base), then wire `ddd-domain-modeling` stage 4 to call it instead of its own embedded 7-pattern table.

**Architecture:** Two directories of markdown content, no code. `design-pattern-advisor/` is authored fresh; `ddd-domain-modeling/` is imported into this repo (it currently only exists in `~/.claude/skills/`) and then edited. Both are synced back to `~/.claude/skills/` as the final step so the changes take effect immediately.

**Tech Stack:** Markdown only. No build step, no tests in the code sense — verification is grep-based structural checks plus manual dry runs.

**Spec:** `docs/superpowers/specs/2026-07-25-design-pattern-advisor-design.md`

## Global Constraints

- All content is Traditional Chinese (繁體中文), matching the style already used in `~/.claude/skills/ddd-domain-modeling/SKILL.md` and `references/4-ood-patterns.md` — read those two files for tone/register before writing if unsure.
- Every file under `design-pattern-advisor/references/patterns/` has exactly these 4 top-level headers, in this order: `## Context`, `## Forces`, `## Solution`, `## Resulting Context`. No other top-level `##` headers.
- `Forces` is a bulleted list; each bullet states a real, concrete tension (not a vague label like "行為變動性" on its own — say what varies and why it's in tension with something else).
- `Resulting Context` states both what's gained AND what new cost/complexity appears. Never omit the cost side.
- Pseudocode in `## Solution` is language-agnostic (no Java/Go/Python-specific syntax — plain `class X { method(): Type { ... } }`-style pseudocode).
- **Every pattern file's example in `## Solution` must be an original scenario invented for that file — never the course transcript's own example scenario.** Each task below lists the forbidden terms for that pattern; grep for them before considering the task done.
- Source transcripts live at `/Users/bevis/Code/ai-skill/31 DesignPattern課程影片-字幕/*.txt` — read only for extracting Context/Forces/Resulting Context reasoning, never for the example.

---

### Task 1: Scaffold `design-pattern-advisor` skill (SKILL.md)

**Files:**
- Create: `design-pattern-advisor/SKILL.md`

**Interfaces:**
- Produces: the skill's trigger description and usage instructions, referenced by every later task in this plan and by `ddd-domain-modeling/references/4-ood-patterns.md` (Task 18).

- [ ] **Step 1: Create the directory and write SKILL.md**

```markdown
---
name: design-pattern-advisor
description: 根據描述的行為/結構變異點,比對訊號並提出候選 GoF design pattern(Context/Forces/Solution/Resulting Context 四段式說明,含理由與取捨),協助判斷現在該不該套用。獨立、可被任何 skill 呼叫的知識庫型 skill——目前被 ddd-domain-modeling 階段 4 呼叫,未來也可被其他 skill 使用。觸發時機:使用者直接問「這裡要不要套 design pattern」、「這個情境適合什麼設計模式」,或任何 skill 在設計行為/結構時偵測到具體的變異點訊號並需要候選建議。不是每次看到訊號都要套用——只有 Forces 真的互相衝突,且套用後的 Resulting Context 划算,才建議採用,維持 YAGNI。
---

# Design Pattern Advisor

## 何時使用

- 使用者直接問「這裡要不要套 design pattern」、「這個情境適合什麼設計模式」
- 被其他 skill(目前是 `ddd-domain-modeling` 階段 4)呼叫,取得針對某個具體變異點的候選 pattern

## 不使用

- 使用者已經明確決定要套用哪個 pattern,只要求「幫我寫程式碼」——生成生產程式碼是程式碼產生類 skill(如 `java-clean-arch-codegen`)的工作,`design-pattern-advisor` 只負責建議與說明。

## 使用方式

1. 讀 `references/signal-table.md`,比對使用者描述的變異點符合哪一列的訊號。
2. 讀對應的 `references/patterns/<name>.md`,取得該 pattern 的 Context/Forces/Solution/Resulting Context。
3. 提出建議時講清楚三件事,不要只丟 pattern 名稱:
   - 具體的變異點是什麼(對照使用者剛描述的情境,不要只講抽象的「這裡適合用 XX」)
   - 候選 pattern 的 Forces 是否真的在使用者的情境中互相衝突
   - 現在套 vs 先不套的取捨——只有 Forces 真的衝突、且 Resulting Context 的代價划算,才建議現在套用;如果目前只看得到一種實作、使用者也不確定未來會不會變,提醒可以先用最簡單的寫法,等真的出現第二種變化再重構
4. 找不到比對得上的訊號時,誠實告知使用者「目前知識庫沒有涵蓋這個情境」,不要腦補一個不在 `references/patterns/` 裡的 pattern。

## 涵蓋的 Pattern

見 `references/signal-table.md`,共 13 個:行為型(Strategy、Template Method、Chain of Responsibility、Observer、Command、State)、結構型(Proxy、Facade、Adapter、Composite、Decorator)、創建型(Builder、Factory)。
```

- [ ] **Step 2: Verify the file exists and has valid frontmatter**

Run: `head -5 "design-pattern-advisor/SKILL.md"`
Expected: shows the `---` frontmatter block starting with `name: design-pattern-advisor`

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/SKILL.md
git commit -m "$(cat <<'EOF'
Scaffold design-pattern-advisor skill

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 2: Write `signal-table.md`

**Files:**
- Create: `design-pattern-advisor/references/signal-table.md`

**Interfaces:**
- Consumes: nothing (file paths below are fixed by this plan, independent of whether Tasks 3-15 have run yet)
- Produces: the master index, linked to by every `patterns/<name>.md` file path used in Tasks 3-15.

- [ ] **Step 1: Write the file**

```markdown
# 訊號對照表

| 變異點訊號 | Pattern | 分類 | 詳解 |
|---|---|---|---|
| 同一動作依「類型」欄位分支出不同算法(if/switch on type) | Strategy | 行為型 | [patterns/strategy.md](patterns/strategy.md) |
| 多個類似演算法之間大部分步驟相同,只有少數步驟不同 | Template Method | 行為型 | [patterns/template-method.md](patterns/template-method.md) |
| 需要依序嘗試多個處理者,直到找到能處理該請求的那一個,且處理者集合會持續變動 | Chain of Responsibility | 行為型 | [patterns/chain-of-responsibility.md](patterns/chain-of-responsibility.md) |
| 一個物件的狀態改變時,需要通知多個(未來可能更多)訂閱者做出反應 | Observer | 行為型 | [patterns/observer.md](patterns/observer.md) |
| 需要把「觸發」和「實際執行的動作」的綁定關係做成可從外部替換,或需要支援還原/重做 | Command | 行為型 | [patterns/command.md](patterns/command.md) |
| 物件的行為要依「狀態」改變,且各個公開操作中充斥著判斷目前狀態的條件式 | State | 行為型 | [patterns/state.md](patterns/state.md) |
| 需要在不修改既有類別的前提下,控制 client 對某物件的存取(延遲建立、權限管控、遠端存取等) | Proxy | 結構型 | [patterns/proxy.md](patterns/proxy.md) |
| Client 為了完成一個意圖,被迫認識並協調子系統中多個彼此依賴的介面 | Facade | 結構型 | [patterns/facade.md](patterns/facade.md) |
| Client 定義的介面與能實際完成該意圖的類別介面不相容,且不能修改該類別 | Adapter | 結構型 | [patterns/adapter.md](patterns/adapter.md) |
| 需要讓 client 用一致的方式操作一組樹狀結構(遞迴的容器/葉節點),且不在乎自己面對的是單一物件還是整棵子樹 | Composite | 結構型 | [patterns/composite.md](patterns/composite.md) |
| 需要在不修改既有類別的前提下疊加新行為,且疊加的方式要能自由組合 | Decorator | 結構型 | [patterns/decorator.md](patterns/decorator.md) |
| 一個物件的建構需要多個可選步驟、順序敏感 | Builder | 創建型 | [patterns/builder.md](patterns/builder.md) |
| 建立一個複雜物件族的邏輯,應該跟使用它的地方分開 | Factory | 創建型 | [patterns/factory.md](patterns/factory.md) |
```

- [ ] **Step 2: Verify row count**

Run: `grep -c '^|' "design-pattern-advisor/references/signal-table.md"`
Expected: `15` (1 header row + 1 separator row + 13 data rows)

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/signal-table.md
git commit -m "$(cat <<'EOF'
Add design-pattern-advisor signal table (13 patterns)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 3: Write `patterns/strategy.md`

**Files:**
- Create: `design-pattern-advisor/references/patterns/strategy.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/strategy.md`, linked from `signal-table.md` (Task 2)

**Source:** `31 DesignPattern課程影片-字幕/2.1策略模式：一種能力多種行為.txt`
**Forbidden terms (do not reuse as the example):** 英雄, 血量, 水球, 火球, 地球攻擊, Hero, Water Ball, Fireball, Earth, HP
**Assigned original example domain:** 電商訂單的「運費計算」——同一個「計算運費」動作,依運送方式(郵局掛號 / 宅配 / 超商取貨)而有完全不同的計算邏輯。

- [ ] **Step 1: Write the file**

Content requirements — fill in the 4 sections using the substance below (already extracted from the transcript), written in flowing 繁體中文 prose/bullets, NOT a literal copy of these notes:

- **Context**: 程式中有一個動作,其行為會依照某個「類型」欄位而分支(if/switch on type),而且這些類型會持續增加。
- **Forces** (state as real tensions):
  - 行為變動性:這個動作目前已經有多種不同的實作方式,而且未來還會持續新增
  - 擴充性:希望呼叫端(client)能夠簡單地抽換或擴充某個行為,不必進到既有類別中修改
  - 維護性:這些不同實作方式的細節都寫在同一個類別裡,曝露太多細節,拖累了這個類別的可讀性與維護性
- **Solution**: 用「依賴反轉之重構三步驟」——(1) 封裝變動之處:為每一種行為變種各自建立一個類別;(2) 萃取共同行為:把這些變種類別的共同能力萃取成一個介面;(3) 委派:原本的類別不再自己實作這些行為,而是持有這個介面、把行為委派出去,再用依賴注入決定要用哪個具體變種。以「運費計算」為例(不得使用課程的英雄對戰範例),寫出：一個 `ShippingFeeStrategy` 介面(`calculate(order): Money`)、三個實作類別(`RegisteredMailFee`、`HomeDeliveryFee`、`ConvenienceStorePickupFee`),以及 `Order` 如何透過建構子或 setter 依賴注入這個介面,並在需要算運費時委派給它。
- **Resulting Context**:
  - 得到:呼叫端可以自由抽換或擴充某種運費計算方式,新增一種運送方式只要新增一個類別,不必修改既有程式(OCP);每個運費演算法的實作細節被封裝進各自的類別,工程師能專注維護單一演算法
  - 代價:類別數量增加,如果運送方式永遠只有一種、也確定未來不會變,套用 Strategy 反而是過度設計,直接寫在方法裡更簡單

- [ ] **Step 2: Verify required sections and no forbidden terms**

Run:
```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/strategy.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/strategy.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/strategy.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/strategy.md"
grep -iE "英雄|血量|水球|火球|地球攻擊|hero|water ball|fireball" "design-pattern-advisor/references/patterns/strategy.md"
```
Expected: first four commands each print `1`; the last command prints nothing (no match, exit code 1).

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/strategy.md
git commit -m "$(cat <<'EOF'
Add Strategy pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 4: Write `patterns/template-method.md`

**Files:**
- Create: `design-pattern-advisor/references/patterns/template-method.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/template-method.md`, linked from `signal-table.md`

**Source:** `31 DesignPattern課程影片-字幕/2.2樣板方法：變與不變之處.txt`
**Forbidden terms:** 分組, Grouping, 水球軟體學院, 學員, Stereoge, Language Based, Time Slot Based
**Assigned original example domain:** 多個資料來源的「批次匯入」工作——每個匯入工作都是「讀檔 → 逐列解析 → 驗證 → 寫入資料庫」,只有「逐列解析」這一步依來源格式(CSV / 固定寬度文字檔)而不同。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: 程式中有一組類似的行為(演算法/流程),彼此高度相似,但撰寫時被迫用複製貼上再修改的方式實作。
- **Forces**:
  - 這組類似的行為導致撰寫著重複的程式碼
  - 但這些重複的程式碼之中,又有一小部分彼此不同(行為變動性)
  - 開發新的類似行為時,被迫用複製貼上再改寫的方式實作,擴充上吃力、也不好維護
- **Solution**: 辨識出「重複/不變的部分」與「會變的部分」,把不變的部分提取成一個抽象類別上的「樣板方法」(template method),固定呼叫順序;把會變的部分萃取成抽象方法(步驟),交給子類別複寫。以「批次匯入」為例(不得使用課程的分組範例):寫出一個抽象類別 `ImportJob`,樣板方法 `run()` 依序呼叫 `readFile()`(具體,共用)→ `parseRow(line): Record`(抽象)→ `validate(record)`(具體,共用)→ `save(record)`(具體,共用);兩個子類別 `CsvImportJob`、`FixedWidthImportJob` 各自只複寫 `parseRow`。
- **Resulting Context**:
  - 得到:重複的程式碼被提取到樣板方法中一次維護;子類別的實作內容只剩下真正變動的部分,新增一種來源格式只要撰寫一個 `parseRow` 複寫,非常輕鬆
  - 代價:這個模式的作用範圍被限制在單一方法內(繼承關係綁死),如果變動的部分未來需要在執行期動態抽換(而不只是在編譯期用不同子類別決定),就要考慮改用/搭配 Strategy

- [ ] **Step 2: Verify required sections and no forbidden terms**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/template-method.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/template-method.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/template-method.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/template-method.md"
grep -iE "分組|Grouping|水球軟體學院|Stereoge" "design-pattern-advisor/references/patterns/template-method.md"
```
Expected: first four print `1`; last prints nothing.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/template-method.md
git commit -m "$(cat <<'EOF'
Add Template Method pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 5: Write `patterns/chain-of-responsibility.md`

**Files:**
- Create: `design-pattern-advisor/references/patterns/chain-of-responsibility.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/chain-of-responsibility.md`, linked from `signal-table.md`

**Source:** `31 DesignPattern課程影片-字幕/2.3責任鍊模式.txt`
**Forbidden terms:** Discord, 機器人, Bot, Waterball Bot, Dcard, Currency, Help Handler
**Assigned original example domain:** 採購請款的簽核流程——依請款金額路由到不同層級的核准者(部門主管 / 財務主管 / 財務長),核准者集合未來會持續調整。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: 程式需要支援很多種不同的請求類型,每種請求只對應到一種處理行為,而且處理者的集合會持續增加。
- **Forces**:
  - 請求種類會持續新增,而且處理各種請求的行為不同(行為變動性,方向是由少到多)
  - 希望每種請求的處理都是一段獨立的程式,不同處理者之間互不影響,以取得更好的擴充性和維護性
  - 系統未來可能支援新請求、也可能停止支援某些請求,希望能有彈性地決定要支援哪些
- **Solution**: 萃取一個抽象 Handler,每個 Handler 都認識「下一位 Handler」,形成一條鏈;每個 concrete handler 在 handle 時先判斷請求是否隸屬自己的責任範圍,是的話就處理,否則交給下一位。以「採購請款簽核」為例(不得使用課程的 Discord 機器人範例):寫出抽象類別 `ApprovalHandler`(持有 `next: ApprovalHandler`,方法 `approve(request)`),三個具體類別 `ManagerApprovalHandler`(金額 ≤ 1000 才處理)、`FinanceApprovalHandler`(≤ 10000)、`CfoApprovalHandler`(其餘一律處理),透過依賴注入串成一條鏈,原本的請款系統只依賴鏈的第一個 Handler。
- **Resulting Context**:
  - 得到:發起請求的一方完全看不到究竟是哪個 handler 處理了請求,也看不到處理細節,兩者完全解耦;支援新的請求類型只要撰寫新的 handler 並串進鏈中,完全不用修改既有程式(OCP);不同 handler 可以由不同工程師平行開發
  - 代價:各個 concrete handler 之間常常存在重複的「判斷是否為自己責任範圍→處理/否則交給下一位」樣板程式碼,通常會再套用 Template Method 來去除這份重複

- [ ] **Step 2: Verify required sections and no forbidden terms**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/chain-of-responsibility.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/chain-of-responsibility.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/chain-of-responsibility.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/chain-of-responsibility.md"
grep -iE "Discord|機器人|Bot|Dcard" "design-pattern-advisor/references/patterns/chain-of-responsibility.md"
```
Expected: first four print `1`; last prints nothing.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/chain-of-responsibility.md
git commit -m "$(cat <<'EOF'
Add Chain of Responsibility pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 6: Write `patterns/observer.md`

**Files:**
- Create: `design-pattern-advisor/references/patterns/observer.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/observer.md`, linked from `signal-table.md`

**Source:** `31 DesignPattern課程影片-字幕/3.1觀察者模式：響應式行為.txt`
**Forbidden terms:** 學員資料, student.data, 長條圖, 圓餅圖, Job Title Pie Chart, Bar Chart
**Assigned original example domain:** 倉儲庫存變動——庫存數量改變時要觸發多個(未來會更多)反應:補貨提醒、低庫存通知、儀表板更新。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: 程式中某個物件的狀態改變時,需要觸發多道「響應式行為」(reactive behaviors)。
- **Forces**(兩道 forces 缺一都代表不必套用):
  - 程式中存在著多道響應式行為,響應著同一個狀態改變
  - 系統彈性上的要求:希望能有彈性地擴充新的響應式行為、或刪除既有的響應式行為,而完全無需改寫既有類別中的程式(遵守 OCP)——如果響應式行為的數量永遠固定,這道 force 就不存在,套用 Observer 反而是過度設計
- **Solution**: 萃取一個 Observer 介面(具備 `update` 動作),讓每一道響應式行為各自實作這個介面;被觀察的物件(Subject)提供 `register`/`unregister` 方法,狀態改變時呼叫 `notify`,對所有註冊的 observer 呼叫 `update`。以「倉儲庫存」為例(不得使用課程的學員資料圖表範例):`InventoryStock` 作為 subject,`ReorderAlertObserver`、`LowStockNotifier`、`DashboardUpdater` 三個 observer 實作 `StockObserver` 介面;可選擇 Pull Model(observer 在 `update` 時自己回頭向 subject 取得最新庫存)或 Push Model(subject 在 `notify` 時直接把最新庫存數量帶進 `update` 的參數)。
- **Resulting Context**:
  - 得到:subject 只知道有多少 observer 註冊了自己,完全看不到具體的響應式行為,兩者徹底解耦;未來要擴充新的響應式行為時,無需進入 subject 類別修改,只要實作新 observer 並註冊即可(OCP)
  - 代價:Pull Model 下每個 observer 仍然依賴 subject 才能取得資料;Push Model 雖然徹底解耦,但事前得想清楚該推送哪些欄位,推送的資料一旦無法滿足某些 observer 的需求,那些 observer 就只能退回去直接依賴 subject 取資料

- [ ] **Step 2: Verify required sections and no forbidden terms**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/observer.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/observer.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/observer.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/observer.md"
grep -iE "學員資料|student\.data|長條圖|圓餅圖|Pie Chart" "design-pattern-advisor/references/patterns/observer.md"
```
Expected: first four print `1`; last prints nothing.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/observer.md
git commit -m "$(cat <<'EOF'
Add Observer pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 7: Write `patterns/command.md`

**Files:**
- Create: `design-pattern-advisor/references/patterns/command.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/command.md`, linked from `signal-table.md`

**Source:** `31 DesignPattern課程影片-字幕/3.2指令模式.txt`
**Forbidden terms:** 遙控器, 冷氣, 電風扇, 電視, Air Conditioner, Fan, Television, Remote Control, Controller
**Assigned original example domain:** 文字編輯器的工具列按鈕——每個按鈕(粗體 / 斜體 / 插入圖片)綁定一個編輯動作,且要支援復原(Undo)/重做(Redo)。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: 程式中有一個類別暴露了多項操作,每項操作對應到一道指令,而 client 希望能在外部輕易改變「操作」與「指令」的綁定規則。
- **Forces**:
  - Client 透過某個操作(如按下按鈕)來請求執行某道指令,但指令的執行邏輯目前寫死在 switch/case 裡
  - 想輕易地改變操作與指令的綁定規則,且未來要支援新指令時能遵守 OCP,完全不修改既有類別
  - (加分情境)如果指令的執行過程都被封裝成物件,就能輕易地實作還原/重做
- **Solution**: 把每一道指令(以及它操作的接收者)封裝進一個實作 `Command` 介面(`execute()`)的物件;原本負責 dispatch 的類別(Invoker)不再認識任何接收者,只認識 Command,呼叫 `execute()` 即可。以「文字編輯器工具列」為例(不得使用課程的家電遙控器範例):`EditorCommand` 介面,`BoldCommand`、`ItalicCommand`、`InsertImageCommand` 為具體指令,持有它們要操作的 `Document` 接收者;`Toolbar`(Invoker)透過 `bindButton(buttonId, command)` 把按鈕綁到指令上,按下按鈕時呼叫對應指令的 `execute()`。若要支援 Undo/Redo:`Command` 再加上 `undo()`,`Toolbar` 用兩個 Stack(已執行指令、已復原指令)實作復原/重做演算法。
- **Resulting Context**:
  - 得到:Invoker 與接收者之間完全解耦,Invoker 只懂得下達指令,不知道也不在乎指令怎麼執行;新增/刪除指令時無需修改 Invoker(OCP);每道指令的執行邏輯被封裝成獨立、可單獨除錯的類別;副作用是很容易加上 Undo/Redo
  - 代價:指令的種類越多,`Command` 的具體實作類別數量就越多,但每個都很小、職責單一,通常不是問題

- [ ] **Step 2: Verify required sections and no forbidden terms**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/command.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/command.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/command.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/command.md"
grep -iE "遙控器|冷氣|電風扇|電視|Air Conditioner|Fan|Television" "design-pattern-advisor/references/patterns/command.md"
```
Expected: first four print `1`; last prints nothing.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/command.md
git commit -m "$(cat <<'EOF'
Add Command pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 8: Write `patterns/state.md`

**Files:**
- Create: `design-pattern-advisor/references/patterns/state.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/state.md`, linked from `signal-table.md`

**Source:** `31 DesignPattern課程影片-字幕/3.3狀態模式-有限狀態機.txt`
**Forbidden terms:** 購票機, Ticket System, insert coin, 硬幣, sold out, enough coins
**Assigned original example domain:** 訂單狀態生命週期——訂單在「待付款 / 已付款 / 已出貨 / 已送達 / 已取消」之間轉移,各項操作(付款、出貨、取消)的行為都依目前狀態而不同。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: 一個物件的行為在好幾個公開操作中都會依照「目前處於哪個狀態」而改變,而且各個操作的實作中充斥著判斷目前狀態的條件式。
- **Forces**:
  - 物件有明確的多種狀態,行為隨狀態而改變(行為變動性)
  - 為了讓行為隨狀態改變,許多公開操作的實作中都寫著大量判斷目前狀態的條件式,不好閱讀,破壞了維護性
  - (有時)希望允許 client 直接改變物件的狀態,而不只是靠driving一連串操作間接到達某個狀態
- **Solution**: 先畫狀態機圖列舉出所有狀態與轉移規則,再把每個狀態各自封裝成一個實作共同 `State` 介面的類別;物件(Context)不再自己判斷狀態,而是持有目前的 `State` 物件,把每個操作都委派給它;狀態的 entry/exit 動作也封裝在對應的 state 類別中,負責維護該狀態下的屬性一致性。以「訂單狀態」為例(不得使用課程的購票機範例):`OrderState` 抽象類別(`pay()`、`ship()`、`cancel()`),具體類別 `PendingPaymentState`、`PaidState`、`ShippedState`、`DeliveredState`、`CancelledState` 各自複寫合法的操作,不合法的操作(如已送達的訂單呼叫 `pay()`)拋出例外;`Order` 持有 `currentState: OrderState`,每個公開操作只是一行委派。
- **Resulting Context**:
  - 得到:Context 類別的操作瘦身成單行委派,省去大量狀態判斷條件式;新增一種狀態只要新增一個類別,不用修改 Context(OCP);client 能直接透過切換 state 物件來改變 Context 的行為(或還原到某個狀態)
  - 代價:狀態數量直接決定了類別數量;維護「進入/離開某狀態時屬性必須符合什麼一致性規則」的邏輯被分散到各個 state 類別中,好處是每個狀態的規則各自獨立,但要求開發者在每個 state 類別裡都謹慎維護這份一致性

- [ ] **Step 2: Verify required sections and no forbidden terms**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/state.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/state.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/state.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/state.md"
grep -iE "購票機|Ticket System|insert coin|sold out|enough coins" "design-pattern-advisor/references/patterns/state.md"
```
Expected: first four print `1`; last prints nothing.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/state.md
git commit -m "$(cat <<'EOF'
Add State pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 9: Write `patterns/proxy.md`

**Files:**
- Create: `design-pattern-advisor/references/patterns/proxy.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/proxy.md`, linked from `signal-table.md`

**Source:** `31 DesignPattern課程影片-字幕/4-3代理人模式.txt`
**Forbidden terms:** 記帳, Expense Tracking, 小華, CSV, Trial Proxy
**Assigned original example domain:** 相簿應用的高解析度圖片載入——`ImageProvider` 介面,真正的圖檔載入很昂貴,用 Proxy 做延遲載入,只有在真的要顯示縮圖被放大檢視時才載入原始檔案。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: Client 依賴一個介面,而實際實作該介面的物件建立成本很高、需要存取控管,或需要透過某種通訊協定才能取得。
- **Forces**:
  - Client 已經依賴著實作該介面的實體
  - 想要控制 client 對這個實體的存取(延遲建立、限制操作範圍、或透過網路存取),但不能修改這個實體的既有程式(可能是別人維護的、或不想碰)
  - 想要不改變 client 使用介面的方式,悄悄地加上這些控制
- **Solution**: 宣告一個 Proxy 類別,實作 client 依賴的同一個介面;client 改成依賴 Proxy;Proxy 內部持有(或延遲建立)真正的實體,並在每個操作中把呼叫轉發給它,同時可以疊加額外行為。以「相簿應用高解析圖片」為例(不得使用課程的記帳系統範例):`ImageProvider` 介面(`getPixels(): Bitmap`),`RemoteImageProxy` 實作此介面,持有 `realImage: HighResImage`(一開始為 null),`getPixels()` 中判斷若為 null 才向遠端下載並實體化,之後轉發呼叫。
- **Resulting Context**:
  - 得到:Proxy 可以在 client 完全不知情的狀況下,在存取真正物件之前加上延遲載入、權限控管、監控或快取等行為;真正的物件甚至不需要一開始就存在,也不必和 client 在同一個記憶體空間中(Remote Proxy)
  - 代價:多了一個 Proxy 類別要維護;如果 Proxy 改成能代理「任何實作該介面的類別」而非固定代理某個具體類別,雖然更彈性,但會失去延遲建立的能力(因為 Proxy 不再知道要建立哪個具體類型)

- [ ] **Step 2: Verify required sections and no forbidden terms**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/proxy.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/proxy.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/proxy.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/proxy.md"
grep -iE "記帳|Expense Tracking|小華|Trial Proxy" "design-pattern-advisor/references/patterns/proxy.md"
```
Expected: first four print `1`; last prints nothing.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/proxy.md
git commit -m "$(cat <<'EOF'
Add Proxy pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 10: Write `patterns/facade.md`

**Files:**
- Create: `design-pattern-advisor/references/patterns/facade.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/facade.md`, linked from `signal-table.md`

**Source:** `31 DesignPattern課程影片-字幕/4.1門面模式.txt`
**Forbidden terms:** Markdown, 表格, Members Table, Table Stats, Parser
**Assigned original example domain:** 訂單結帳流程——結帳這個意圖背後要協調庫存檢查、優惠券驗證、金流授權、發票開立等多個子系統介面。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: Client 為了完成一個意圖,被迫認識並協調子系統中的多個彼此依賴的介面。
- **Forces**:
  - 結構複雜度太高:子系統中存在許多介面,而且這些介面彼此依賴
  - Client 要求易用性:被迫了解各個介面的能力、還要處理多個介面之間的協作,才能實現一個單純的意圖,學習門檻太高
- **Solution**: 設計一個 Facade 類別,把子系統的內部結構封裝起來,對外只暴露對應 client 意圖的操作,並指導 client 只依賴這個 Facade。以「訂單結帳」為例(不得使用課程的 Markdown 表格統計範例):`CheckoutFacade` 類別,`checkout(cart): Receipt` 這個操作內部依序委派 `InventoryChecker`、`CouponValidator`、`PaymentGateway`、`InvoiceIssuer` 四個子系統介面;`Checkout` 頁面的 client 端程式只需要依賴 `CheckoutFacade`,不需要認識底下這四個介面。
- **Resulting Context**:
  - 得到:client 的依賴介面數量從多個降到一個(或少數幾個),大幅提升易用性與開發生產力
  - 代價:Facade 本身也是需要維護心力的類別;如果子系統的結構經常變動(結構變動性高),Facade 也得跟著頻繁修改——Facade 的維護成本與其內部結構變動的頻率成正比

- [ ] **Step 2: Verify required sections and no forbidden terms**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/facade.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/facade.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/facade.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/facade.md"
grep -iE "Markdown|Members Table|Table Stats" "design-pattern-advisor/references/patterns/facade.md"
```
Expected: first four print `1`; last prints nothing.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/facade.md
git commit -m "$(cat <<'EOF'
Add Facade pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 11: Write `patterns/adapter.md`

**Files:**
- Create: `design-pattern-advisor/references/patterns/adapter.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/adapter.md`, linked from `signal-table.md`

**Source:** `31 DesignPattern課程影片-字幕/4.2轉接器模式.txt`
**Forbidden terms:** 單字, Vocabulary, 爬蟲, Crawler, Dictionary, 小華
**Assigned original example domain:** 簡訊發送——自家定義的 `Notifier` 介面,但實際能發簡訊的是一個介面不相容的第三方簡訊服務 SDK。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: Client 定義了一個表達自己意圖的介面,但實際能完成這個意圖的類別卻實作著另一個不相容的介面,而且不能(或不該)修改那個類別。
- **Forces**:
  - Client 依賴著自己根據意圖定義的介面
  - 真正有能力完成這件事的類別,實作的是另一個不相容的介面,而且這個類別可能是第三方套件,未來會獨立於 client 演進,不能修改它
  - 想要重複利用那個類別的能力,又不希望它的介面細節污染 client 定義好的介面
- **Solution**: 宣告一個 Adapter 類別,實作 client 定義的目標介面(Target),內部持有(依賴注入或自行建立)那個不相容的類別(Adaptee),並在每個操作中把呼叫轉譯過去——包含參數型別、回傳型別,甚至例外型別的轉換。以「簡訊發送」為例(不得使用課程的英文單字字典爬蟲範例):自家的 `Notifier` 介面(`send(phone, message)`,失敗時丟 `NotificationFailedException`),第三方 `ThirdPartySmsSdk`(方法名稱、參數、例外型別完全不同,且不能修改);寫一個 `SmsNotifierAdapter implements Notifier`,內部持有 `ThirdPartySmsSdk`,把 `send()` 轉譯成該 SDK 的呼叫方式,並把 SDK 丟出的例外包裝成 `NotificationFailedException` 再拋出。
- **Resulting Context**:
  - 得到:client 完全不需要依賴那個不相容的介面或第三方套件,未來要更換簡訊供應商,只需要換一個新的 Adapter,client 程式碼完全不受影響;這正是依賴反轉原則(DIP)的具體實作方式——先以 client 的意圖定義介面,再讓低層次的實作去 adapt 這個介面
  - 代價:Adapter 本身需要維護,一旦被轉接的介面(第三方 SDK)改版,轉接邏輯要跟著更新

- [ ] **Step 2: Verify required sections and no forbidden terms**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/adapter.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/adapter.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/adapter.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/adapter.md"
grep -iE "單字|Vocabulary|爬蟲|Crawler|小華" "design-pattern-advisor/references/patterns/adapter.md"
```
Expected: first four print `1`; last prints nothing.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/adapter.md
git commit -m "$(cat <<'EOF'
Add Adapter pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 12: Write `patterns/composite.md`

**Files:**
- Create: `design-pattern-advisor/references/patterns/composite.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/composite.md`, linked from `signal-table.md`

**Source:** `31 DesignPattern課程影片-字幕/4.4複合模式.txt`
**Forbidden terms:** 檔案系統, Directory, File (as a class name in context), 目錄, Common Line Interface
**Assigned original example domain:** 電商商品分類樹——`Category` 可以包含子分類與商品,要計算某個分類底下(含所有子分類)的商品總數與價格範圍。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: Client 需要用一致的方式操作一組物件,而這組物件組成一棵樹(遞迴的部分-整體階層——某些物件包含著同一抽象類型的子物件,某些則是葉節點)。
- **Forces**:
  - 結構複雜度高:結構中存在遞迴關聯(self-association),讓結構能無限延伸
  - 結構變動性:樹中節點的具體種類未來可能增加(新的容器/葉節點類型)
  - Client 想在完成自己的意圖時(例如計算大小、統計數量),不必在乎自己面對的是單一葉節點還是整棵子樹,容器類別的實作也不希望為每種子節點型別各寫一套分支邏輯
- **Solution**: 萃取一個抽象的 Component 型別,同時代表葉節點與容器角色;容器持有一份 Component 型別的子節點清單(而非按型別分開的多份清單),並透過對每個子節點遞迴呼叫同一個操作來實作自己的操作;client 只依賴 Component。以「電商商品分類樹」為例(不得使用課程的檔案系統範例):抽象類別 `CatalogItem`(`countProducts(): int`),`Product implements CatalogItem`(葉節點,回傳 1),`Category implements CatalogItem`(容器,持有 `children: List<CatalogItem>`,`countProducts()` 對所有子節點的 `countProducts()` 加總);`StorefrontPage`(client)只呼叫某個 `CatalogItem.countProducts()`,不必知道自己拿到的是單一商品還是整棵分類子樹。
- **Resulting Context**:
  - 得到:client 變得對結構無感(structure-agnostic)——完全不必知道自己面對的是葉節點還是整棵子樹,也不必因為結構變動而修改;新增一種節點型別無需修改 client 或既有容器類別(OCP);容器類別不再需要為不同子節點型別各寫一份重複邏輯
  - 代價:「透明度」(把所有操作都放進共用的 Component 介面,讓葉節點與容器操作起來完全一致)和「操作安全性」互相衝突——如果把 `addChild()` 也放進 Component,葉節點就必須為這個它不支援的操作丟出執行期例外;必須根據實際情境的 client 需求權衡,選擇影響較大的那道 force 優先解決

- [ ] **Step 2: Verify required sections and no forbidden terms**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/composite.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/composite.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/composite.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/composite.md"
grep -iE "檔案系統|Common Line Interface" "design-pattern-advisor/references/patterns/composite.md"
```
Expected: first four print `1`; last prints nothing.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/composite.md
git commit -m "$(cat <<'EOF'
Add Composite pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 13: Write `patterns/builder.md` (no course source — GoF knowledge)

**Files:**
- Create: `design-pattern-advisor/references/patterns/builder.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/builder.md`, linked from `signal-table.md`

**Source:** none (no course transcript covers this pattern) — use standard GoF knowledge.
**Assigned original example domain:** 組裝一個 HTTP 請求物件——有多個可選部分(headers、query params、body、認證資訊),且部分欄位之間有設定順序的限制(例如先設定 body 才能設定 content-type)。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: 一個物件的建構需要多個可選步驟,且步驟之間可能順序敏感,如果全部塞進一個建構子,參數列會又長又難懂,而且不是每次都需要全部參數。
- **Forces**:
  - 物件有多個可選的組成部分,不是每次建構都需要全部設定
  - 建構的過程有順序或相依性(例如某個部分要先設定,另一個部分才能正確組裝)
  - 直接用一個多參數建構子(telescoping constructor)會導致呼叫端難以閱讀,也容易傳錯參數順序
- **Solution**: 把逐步組裝的邏輯抽到一個獨立的 Builder 類別,提供一連串可鏈式呼叫的方法各自設定一個可選部分,最後用 `build()` 產出成品物件;成品物件本身維持不可變(immutable)。以「HTTP 請求物件」為例:`HttpRequestBuilder`,方法 `withHeader(key, value)`、`withQueryParam(key, value)`、`withBody(content)`、`withAuth(token)` 各自回傳 `this` 以支援鏈式呼叫,最後 `build(): HttpRequest` 產出不可變的 `HttpRequest` 物件;呼叫端寫成 `new HttpRequestBuilder().withHeader(...).withBody(...).withAuth(...).build()`。
- **Resulting Context**:
  - 得到:建構過程變得可讀、可重用,呼叫端只需要設定自己在乎的部分;建構的細節(順序驗證、預設值)被集中在 Builder 內部維護,成品物件保持不可變
  - 代價:多了一個 Builder 類別要維護,如果物件只有 2-3 個必要參數、彼此沒有順序限制,直接用建構子會更簡單,套用 Builder 反而是過度設計

- [ ] **Step 2: Verify required sections**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/builder.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/builder.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/builder.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/builder.md"
```
Expected: all four print `1`.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/builder.md
git commit -m "$(cat <<'EOF'
Add Builder pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 14: Write `patterns/factory.md` (no course source — GoF knowledge)

**Files:**
- Create: `design-pattern-advisor/references/patterns/factory.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/factory.md`, linked from `signal-table.md`

**Source:** none — use standard GoF knowledge (Factory Method).
**Assigned original example domain:** 依使用者通知偏好建立不同的 `Notification` 物件(Email / SMS / Push),呼叫端不該自己寫 `new` 加上型別判斷。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: 程式中需要依某個條件（如使用者偏好、設定值）建立一個複雜物件族中的其中一種,而「怎麼建立」的知識目前散落在每個呼叫 `new` 的地方,和「怎麼使用」混在一起。
- **Forces**:
  - 存在一組相關但實作不同的類別(物件族),需要依條件選擇建立哪一種
  - 建立這些物件的細節(要傳哪些參數、要不要額外初始化)不該讓每個呼叫端各自知道並重複實作
  - 未來這個物件族可能會新增成員,希望新增時不必修改所有呼叫 `new` 的地方
- **Solution**: 把「依條件建立哪一種物件」的邏輯集中到一個工廠方法裡,呼叫端只需要告訴工廠要什麼類型,不需要自己 `new` 並處理型別判斷。以「使用者通知」為例:`Notification` 介面,`EmailNotification`、`SmsNotification`、`PushNotification` 三個實作;`NotificationFactory.create(preference: NotificationChannel): Notification` 內部依 `preference` 決定要 `new` 哪一個具體類別並完成必要的初始化;呼叫端只寫 `notificationFactory.create(user.preference).send(message)`。
- **Resulting Context**:
  - 得到:建立物件的知識集中在工廠裡管理,呼叫端不需要知道每種通知類型的建構細節;新增一種通知管道時,只需要修改工廠內部(集中一處),呼叫端程式碼不變
  - 代價:多了一層工廠類別的間接性;如果物件族的成員數量固定且很少變動,直接在呼叫端 `new` 反而更直白,不需要工廠

- [ ] **Step 2: Verify required sections**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/factory.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/factory.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/factory.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/factory.md"
```
Expected: all four print `1`.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/factory.md
git commit -m "$(cat <<'EOF'
Add Factory pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 15: Write `patterns/decorator.md` (no course source — GoF knowledge)

**Files:**
- Create: `design-pattern-advisor/references/patterns/decorator.md`

**Interfaces:**
- Consumes: nothing from other tasks
- Produces: `patterns/decorator.md`, linked from `signal-table.md`

**Source:** none — use standard GoF knowledge.
**Assigned original example domain:** 包裝一個基礎的 `DataFetcher`(呼叫外部 API 取得資料),用可自由組合的 Decorator 疊加快取、重試、記錄 log 等橫切行為。

- [ ] **Step 1: Write the file**

Content requirements:

- **Context**: 需要在不修改既有類別的前提下,為某個物件疊加額外行為,而且這些額外行為要能自由組合、任意搭配。
- **Forces**:
  - 有一個基礎行為(如呼叫外部 API 取資料),但不同情境下需要疊加不同的額外行為(快取、重試、記錄 log)
  - 這些額外行為的組合是動態的、可能因情境而異(有時只要快取,有時快取加重試都要),用繼承的方式為每種組合各寫一個子類別會導致類別數量爆炸
  - 不想修改基礎類別本身的程式碼
- **Solution**: 讓 Decorator 與被包裝的物件實作同一個介面,Decorator 內部持有一個該介面的實體(可能是原始物件,也可能是另一個 Decorator),在轉發呼叫的前後加上自己的行為,如此可以層層疊加、任意組合。以「資料抓取」為例:`DataFetcher` 介面(`fetch(id): Data`),`ApiDataFetcher`(基礎實作),`CachingDataFetcher implements DataFetcher`(持有一個 `DataFetcher`,`fetch()` 先查快取,沒有才轉發並存入快取)、`RetryingDataFetcher implements DataFetcher`(持有一個 `DataFetcher`,`fetch()` 失敗時重試數次);組合方式為 `new RetryingDataFetcher(new CachingDataFetcher(new ApiDataFetcher()))`,想要哪些行為就疊加哪些 Decorator。
- **Resulting Context**:
  - 得到:額外行為可以用組合(composition)取代繼承,任意搭配疊加,不需要為每種組合各寫一個類別;新增一種橫切行為只要新增一個 Decorator 類別,不影響既有的基礎類別或其他 Decorator
  - 代價:疊加太多層 Decorator 時,呼叫堆疊變深,除錯時要一層一層追蹤,可讀性會下降;如果只有一兩種固定的行為組合,直接寫死反而更清楚,不需要 Decorator 的彈性

- [ ] **Step 2: Verify required sections**

```bash
grep -c "^## Context$" "design-pattern-advisor/references/patterns/decorator.md"
grep -c "^## Forces$" "design-pattern-advisor/references/patterns/decorator.md"
grep -c "^## Solution$" "design-pattern-advisor/references/patterns/decorator.md"
grep -c "^## Resulting Context$" "design-pattern-advisor/references/patterns/decorator.md"
```
Expected: all four print `1`.

- [ ] **Step 3: Commit**

```bash
git add design-pattern-advisor/references/patterns/decorator.md
git commit -m "$(cat <<'EOF'
Add Decorator pattern reference to design-pattern-advisor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 16: Import `ddd-domain-modeling` into the repo

**Files:**
- Create: `ddd-domain-modeling/` (entire directory, copied from `~/.claude/skills/ddd-domain-modeling/`)

**Interfaces:**
- Consumes: nothing
- Produces: `ddd-domain-modeling/SKILL.md` and `ddd-domain-modeling/references/*.md` in the repo, edited by Tasks 17-18.

- [ ] **Step 1: Copy the skill into the repo**

```bash
cp -R ~/.claude/skills/ddd-domain-modeling "/Users/bevis/Code/ai-skill/ddd-domain-modeling"
```

- [ ] **Step 2: Verify the copy is complete**

Run: `diff -rq ~/.claude/skills/ddd-domain-modeling "/Users/bevis/Code/ai-skill/ddd-domain-modeling"`
Expected: no output (directories identical)

- [ ] **Step 3: Commit**

```bash
git add ddd-domain-modeling/
git commit -m "$(cat <<'EOF'
Import ddd-domain-modeling skill into this repo

Brings the skill under version control for the first time so the
design-pattern-advisor integration changes (Tasks 17-18) are tracked.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 17: Edit `ddd-domain-modeling/SKILL.md` — remove the standalone pattern trigger

**Files:**
- Modify: `ddd-domain-modeling/SKILL.md` (the `description:` frontmatter line)

**Interfaces:**
- Consumes: `ddd-domain-modeling/SKILL.md` from Task 16
- Produces: updated description with the "這裡要不要套 design pattern" trigger phrase removed

- [ ] **Step 1: Read the current description line**

Run: `grep -n "這裡要不要套 design pattern" "ddd-domain-modeling/SKILL.md"`
Expected: prints the line number and content of the description line containing this phrase (inside the long `description:` frontmatter value).

- [ ] **Step 2: Remove the phrase from the description**

Find the substring `、或「這裡要不要套 design pattern」、「幫我做領域分析」` (or however the phrase is joined into the surrounding list — read the exact surrounding text with the grep from Step 1) and remove just `「這裡要不要套 design pattern」、` from the list, keeping the rest of the sentence grammatically intact. Use the Edit tool with the exact surrounding text as `old_string`/`new_string` (do not guess — copy the exact text found in Step 1).

- [ ] **Step 3: Verify the phrase is gone and the frontmatter is still valid YAML**

```bash
grep -c "這裡要不要套 design pattern" "ddd-domain-modeling/SKILL.md"
head -5 "ddd-domain-modeling/SKILL.md"
```
Expected: first command prints `0`; second command shows an intact `---` frontmatter block.

- [ ] **Step 4: Commit**

```bash
git add ddd-domain-modeling/SKILL.md
git commit -m "$(cat <<'EOF'
Remove standalone pattern-suggestion trigger from ddd-domain-modeling

"這裡要不要套 design pattern" is now owned by design-pattern-advisor,
which ddd-domain-modeling's stage 4 calls internally instead of
reasoning from its own embedded table.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 18: Edit `ddd-domain-modeling/references/4-ood-patterns.md` — call out to design-pattern-advisor

**Files:**
- Modify: `ddd-domain-modeling/references/4-ood-patterns.md`

**Interfaces:**
- Consumes: `design-pattern-advisor` skill (Tasks 1-15), `ddd-domain-modeling/references/4-ood-patterns.md` from Task 16
- Produces: updated stage-4 reference that delegates pattern suggestions to `design-pattern-advisor`

- [ ] **Step 1: Read the current file to get exact text for replacement**

Run: `cat -n "ddd-domain-modeling/references/4-ood-patterns.md"`
(Already read in full earlier in this plan's authoring — the file has a "## 主動提出 Design Pattern 建議:訊號 → 候選對照" section with an embedded table (lines ~13-26 as of Task 16's import) and a "## 怎麼提出建議(措辭原則)" section below it.)

- [ ] **Step 2: Replace the embedded signal table section**

Using the Edit tool, replace the entire section starting at `## 主動提出 Design Pattern 建議:訊號 → 候選對照` through the end of the table (the line before `## 怎麼提出建議(措辭原則)`) with:

```markdown
## 主動提出 Design Pattern 建議

在補方法的過程中,一旦觀察到具體的行為變異點(不要等使用者問才講),呼叫 `design-pattern-advisor` skill,附上這個變異點的具體描述(不是抽象的「這裡有變動性」,而是「你剛提到 <A> 未來還會有 <B>、<C> 兩種算法」這種具體描述),取得候選 pattern 的 Context/Forces/Solution/Resulting Context。不要自己憑記憶列出訊號對照表——`design-pattern-advisor` 是這份知識的唯一來源,才能確保未來新增 pattern 時兩邊不會不同步。
```

- [ ] **Step 3: Update the "怎麼提出建議(措辭原則)" section's third point to reference the advisor's Resulting Context**

Find the existing text:
```
3. **現在套 vs 先不套的取捨**——如果目前只看得到一種實作、使用者也不確定未來會不會變,提醒可以先用最簡單的寫法(例如直接 if/else 或單一方法),等真的出現第二種變化再重構成 Pattern,不用為了假設中的彈性預先套用。**只有在使用者確認未來變化是大概率會發生的,才建議現在就套。**
```
Replace it with:
```
3. **現在套 vs 先不套的取捨**——參考 `design-pattern-advisor` 回傳的 Forces 是否真的在使用者的情境中互相衝突、Resulting Context 的代價是否划算。如果目前只看得到一種實作、使用者也不確定未來會不會變,提醒可以先用最簡單的寫法(例如直接 if/else 或單一方法),等真的出現第二種變化再重構成 Pattern,不用為了假設中的彈性預先套用。**只有在使用者確認未來變化是大概率會發生的,才建議現在就套。**
```

- [ ] **Step 4: Verify the old embedded table is gone and the new call-out is present**

```bash
grep -c "候選 Pattern" "ddd-domain-modeling/references/4-ood-patterns.md"
grep -c "design-pattern-advisor" "ddd-domain-modeling/references/4-ood-patterns.md"
```
Expected: first command prints `0` (the old signal table's header text is gone); second prints `2` or more (referenced in the new call-out section and the updated point 3).

- [ ] **Step 5: Commit**

```bash
git add ddd-domain-modeling/references/4-ood-patterns.md
git commit -m "$(cat <<'EOF'
Wire ddd-domain-modeling stage 4 to call design-pattern-advisor

Replaces the embedded 7-pattern signal table with a call-out to the
shared design-pattern-advisor skill, which now covers 13 patterns.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015QQ7kpgfXtz2pkLzNpDYC3
EOF
)"
```

---

### Task 19: Sync both skills to `~/.claude/skills/`

**Files:**
- Overwrite: `~/.claude/skills/design-pattern-advisor/` (new)
- Overwrite: `~/.claude/skills/ddd-domain-modeling/` (existing, will be overwritten with the repo version)

**Interfaces:**
- Consumes: `design-pattern-advisor/` (Tasks 1-15) and `ddd-domain-modeling/` (Tasks 16-18) from the repo
- Produces: live, effective skills at `~/.claude/skills/`

**Note:** this step overwrites the live copy of `ddd-domain-modeling` that the user has been using. Since the repo copy was imported directly from that same live copy in Task 16 and only had the two targeted edits applied on top (Tasks 17-18), this is a faithful sync, not a divergent rewrite — but flag this to the user before running it, since it's a change to files outside the git repo.

- [ ] **Step 1: Copy design-pattern-advisor (new skill, no existing content to preserve)**

```bash
cp -R "/Users/bevis/Code/ai-skill/design-pattern-advisor" ~/.claude/skills/design-pattern-advisor
```

- [ ] **Step 2: Sync ddd-domain-modeling (overwrite existing)**

```bash
rm -rf ~/.claude/skills/ddd-domain-modeling
cp -R "/Users/bevis/Code/ai-skill/ddd-domain-modeling" ~/.claude/skills/ddd-domain-modeling
```

- [ ] **Step 3: Verify both are in sync with the repo**

```bash
diff -rq "/Users/bevis/Code/ai-skill/design-pattern-advisor" ~/.claude/skills/design-pattern-advisor
diff -rq "/Users/bevis/Code/ai-skill/ddd-domain-modeling" ~/.claude/skills/ddd-domain-modeling
```
Expected: both commands print no output (directories identical).

No commit needed — `~/.claude/skills/` is outside the git repo.

---

### Task 20: Validation dry runs (manual, per the spec's validation plan)

**Files:** none (manual verification only)

**Interfaces:**
- Consumes: everything from Tasks 1-19

- [ ] **Step 1: Standalone trigger test**

In a fresh Claude Code conversation, ask: "這個情境要不要套 Strategy pattern:同一個折扣計算方法依會員等級分支出不同算法" and confirm `design-pattern-advisor` triggers and correctly loads `patterns/strategy.md`'s reasoning (not a different pattern).

- [ ] **Step 2: Integrated trigger test**

In a fresh Claude Code conversation, invoke `ddd-domain-modeling` on a small scenario (e.g. an order-discount calculation that branches by membership tier) and walk it to stage 4. Confirm it calls `design-pattern-advisor` when it spots the variation point, rather than reasoning from a table embedded in `4-ood-patterns.md` (which no longer has one).

- [ ] **Step 3: Content spot-check**

Manually read `design-pattern-advisor/references/patterns/chain-of-responsibility.md` (course-sourced) and `design-pattern-advisor/references/patterns/builder.md` (GoF-only) end to end. Confirm: all 4 sections present, Forces state real tensions (not vague labels), Resulting Context states both benefit and cost, and the example in Solution matches each task's assigned original domain (not the course transcript's scenario).

No commit for this task — it's a verification pass. If any check fails, fix the relevant file and re-run its Task's Step 2 grep checks before re-verifying here.
