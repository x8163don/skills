# Builder(建造者模式)

## Context

一個物件的建構需要多個可選步驟,且步驟之間可能順序敏感。如果把所有欄位全部塞進同一個建構子,參數列會又長又難懂——呼叫端得記住每個位置對應哪個欄位,一旦傳錯順序也不容易被發現;而且並不是每次建構這個物件時,所有參數都是必要的,大部分呼叫端其實只需要設定其中幾個部分。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **可選性**:物件有多個可選的組成部分,不是每次建構都需要全部設定——今天這個呼叫端只在乎其中兩三個欄位,明天另一個呼叫端可能需要別的組合。
- **順序或相依性**:建構的過程本身帶有順序或相依關係,例如某個部分要先設定好,另一個部分才能正確組裝(例如要先有 body,才能正確設定對應的 content-type)。
- **可讀性與正確性**:直接用一個多參數的建構子(telescoping constructor,甚至為了應付不同參數組合而疊出一堆多載建構子)會讓呼叫端難以閱讀,也容易在一長串同型別參數中傳錯順序,而編譯器或型別系統通常抓不出這種錯誤。

當「可選性」與「順序相依」同時存在、而現況又是靠一個(或一疊)多參數建構子硬撐時,Builder 就是值得考慮的候選。

## Solution

核心手法是把逐步組裝的邏輯,從成品物件本身抽離出來,獨立成一個 Builder 類別:

1. **拆出 Builder**:新增一個獨立的 Builder 類別,負責一步一步組裝成品物件所需的各個部分。
2. **鏈式設定方法**:Builder 為每一個可選部分各自提供一個設定方法,每個方法只負責記錄那一個部分的值,並回傳 `this`,讓呼叫端可以鏈式(chained)串接多個設定呼叫,只設定自己在乎的部分。
3. **集中驗證與產出**:所有欄位之間的順序限制、預設值、必要條件檢查,都集中寫在 Builder 內部維護;最後呼叫一個 `build()` 方法,才真正組裝並產出成品物件。成品物件本身在建立之後維持不可變(immutable)——它沒有對外開放的 setter,一旦被 `build()` 出來,狀態就不會再被修改。

以「組裝一個 HTTP 請求物件」為例——這個物件有多個可選部分(headers、query params、body、認證資訊),而且部分欄位之間有設定順序的限制(例如必須先設定 body,才能設定對應的 content-type):

```
// 成品物件:建立之後不可變,沒有任何 setter
class HttpRequest {
  readonly url: string
  readonly headers: Map<string, string>
  readonly queryParams: Map<string, string>
  readonly body: string | null
  readonly authToken: string | null

  constructor(url, headers, queryParams, body, authToken) {
    this.url = url
    this.headers = headers
    this.queryParams = queryParams
    this.body = body
    this.authToken = authToken
  }
}

// Builder:逐步組裝,並集中處理順序限制與預設值
class HttpRequestBuilder {
  private url: string
  private headers: Map<string, string> = new Map()
  private queryParams: Map<string, string> = new Map()
  private body: string | null = null
  private authToken: string | null = null

  constructor(url: string) {
    this.url = url
  }

  withHeader(key: string, value: string): this {
    this.headers.set(key, value)
    return this
  }

  withQueryParam(key: string, value: string): this {
    this.queryParams.set(key, value)
    return this
  }

  withBody(content: string): this {
    // 必須先設定 body,之後才允許設定對應的 content-type
    this.body = content
    return this
  }

  withAuth(token: string): this {
    this.authToken = token
    return this
  }

  withContentType(contentType: string): this {
    if (this.body === null) {
      // 順序限制集中在 Builder 內部檢查,而不是留給呼叫端自己小心
      throw new Error("withContentType() 必須在 withBody() 之後呼叫")
    }
    this.headers.set("Content-Type", contentType)
    return this
  }

  build(): HttpRequest {
    return new HttpRequest(
      this.url,
      this.headers,
      this.queryParams,
      this.body,
      this.authToken
    )
  }
}

// 呼叫端只設定自己在乎的部分,鏈式串接、最後 build() 產出不可變物件
request = new HttpRequestBuilder("https://api.example.com/orders")
  .withHeader("Accept", "application/json")
  .withBody(JSON.stringify({ item: "book", qty: 1 }))
  .withContentType("application/json")
  .withAuth("Bearer xxx")
  .build()
```

呼叫端完全不需要知道 `HttpRequest` 建構子的參數順序,也不用被迫傳入不需要的欄位;順序限制(先 body 才能設 content-type)被封裝在 `HttpRequestBuilder` 內部,呼叫端寫錯順序會立刻在組裝階段被擋下來,而不是等到請求送出後才發現。

## Resulting Context

套用 Builder 之後:

- **得到**:建構過程變得可讀、可重用——呼叫端只需要設定自己在乎的部分,鏈式呼叫本身就是一份清楚的文件,說明這次到底設定了哪些欄位;建構的細節(順序驗證、預設值)被集中在 Builder 內部維護,不會散落在各個呼叫端各自重複檢查;成品物件保持不可變,一旦組裝完成就不用擔心狀態被意外修改。
- **代價**:多了一個 Builder 類別要維護,成品物件的每個欄位往往要在兩個地方(成品類別與 Builder 類別)各寫一次。如果物件只有兩三個必要參數、彼此之間也沒有順序限制,直接用建構子會更簡單直接——這時候套用 Builder 反而是過度設計,徒增一層間接而沒有換到對應的好處。
