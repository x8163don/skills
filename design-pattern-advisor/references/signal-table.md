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
