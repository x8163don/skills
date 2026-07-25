# 階段 4:OOD Class Diagram(補行為) + Design Pattern 建議

## 目的

在階段 3 的結構圖上補上方法(behavior),並且在看到具體的「行為變異點」時,主動提出可能適用的 Design Pattern候選——但不是每次都要套,YAGNI 仍然優先,提出候選只是讓使用者能做知情的選擇。

## 補方法:先問「誰該負責這個邏輯」

對每一條在階段 1 Event Storming 裡出現的 Command / 業務規則,問:「這個動作,應該由哪個類別負責?」

判斷原則(Information Expert,GRASP 的核心概念之一):**擁有做這件事所需資料的那個類別,就該擁有這個方法**。例如「確認訂單」需要知道訂單目前狀態,這個方法就該長在 Order 上,不要放到一個外部的 Service 類別裡把 Order 當純資料袋。只有當一個行為明顯橫跨多個 Aggregate(例如「訂單確認後同時發送通知」)才考慮用 Application Service / Use Case 層去協調,而不是塞進單一 Entity。

## 主動提出 Design Pattern 建議

在補方法的過程中,一旦觀察到具體的行為變異點(不要等使用者問才講),呼叫 `design-pattern-advisor` skill,附上這個變異點的具體描述(不是抽象的「這裡有變動性」,而是「你剛提到 <A> 未來還會有 <B>、<C> 兩種算法」這種具體描述),取得候選 pattern 的 Context/Forces/Solution/Resulting Context。不要自己憑記憶列出訊號對照表——`design-pattern-advisor` 是這份知識的唯一來源,才能確保未來新增 pattern 時兩邊不會不同步。

## 怎麼提出建議(措辭原則)

看到訊號時,講清楚三件事,再讓使用者決定:

1. **具體的變異點是什麼**(不要只說「這裡適合用 XX Pattern」,要指出「你剛提到 <A> 未來還會有 <B>、<C> 兩種算法」)
2. **候選 Pattern 是什麼、為什麼適合**(根據 `design-pattern-advisor` 回傳的 Context/Forces/Solution 說明)
3. **現在套 vs 先不套的取捨**——參考 `design-pattern-advisor` 回傳的 Forces 是否真的在使用者的情境中互相衝突、Resulting Context 的代價是否划算。如果目前只看得到一種實作、使用者也不確定未來會不會變,提醒可以先用最簡單的寫法(例如直接 if/else 或單一方法),等真的出現第二種變化再重構成 Pattern,不用為了假設中的彈性預先套用。**只有在使用者確認未來變化是大概率會發生的,才建議現在就套。**

## 輸出格式

Class Diagram 補上方法簽名(沿用階段 3 的 mermaid code block,在每個 class 裡加 `+method(): ReturnType`)。

Pattern 建議整理成表格:

```
| 變異點 | 建議 Pattern | 理由 | 採用? |
|---|---|---|---|
| ... | ... | ... | 是 / 否 / 先不套,等出現第二種變化再說 |
```

## 停止條件

Class Diagram 的每個類別都有對應到階段 1 Command 的方法、使用者確認過每一條 Pattern 建議的「採用?」欄位,這階段才算完成。完成後回到 SKILL.md 的「完成後」章節收尾。
