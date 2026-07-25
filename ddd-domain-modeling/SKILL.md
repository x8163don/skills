---
name: ddd-domain-modeling
description: Guides the user step-by-step through domain modeling before writing code, a class diagram, or a technical design doc — Event Storming (domain events/commands/actors) → tactical DDD analysis (Aggregate/Entity/Value Object boundaries) → OOA class diagram (structure only) → OOD class diagram (behavior + proactive design-pattern suggestions). Maintains a shared project-wide `glossary.md` (Ubiquitous Language) of Aggregate/Entity/Value Object terms across sessions, flagging conflicting definitions instead of silently duplicating terms. Produces a domain-model.md with Mermaid class diagrams. Use this whenever the user is designing a new feature or system and needs to figure out the domain model, aggregate boundaries, entities, value objects, or class structure — including when an OpenSpec design.md needs domain modeling before its Context/Decisions sections can be written, or standalone requests like "幫我做 event storming", "這個功能的 aggregate 怎麼切", "幫我畫 class diagram", "幫我做領域分析", "幫我維護詞彙表", "ubiquitous language". Always work one phase at a time and ask the user domain-specific questions before proposing a model — never invent business rules the user hasn't stated.
---

# DDD Domain Modeling(Event Storming → OOA/OOD)

## 心法:為什麼要逐步問,而不是一次生成

領域知識只存在使用者腦中,不在對話的兩三句描述裡。這個 skill 的工作是在對的順序問對的問題,把使用者的答案收斂成結構化產出——不是看到一個功能名稱就腦補一整套 Aggregate 設計。

順序也不能跳:Aggregate 邊界要先從 Event Storming 找出的「哪些事一定要一起發生」推導出來;Class Diagram 的屬性/關聯要等 Aggregate/Entity/VO 定案才畫得準;Design Pattern 要等看到具體的行為變異點才提,不是先射箭再畫靶。任何一個階段跳過訪談、自己腦補,後面階段大概率要回頭重做。

## 何時使用

- 使用者要設計新功能/新系統,需要釐清領域模型、Aggregate 怎麼切、Entity 跟 Value Object 怎麼分
- 在 OpenSpec 工作流中,`design.md` 需要先有領域模型才能填 Context / Decisions
- 使用者直接要求 event storming、class diagram

**不是每次都要走完整四階段**:如果專案已經有涵蓋這次範圍的既有設計文件,或這次變更明顯很小(例如只是在既有 Aggregate 上加一個屬性),不需要硬逼使用者從 Event Storming 重新訪談一遍。怎麼判斷、怎麼跟使用者確認要不要簡化,見下面「開場」的第一步與 `references/0-scope-triage.md`。

**不使用**:純技術性重構(不涉及新的業務規則或領域概念,例如換一個 ORM、調整檔案結構)、單純的效能調整、或使用者已經明確給出完整的 Aggregate/Class 設計只要求「照這個做」而不是「幫我分析」——這些情況不需要訪談式的領域建模,直接照描述做或使用其他 skill(例如程式碼產生類的 skill)。

## 產出物

兩份文件,層級不同,不要搞混:

- `domain-model.md`:**本次建模**的產出,依四個階段逐步累積章節(不是一次寫完,每階段確認後才落章節)。放在目前工作目錄;如果在 OpenSpec change 資料夾內工作,建議放在該 change 目錄下,跟 `design.md` 同層。
- `glossary.md`:**整個專案共用**的詞彙表(Ubiquitous Language),固定放在專案根目錄(git repo 的話用 repo root,不是子資料夾)。累積所有建模階段(不管哪個功能、哪個 change)沉澱下來的 Aggregate/Entity/Value Object 名稱與定義,讓不同功能之間的用詞保持一致。這份文件跨越所有 domain-model.md,不會因為換了功能就重新開始。細節見 `references/5-glossary.md`。

**開場依序做四件事**:
1. **規模與既有素材評估**:找專案裡既有的 design/architecture 文件(尤其 OpenSpec 的 proposal.md/design.md),實際讀內容判斷有沒有涵蓋這次範圍,再評估這次變更的規模,跟使用者確認要走完整四階段、還是可以跳過部分階段。詳細判斷法則見 `references/0-scope-triage.md`,這一步務必先做,決定了後面要不要照四階段一步步走。
2. 額外收集其他既有素材(使用者故事、會議紀錄)?有的話先讀,減少重複發問。
3. `domain-model.md` 要放在哪裡?(預設:目前工作目錄;如果在 OpenSpec change 資料夾內工作,建議放在該 change 目錄下,跟 `design.md` 同層)
4. 檢查專案根目錄有沒有既有的 `glossary.md`;有就先讀過一遍,讓接下來的訪談(尤其階段 1 的事件命名)沿用已經定案的詞彙,不要另外發明同義詞。沒有就先跟使用者說「這是第一次建這份詞彙表」,繼續往下走即可,不用現在就建立空檔案。

## 核心規則:一次一階段,答案確認後才前進

1. 每階段開始前,先檢查使用者已提供的描述夠不夠回答這階段的問題;不夠就照該階段的引導問題問,不要自己腦補業務規則或抄套模板答案。
2. 每階段結束,把「這階段目前的結論」整理成草稿念給使用者確認或修改;使用者確認後才寫進 `domain-model.md`、才進下一階段。不要因為想加快進度就連續問完四階段的問題再一次性產出。
3. 後面階段發現前面階段的結論有誤(例如畫 Class Diagram 時發現某個 Entity 其實該併進另一個 Aggregate),回頭修正前一階段的章節,並跟使用者說明**為什麼**要改——不要為了往前走而將就一個已知有問題的邊界。

## 四階段總覽

開場的規模評估(見上面「開場」第 1 步、`references/0-scope-triage.md`)決定了以下四階段要完整走一遍,還是跳過某幾階、直接從階段 2 開始問局部問題。

| # | 階段 | 目的 | 這階段結束時要有 | Reference |
|---|---|---|---|---|
| 1 | Event Storming(簡化版) | 按時間序列出流程中發生了什麼事,找出全貌與邊界線索 | Actor → Command → Event 時間序列表 | `references/1-event-storming.md` |
| 2 | Domain Analysis | 從事件收斂出 Aggregate 邊界、Entity、Value Object | 每個 Aggregate 的 Root、內含 Entity/VO、要守護的不變量;並完成一次詞彙表比對(新詞/沿用/衝突) | `references/2-tactical-analysis.md` + `references/5-glossary.md` |
| 3 | OOA Class Diagram | 把 Aggregate/Entity/VO 轉成結構圖(屬性 + 關聯,先不寫方法) | 一份 Mermaid class diagram,只有結構 | `references/3-ooa-class-diagram.md` |
| 4 | OOD Class Diagram + Pattern | 補上行為(方法),對看到的變異點主動提出 pattern 候選 | 補完方法的 Mermaid class diagram + pattern 建議清單(含理由與是否採用) | `references/4-ood-patterns.md` |

每進入一個階段前,讀對應的 reference 檔案——裡面有這階段該問的具體問題清單、判斷法則,以及該怎麼把答案轉成產出格式。不要跳過閱讀直接憑記憶問。

**詞彙表不是第五個階段,是貫穿全程的動作**:階段 2 產出 Aggregate/Entity/VO 名稱後,立刻對照 `glossary.md` 做一次檢查(新詞、沿用、衝突三種情況),流程見 `references/5-glossary.md`。這一步卡在階段 2 結束、階段 3 開始之前,因為階段 3 畫 Class Diagram 要用的類別名稱必須是詞彙表確認過的最終版本,不然衝突沒解決就往下畫,圖畫完又要因為改名重畫。

## domain-model.md 骨架

```markdown
# Domain Model: <主題>

## 1. Event Storming

| 順序 | Actor | Command | Event |
|---|---|---|---|
| 1 | ... | ... | ... |

⚠️ Hotspot(訪談中浮現的疑問/爭議,留待後續確認):
- ...

## 2. Domain Analysis

### Aggregate: <名稱>
- Root: <Entity>
- 內含 Entity: ...
- 內含 Value Object: ...
- 不變量(Invariant): <這個 Aggregate 要保證什麼永遠為真>

### 詞彙表異動(對照專案的 glossary.md)
- 新增: <詞彙 — 定義>
- 沿用既有: <詞彙>
- 衝突已處理: <詞彙 — 舊定義 → 新定義,原因>

## 3. OOA Class Diagram(結構)

\`\`\`mermaid
classDiagram
  class <ClassName> {
    +attr: Type
  }
  <ClassA> "1" --> "0..*" <ClassB> : contains
\`\`\`

## 4. OOD Class Diagram(行為 + Pattern)

\`\`\`mermaid
classDiagram
  class <ClassName> {
    +attr: Type
    +method(): ReturnType
  }
\`\`\`

### Design Pattern 建議
| 變異點 | 建議 Pattern | 理由 | 採用? |
|---|---|---|---|
| ... | ... | ... | 是/否/先不套 |
```

## 完成後

四階段都確認完:

1. 把這次「詞彙表異動」章節裡確認過的新增/更新項目,寫回專案根目錄的 `glossary.md`(沒有這份檔案就新建);格式與寫入規則見 `references/5-glossary.md`。
2. 把 `domain-model.md` 和 `glossary.md` 的路徑都告訴使用者。
3. 提醒:如果這次建模是為了 OpenSpec 的 `design.md`,可以把第 2、3、4 節的重點摘要貼進 `design.md` 的 **Context**(領域概況)與 **Decisions**(pattern 選擇理由)區塊——不用整份搬過去,design.md 該保持精簡,只留跟技術決策直接相關的摘要。
