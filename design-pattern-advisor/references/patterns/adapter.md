# Adapter(轉接器模式)

## Context

Client 定義了一個表達自己意圖的介面,但實際能完成這個意圖的類別卻實作著另一個不相容的介面,而且不能(或不該)修改那個類別。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **意圖導向的介面**:client 依賴著自己根據意圖定義的介面——這個介面的形狀是從 client 的需求出發設計出來的,不是從某個現成類別的實作反推回去的。
- **不相容的既有實作**:真正有能力完成這件事的類別,實作的卻是另一個不相容的介面(方法名稱、參數型別、回傳型別、甚至例外型別都對不上),而且這個類別可能是第三方套件,未來會獨立於 client 演進,不能修改它。
- **不想被污染**:想要重複利用那個類別的能力,又不希望它的介面細節污染 client 定義好的介面——一旦 client 直接依賴那個不相容的介面,client 的程式碼就會被第三方的命名習慣、參數順序、例外型別綁死。

當「意圖導向的介面」與「不相容的既有實作」同時存在、而 client 又不想被那個實作的介面細節污染時,Adapter 就是值得考慮的候選。

## Solution

核心手法是宣告一個 Adapter 類別,實作 client 定義的目標介面(Target),內部持有(依賴注入或自行建立)那個不相容的類別(Adaptee),並在每個操作中把呼叫轉譯過去——包含參數型別、回傳型別,甚至例外型別的轉換。

以「簡訊發送」為例:系統內部已經定義好一個表達意圖的介面 `Notifier`,呼叫端只認得 `send(phone, message)`,失敗時預期收到 `NotificationFailedException`;但實際負責發送簡訊的是一個第三方簡訊服務 SDK `ThirdPartySmsSdk`,它的方法名稱、參數順序、例外型別都跟 `Notifier` 完全不同,而且是外部套件,不能修改它的原始碼。這時就宣告一個 `SmsNotifierAdapter`,實作 `Notifier`,內部持有 `ThirdPartySmsSdk` 的實例,把 `send()` 轉譯成該 SDK 期望的呼叫方式,並把 SDK 丟出的例外包裝成 `NotificationFailedException` 再拋出:

```
// Target:client 依照自己意圖定義的介面
interface Notifier {
  send(phone: string, message: string): void  // 失敗時丟出 NotificationFailedException
}

// Adaptee:第三方簡訊服務 SDK,介面不相容,且不能修改
class ThirdPartySmsSdk {
  dispatchMessage(recipientNumber: string, body: string, options: SmsOptions): SmsDispatchResult {
    // 內部呼叫第三方服務,失敗時丟出 SmsSdkException
  }
}

// Adapter:實作 Target,內部持有 Adaptee,負責轉譯呼叫
class SmsNotifierAdapter implements Notifier {
  private sdk: ThirdPartySmsSdk

  constructor(sdk: ThirdPartySmsSdk) {
    this.sdk = sdk
  }

  send(phone: string, message: string): void {
    try {
      // 把 Target 的呼叫方式轉譯成 Adaptee 期望的參數形狀
      this.sdk.dispatchMessage(phone, message, SmsOptions.default())
    } catch (e: SmsSdkException) {
      // 把 Adaptee 的例外型別轉譯成 Target 承諾的例外型別
      throw new NotificationFailedException(e.message)
    }
  }
}

// 呼叫端只依賴 Notifier,完全不知道背後是哪一個簡訊服務
notifier: Notifier = new SmsNotifierAdapter(new ThirdPartySmsSdk())
notifier.send("0912345678", "您的驗證碼是 123456")
```

呼叫端從頭到尾只依賴 `Notifier` 這個介面,完全不需要知道背後實際發送簡訊的是哪一套 SDK、也不需要理解它的參數形狀或例外設計。

## Resulting Context

套用 Adapter 之後:

- **得到**:client 完全不需要依賴那個不相容的介面或第三方套件,未來要更換簡訊供應商,只需要換一個新的 Adapter,client 程式碼完全不受影響;這正是依賴反轉原則(DIP)的具體實作方式——先以 client 的意圖定義介面,再讓低層次的實作去 adapt 這個介面。
- **代價**:Adapter 本身需要維護,一旦被轉接的介面(第三方 SDK)改版,轉接邏輯要跟著更新;多了一層轉接,追蹤呼叫流程時要多跳一層才能看到真正的實作。
