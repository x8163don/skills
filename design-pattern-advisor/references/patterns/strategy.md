# Strategy(策略模式)

## Context

程式中存在一個動作,它的具體行為會依照某個「類型」欄位而分支——最常見的寫法就是一長串 `if/else` 或 `switch` 依 type 判斷該執行哪一種邏輯。這種類型欄位不是靜態不變的,而是會隨著業務發展持續增加新的分支。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **行為變動性**:這個動作目前已經有多種不同的實作方式並存,而且可以預期未來還會持續新增更多變種——不是「理論上可能」,而是已經觀察到變動的軌跡。
- **擴充性**:呼叫端(client)希望能夠簡單地抽換或擴充某一種行為,而不必為此鑽進既有類別內部去修改程式碼——修改既有、已經在運作的類別,本身就帶有風險。
- **維護性**:目前這些不同實作方式的細節全部寫在同一個類別裡,單一類別因此曝露了過多的實作細節,拖累了這個類別的可讀性,也讓「新增一種變種」跟「維護既有變種」這兩件事互相干擾。

當「行為變動性」持續存在、而「擴充性」與「維護性」的訴求又跟現況(全部塞在同一個類別裡用條件式分支)相衝突時,Strategy 就是值得考慮的候選。

## Solution

核心手法是「依賴反轉之重構三步驟」:

1. **封裝變動之處**:把每一種行為變種,各自獨立成一個類別,讓每個類別只專注實作自己那一種演算法。
2. **萃取共同行為**:觀察這些變種類別對外提供的能力其實是一致的(同樣的輸入、同樣形狀的輸出),把這個共同能力萃取成一個介面。
3. **委派**:原本混雜了所有變種邏輯的類別,不再自己實作這些行為,而是改成持有這個介面的參考,把實際運算委派給它;至於要使用哪一個具體變種,則透過依賴注入(建構子注入或 setter 注入)由外部決定,原本的類別完全不需要知道有哪些變種存在。

以下用「電商訂單的運費計算」為例——同一個「計算運費」動作,依運送方式(郵局掛號 / 宅配 / 超商取貨)而有完全不同的計算邏輯:

```
// Step 2 的產物:萃取出的共同介面
interface ShippingFeeStrategy {
  calculate(order: Order): Money
}

// Step 1 的產物:每種運送方式各自一個類別,各自封裝自己的計算細節
class RegisteredMailFee implements ShippingFeeStrategy {
  calculate(order: Order): Money {
    // 依重量、掛號附加費計算郵局掛號運費
    weight = order.totalWeight()
    return baseRateByWeight(weight) + REGISTERED_SURCHARGE
  }
}

class HomeDeliveryFee implements ShippingFeeStrategy {
  calculate(order: Order): Money {
    // 依重量、配送區域計算宅配運費
    weight = order.totalWeight()
    zone = resolveZone(order.deliveryAddress())
    return baseRateByWeight(weight) * zoneFactor(zone)
  }
}

class ConvenienceStorePickupFee implements ShippingFeeStrategy {
  calculate(order: Order): Money {
    // 超商取貨通常是固定費率,可能因訂單金額而有免運門檻
    if (order.subtotal() >= FREE_SHIPPING_THRESHOLD) {
      return Money.zero()
    }
    return FLAT_PICKUP_FEE
  }
}

// Step 3 的產物:Order 不再自己判斷運送方式,而是委派給注入進來的 strategy
class Order {
  private shippingFeeStrategy: ShippingFeeStrategy

  constructor(shippingFeeStrategy: ShippingFeeStrategy) {
    this.shippingFeeStrategy = shippingFeeStrategy
  }

  // 也可以提供 setter,讓呼叫端在建立後仍能抽換運送方式
  setShippingFeeStrategy(strategy: ShippingFeeStrategy): void {
    this.shippingFeeStrategy = strategy
  }

  calculateShippingFee(): Money {
    return this.shippingFeeStrategy.calculate(this)
  }
}

// 呼叫端依使用者選的運送方式,決定注入哪一個具體變種
order = new Order(new HomeDeliveryFee())
fee = order.calculateShippingFee()
```

`Order` 從頭到尾都不知道運費是怎麼算出來的,它只認得 `ShippingFeeStrategy` 這個介面;新增一種運送方式(例如未來要支援「冷凍宅配」)只需要新增一個實作類別,`Order` 本身完全不用修改。

## Resulting Context

套用 Strategy 之後:

- **得到**:呼叫端可以自由抽換或擴充某一種運費計算方式,新增一種運送方式只需要新增一個類別、不必修改既有程式碼(符合開放封閉原則,OCP);每個運費演算法的實作細節都被封裝進各自的類別裡,工程師修改某一種運費邏輯時,只需要專注在單一類別,不會影響其他變種。
- **代價**:類別數量會隨著變種數量增加而增加,系統整體的類別數目變多、追蹤流程時要多跳幾層。如果運送方式永遠只會有一種、也確定未來不會再變,套用 Strategy 反而是過度設計——直接把邏輯寫在方法裡更簡單直接,沒有變動性支撐的抽象只是徒增間接層。
