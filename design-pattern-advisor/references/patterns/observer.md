# Observer(觀察者模式)

## Context

程式中某個物件的狀態改變時,需要觸發多道「響應式行為」(reactive behaviors)。這些響應式行為彼此獨立、各自關心的事情不同,但都是因為同一個狀態改變而被觸發。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下兩股力量——這兩道 force 缺一,套用 Observer 都不划算:

- **多重響應**:程式中存在著多道響應式行為,響應著同一個狀態改變。如果狀態改變後只需要做一件事,不需要額外抽出 Observer 介面,直接在狀態改變的地方呼叫那件事就好。
- **彈性擴充的要求**:系統希望能有彈性地擴充新的響應式行為、或刪除既有的響應式行為,而完全無需改寫既有類別中的程式(遵守開放封閉原則,OCP)。如果響應式行為的數量永遠固定、未來也不會再新增或刪除,這道 force 就不存在——套用 Observer 反而是過度設計,徒增一層介面與註冊機制,卻沒有帶來對應的彈性收益。

只有當「同一個狀態改變要觸發多道響應」與「這些響應未來還會持續增減」兩者同時成立時,Observer 才值得套用。

## Solution

核心手法是萃取一個 `Observer` 介面(具備 `update` 動作),讓每一道響應式行為各自實作這個介面;被觀察的物件(Subject)提供 `register`/`unregister` 方法讓 observer 加入或退出,狀態改變時呼叫 `notify`,對所有已註冊的 observer 逐一呼叫 `update`。

以「倉儲庫存變動」為例——庫存數量改變時要觸發多道(未來會更多)反應:補貨提醒、低庫存通知、儀表板更新:

```
// Observer 介面:所有響應式行為都要實作這個共同的 update 動作
interface StockObserver {
  update(stock: InventoryStock): void
}

// Subject:被觀察的物件,持有一份 observer 清單
class InventoryStock {
  private observers: StockObserver[] = []
  private quantity: number

  register(observer: StockObserver): void {
    this.observers.push(observer)
  }

  unregister(observer: StockObserver): void {
    this.observers = this.observers.filter(o => o !== observer)
  }

  changeQuantity(delta: number): void {
    this.quantity += delta
    this.notify()
  }

  getQuantity(): number {
    return this.quantity
  }

  private notify(): void {
    for (const observer of this.observers) {
      observer.update(this)
    }
  }
}

// 響應式行為一:庫存低於門檻時提醒補貨(Pull Model:自己回頭向 subject 取值)
class ReorderAlertObserver implements StockObserver {
  update(stock: InventoryStock): void {
    if (stock.getQuantity() < REORDER_THRESHOLD) {
      sendReorderAlert(stock.getQuantity())
    }
  }
}

// 響應式行為二:庫存過低時通知相關人員
class LowStockNotifier implements StockObserver {
  update(stock: InventoryStock): void {
    if (stock.getQuantity() < LOW_STOCK_THRESHOLD) {
      notifyStaff(stock.getQuantity())
    }
  }
}

// 響應式行為三:更新儀表板上的即時庫存數字
class DashboardUpdater implements StockObserver {
  update(stock: InventoryStock): void {
    refreshDashboard(stock.getQuantity())
  }
}

// 呼叫端組裝:把各個響應式行為註冊到 subject 上
stock = new InventoryStock()
stock.register(new ReorderAlertObserver())
stock.register(new LowStockNotifier())
stock.register(new DashboardUpdater())

stock.changeQuantity(-50)  // 觸發 notify,依序呼叫每個已註冊 observer 的 update
```

上面採用的是 **Pull Model**:`update` 只帶入 subject 本身的參考,observer 在需要資料時自己回頭呼叫 `stock.getQuantity()` 取得最新庫存。另一種做法是 **Push Model**:subject 在 `notify` 時直接把最新庫存數量當作參數帶進 `update`,例如 `observer.update(this.quantity)`,observer 不需要再反查 subject。兩種模型可依團隊需求擇一。

未來如果要新增第四種響應式行為(例如「補貨單自動產生」),只需要新增一個實作 `StockObserver` 的類別並呼叫 `register`,`InventoryStock` 本身完全不需要修改。

## Resulting Context

套用 Observer 之後:

- **得到**:subject 只知道有多少 observer 註冊了自己,完全看不到具體的響應式行為是什麼,兩者徹底解耦;未來要擴充新的響應式行為時,無需進入 subject 類別修改,只要實作新的 observer 並註冊即可,符合開放封閉原則(OCP)。
- **代價**:Pull Model 下,每個 observer 仍然依賴 subject 才能取得資料,並沒有真正做到資料層面的解耦;Push Model 雖然讓 observer 徹底不需要反查 subject,但事前得想清楚該推送哪些欄位——推送的資料一旦無法滿足某些 observer 的需求,那些 observer 就只能退回去直接依賴 subject 取資料,等於部分放棄了 Push Model 原本想要的解耦效果。
