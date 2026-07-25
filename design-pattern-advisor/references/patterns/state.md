# State(狀態模式)

## Context

一個物件的行為在好幾個公開操作中都會依照「目前處於哪個狀態」而改變,而且各個操作的實作中充斥著判斷目前狀態的條件式。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **狀態明確、行為隨狀態而變**:物件有明確的多種狀態,而且同一個操作在不同狀態下會做出不同的事——這不是單一操作的分支,而是「一整組」操作都會依目前狀態改變行為。
- **條件式氾濫、破壞維護性**:為了讓行為隨狀態改變,許多公開操作的實作中都寫著大量判斷目前狀態的條件式,不好閱讀,破壞了維護性——而且這些條件式往往在多個操作裡重複出現,同一組「目前是什麼狀態」的判斷邏輯散落各處。
- **(有時)希望直接操控狀態**:除了讓狀態隨著操作自然轉移之外,有時還希望允許 client 直接改變物件的狀態,而不只是靠 driving 一連串操作間接到達某個狀態。

當「狀態明確、行為隨狀態而變」持續存在、而「條件式氾濫」已經拖累可讀性與維護性時,State 就是值得考慮的候選;如果還同時有「直接操控狀態」的需求,套用 State 會更加合適。

## Solution

核心手法分兩步:

1. **畫出狀態機圖**:先列舉出物件所有可能的狀態,以及每個狀態在收到哪個操作時,合法的轉移規則是什麼(以及哪些操作在該狀態下是不合法的)。
2. **把每個狀態封裝成一個類別**:讓每個狀態各自實作一個共同的 `State` 介面;物件本身(Context)不再自己判斷「目前是什麼狀態、該做什麼」,而是持有目前的 `State` 物件,把每個操作都委派給它去執行。狀態轉移時的 entry/exit 動作(例如進入某狀態時要初始化的欄位、離開某狀態前要檢查的條件)也封裝在對應的 state 類別中,由它負責維護該狀態下屬性的一致性。

以「訂單狀態生命週期」為例——訂單在「待付款 / 已付款 / 已出貨 / 已送達 / 已取消」之間轉移,各項操作(付款、出貨、取消)的行為都依目前狀態而不同:

```
// 狀態機圖(先列舉,再實作):
//   PendingPayment --pay()--> Paid
//   Paid --ship()--> Shipped
//   Shipped --(送達,系統事件)--> Delivered
//   PendingPayment / Paid --cancel()--> Cancelled
//   Shipped / Delivered / Cancelled 皆不可再 pay() / cancel()

// 共同介面
abstract class OrderState {
  abstract pay(order: Order): void
  abstract ship(order: Order): void
  abstract cancel(order: Order): void
}

// 每個狀態各自一個類別,只複寫在該狀態下合法的操作
class PendingPaymentState extends OrderState {
  pay(order: Order): void {
    order.setPaidAt(now())
    order.setState(new PaidState())
  }
  ship(order: Order): void {
    throw new IllegalStateTransition("訂單尚未付款,無法出貨")
  }
  cancel(order: Order): void {
    order.setState(new CancelledState())
  }
}

class PaidState extends OrderState {
  pay(order: Order): void {
    throw new IllegalStateTransition("訂單已付款,無法重複付款")
  }
  ship(order: Order): void {
    order.setShippedAt(now())
    order.setState(new ShippedState())
  }
  cancel(order: Order): void {
    // 已付款取消,進入退款流程
    order.setState(new CancelledState())
  }
}

class ShippedState extends OrderState {
  pay(order: Order): void {
    throw new IllegalStateTransition("訂單已出貨,無法付款")
  }
  ship(order: Order): void {
    throw new IllegalStateTransition("訂單已出貨,無法重複出貨")
  }
  cancel(order: Order): void {
    throw new IllegalStateTransition("訂單已出貨,無法取消")
  }
}

class DeliveredState extends OrderState {
  pay(order: Order): void {
    throw new IllegalStateTransition("訂單已送達,無法付款")
  }
  ship(order: Order): void {
    throw new IllegalStateTransition("訂單已送達,無法重複出貨")
  }
  cancel(order: Order): void {
    throw new IllegalStateTransition("訂單已送達,無法取消")
  }
}

class CancelledState extends OrderState {
  pay(order: Order): void {
    throw new IllegalStateTransition("訂單已取消,無法付款")
  }
  ship(order: Order): void {
    throw new IllegalStateTransition("訂單已取消,無法出貨")
  }
  cancel(order: Order): void {
    throw new IllegalStateTransition("訂單已取消,無法重複取消")
  }
}

// Order(Context)不再自己判斷狀態,而是持有目前的 state,把操作委派給它
class Order {
  private currentState: OrderState = new PendingPaymentState()

  pay(): void {
    this.currentState.pay(this)
  }
  ship(): void {
    this.currentState.ship(this)
  }
  cancel(): void {
    this.currentState.cancel(this)
  }

  setState(state: OrderState): void {
    this.currentState = state
  }
}
```

`Order` 本身完全不知道「待付款狀態不能出貨」這種規則,它只認得 `OrderState` 這個介面,每個公開操作都只是一行委派;新增一種狀態(例如未來要支援「退貨中」)只需要新增一個實作 `OrderState` 的類別,`Order` 本身不必修改。

## Resulting Context

套用 State 之後:

- **得到**:Context 類別的操作瘦身成單行委派,省去大量狀態判斷條件式;新增一種狀態只要新增一個類別,不用修改 Context(符合開放封閉原則,OCP);client 能直接透過切換 state 物件來改變 Context 的行為(或還原到某個狀態)。
- **代價**:狀態數量直接決定了類別數量,狀態一多,類別數目也隨之膨脹;維護「進入/離開某狀態時屬性必須符合什麼一致性規則」的邏輯被分散到各個 state 類別中,好處是每個狀態的規則各自獨立、互不干擾,但也要求開發者在每個 state 類別裡都謹慎維護這份一致性,否則規則容易在某個狀態類別中被遺漏。
