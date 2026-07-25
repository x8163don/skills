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
