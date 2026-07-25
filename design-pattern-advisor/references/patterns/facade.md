# Facade(門面模式)

## Context

Client 為了完成一個意圖,被迫認識並協調子系統中多個彼此依賴的介面。原本 client 只想表達一個單純的目的,卻必須逐一了解每個子系統介面的能力、呼叫順序、彼此之間的依賴關係,才能把這個目的實現出來。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **結構複雜度太高**:子系統中存在許多介面,而且這些介面彼此依賴——要完成一個意圖,往往不是呼叫單一介面就能了事,而是要按特定順序協調多個介面之間的互動。
- **Client 要求易用性**:client 被迫了解各個介面的能力、還要處理多個介面之間的協作,才能實現一個單純的意圖,學習門檻太高——每一個想使用這個子系統的 client,都得重新摸清楚這些介面該怎麼組合才不會出錯。

當「結構複雜度太高」持續存在、而 client 對「易用性」的訴求又跟現況(直接暴露一整組彼此依賴的子系統介面)相衝突時,Facade 就是值得考慮的候選。

## Solution

核心手法是設計一個 Facade 類別,把子系統的內部結構封裝起來,對外只暴露對應 client 意圖的操作,並指導 client 只依賴這個 Facade,不再直接接觸底下的子系統介面。

以「訂單結帳流程」為例——「結帳」這個意圖背後,其實需要協調庫存檢查、優惠券驗證、金流授權、發票開立等多個彼此依賴的子系統介面(例如必須先確認庫存足夠、驗證優惠券有效,才能進行金流授權,授權成功後才能開立發票):

```
// 子系統介面:各自負責結帳流程中的一個環節,彼此之間存在呼叫順序上的依賴
interface InventoryChecker {
  reserve(items: CartItem[]): ReservationResult
}

interface CouponValidator {
  validate(couponCode: string, cart: Cart): DiscountResult
}

interface PaymentGateway {
  authorize(amount: Money, paymentMethod: PaymentMethod): PaymentResult
}

interface InvoiceIssuer {
  issue(order: Order, payment: PaymentResult): Invoice
}

// Facade:封裝子系統的內部結構與呼叫順序,只對外暴露一個對應「結帳」意圖的操作
class CheckoutFacade {
  constructor(
    private inventoryChecker: InventoryChecker,
    private couponValidator: CouponValidator,
    private paymentGateway: PaymentGateway,
    private invoiceIssuer: InvoiceIssuer
  ) {}

  checkout(cart: Cart): Receipt {
    // 依序委派四個子系統介面,呼叫順序與彼此依賴關係都被封裝在這裡
    reservation = this.inventoryChecker.reserve(cart.items())
    discount = this.couponValidator.validate(cart.couponCode(), cart)
    payment = this.paymentGateway.authorize(cart.totalAfter(discount), cart.paymentMethod())
    invoice = this.invoiceIssuer.issue(cart.toOrder(reservation, discount), payment)

    return new Receipt(reservation, discount, payment, invoice)
  }
}

// Checkout 頁面的 client 端程式只需要依賴 CheckoutFacade,
// 不需要認識 InventoryChecker、CouponValidator、PaymentGateway、InvoiceIssuer 這四個介面
class CheckoutPage {
  constructor(private checkoutFacade: CheckoutFacade) {}

  onCheckoutButtonClicked(cart: Cart): void {
    receipt = this.checkoutFacade.checkout(cart)
    this.showReceipt(receipt)
  }
}
```

`CheckoutPage` 只認得 `CheckoutFacade.checkout(cart)` 這一個操作,完全不需要知道結帳背後牽涉了庫存、優惠券、金流、發票這四個子系統,也不需要知道它們之間該用什麼順序協作。

## Resulting Context

套用 Facade 之後:

- **得到**:client 的依賴介面數量從多個降到一個(或少數幾個),大幅提升易用性與開發生產力——新的 client(例如未來的行動端 App 或第三方整合)想要實現「結帳」這個意圖時,只需要學會呼叫 `CheckoutFacade`,不必重新摸清楚四個子系統之間的協作規則。
- **代價**:Facade 本身也是需要維護心力的類別;如果子系統的結構經常變動(結構變動性高),Facade 也得跟著頻繁修改——Facade 的維護成本與其內部結構變動的頻率成正比。如果子系統本身很穩定、很少變動,維護 Facade 的負擔就相對輕;但若子系統經常改版,Facade 就會變成一個需要持續同步更新的額外負擔。
