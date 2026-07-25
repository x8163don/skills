# Decorator(裝飾器模式)

## Context

需要在不修改既有類別的前提下,為某個物件疊加額外行為,而且這些額外行為要能自由組合、任意搭配——不是只有一種固定的包裝方式,而是依情境不同,今天可能只需要其中一種行為,明天可能需要好幾種行為疊在一起。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **基礎行為與額外行為並存**:已經有一個基礎行為(例如呼叫外部 API 取資料),但不同情境下還需要在這個基礎行為之上疊加不同的額外行為,例如快取、重試、記錄 log。
- **組合是動態且多變的**:這些額外行為要怎麼搭配,並非固定不變——有時只需要快取,有時快取跟重試都要,未來也可能再加上記錄 log 或其他橫切行為。如果改用繼承的方式,為每一種可能的組合各寫一個子類別(`CachingApiDataFetcher`、`RetryingApiDataFetcher`、`CachingRetryingApiDataFetcher`……),子類別數量會隨著行為種類呈組合爆炸,而且每新增一種行為就要重新排列組合一次。
- **不想動到基礎類別**:基礎行為本身的程式碼已經穩定運作,不希望為了疊加這些橫切行為而去修改它、也不希望讓基礎類別背負它原本不該關心的職責。

當「額外行為需要動態、自由組合」與「不想用繼承窮舉每種組合、也不想改動基礎類別」這兩股力量同時存在時,Decorator 就是值得考慮的候選。

## Solution

核心手法是讓 Decorator 與被包裝的物件實作同一個介面,Decorator 內部持有一個該介面的實體——這個實體可能是最原始的物件,也可能是另一個 Decorator。呼叫 Decorator 時,它會在把呼叫轉發給內部持有的物件之前、或之後,加上自己那一份額外行為。因為 Decorator 對外呈現的介面跟它包裝的物件完全一樣,所以 Decorator 可以再被另一個 Decorator 包裝,如此層層疊加、任意組合,想要哪些行為就疊加哪些 Decorator,順序也可以自由調整。

以「資料抓取」為例——基礎行為是呼叫外部 API 取得資料,額外需要的橫切行為則是快取與重試:

```
// 共同介面:所有 Decorator 與基礎實作都遵循同一份 API
interface DataFetcher {
  fetch(id: string): Data
}

// 基礎實作:實際呼叫外部 API 取資料,不知道自己會不會被包裝
class ApiDataFetcher implements DataFetcher {
  fetch(id: string): Data {
    return httpClient.get(`/data/${id}`)
  }
}

// Decorator 1:快取。持有一個 DataFetcher,fetch() 前先查快取,
// 沒命中才轉發給內部的 fetcher,並把結果存入快取
class CachingDataFetcher implements DataFetcher {
  private inner: DataFetcher
  private cache: Map<string, Data>

  constructor(inner: DataFetcher) {
    this.inner = inner
    this.cache = new Map()
  }

  fetch(id: string): Data {
    if (this.cache.has(id)) {
      return this.cache.get(id)
    }
    data = this.inner.fetch(id)
    this.cache.set(id, data)
    return data
  }
}

// Decorator 2:重試。持有一個 DataFetcher,fetch() 失敗時重試數次,
// 全部失敗才把最後一次的錯誤往外拋
class RetryingDataFetcher implements DataFetcher {
  private inner: DataFetcher
  private maxAttempts: number

  constructor(inner: DataFetcher, maxAttempts: number = 3) {
    this.inner = inner
    this.maxAttempts = maxAttempts
  }

  fetch(id: string): Data {
    lastError = null
    for (attempt = 1; attempt <= this.maxAttempts; attempt++) {
      try {
        return this.inner.fetch(id)
      } catch (error) {
        lastError = error
      }
    }
    throw lastError
  }
}

// 呼叫端依情境自由組合:先快取、再重試,層層疊加
fetcher: DataFetcher = new RetryingDataFetcher(new CachingDataFetcher(new ApiDataFetcher()))
data = fetcher.fetch("123")

// 情境不同時,也可以只要其中一種行為,或調換疊加順序
cachedOnly: DataFetcher = new CachingDataFetcher(new ApiDataFetcher())
retryThenCache: DataFetcher = new CachingDataFetcher(new RetryingDataFetcher(new ApiDataFetcher()))
```

呼叫端只認得 `DataFetcher` 這個介面,完全不需要知道眼前這個物件到底是原始的 `ApiDataFetcher`,還是包了幾層 Decorator 之後的結果;`ApiDataFetcher` 本身也完全不知道自己被包裝了。想要新增一種橫切行為(例如記錄 log),只需要再寫一個 `LoggingDataFetcher implements DataFetcher`,同樣持有一個 `DataFetcher`,不必動到既有的任何類別。

## Resulting Context

套用 Decorator 之後:

- **得到**:額外行為可以用組合(composition)取代繼承來疊加,依情境自由搭配,不需要為每一種可能的組合各寫一個子類別。新增一種橫切行為只需要新增一個 Decorator 類別,不會影響既有的基礎類別、也不會影響其他 Decorator,符合開放封閉原則。
- **代價**:疊加的 Decorator 層數一多,呼叫堆疊會變深,一次 `fetch()` 呼叫實際上會穿過好幾層物件,除錯時得一層一層追蹤,可讀性因此下降。如果實際上只會用到一兩種固定的行為組合、未來也不太可能再變化,直接把邏輯寫死在一個類別裡反而更直觀,不需要為了尚未出現的彈性需求而引入 Decorator 帶來的間接層。
