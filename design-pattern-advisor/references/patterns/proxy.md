# Proxy(代理人模式)

## Context

Client 依賴一個介面,而實際實作該介面的物件建立成本很高、需要存取控管,或需要透過某種通訊協定才能取得。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **既有依賴**:Client 已經依賴著實作該介面的實體,程式碼是圍繞這個介面寫成的。
- **控管需求**:想要控制 client 對這個實體的存取——可能是延遲建立(建立成本很高、想等到真正需要時才建立)、限制操作範圍(權限管控),或是透過網路才能取得(遠端存取)——但不能修改這個實體既有的程式碼,因為它可能是別人維護的,或者不想去碰動它。
- **透明性**:想要不改變 client 使用介面的方式,悄悄地把這些控制行為加上去,client 完全不需要感知到背後多了一層控管。

當「既有依賴」與「控管需求」同時存在、而「透明性」又要求不能驚動 client 現有用法時,Proxy 就是值得考慮的候選。

## Solution

核心手法是:宣告一個 Proxy 類別,實作 client 依賴的同一個介面;client 改成依賴這個 Proxy;Proxy 內部持有(或延遲建立)真正的實體,並在每一個操作中把呼叫轉發給它,同時可以在轉發前後疊加額外行為(例如延遲建立、權限檢查、快取或記錄)。

以「相簿應用程式的高解析度圖片載入」為例——相簿列表只需要顯示縮圖,但使用者點擊放大檢視時才需要載入昂貴的原始高解析度圖檔:

```
// Client 依賴的介面
interface ImageProvider {
  getPixels(): Bitmap
}

// 真正的實體:建立成本很高(需要向遠端下載原始檔案並解碼)
class HighResImage implements ImageProvider {
  private url: string

  constructor(url: string) {
    this.url = url
    // 建構時就會發生昂貴的下載與解碼動作
    this.downloadAndDecode(url)
  }

  getPixels(): Bitmap {
    return this.decodedBitmap
  }
}

// Proxy:實作同一個介面,對 client 完全透明
class RemoteImageProxy implements ImageProvider {
  private url: string
  private realImage: HighResImage | null = null

  constructor(url: string) {
    this.url = url
    // 注意:建構時「不」建立 HighResImage,只記住 url
  }

  getPixels(): Bitmap {
    if (this.realImage === null) {
      // 只有在真的被呼叫時,才真正建立昂貴的實體
      this.realImage = new HighResImage(this.url)
    }
    return this.realImage.getPixels()
  }
}

// Client 端:改成依賴 Proxy,但寫法跟原本依賴 ImageProvider 時完全一樣
class PhotoAlbumView {
  private imageProvider: ImageProvider

  constructor(imageProvider: ImageProvider) {
    this.imageProvider = imageProvider
  }

  onThumbnailZoomed(): Bitmap {
    // 呼叫端不知道、也不需要知道背後是 Proxy 還是真正的 HighResImage
    return this.imageProvider.getPixels()
  }
}

// 相簿列表建立每張照片時,一律先建立 Proxy,而不是立刻建立昂貴的 HighResImage
view = new PhotoAlbumView(new RemoteImageProxy(photoUrl))
```

`PhotoAlbumView` 從頭到尾都只認得 `ImageProvider` 這個介面,完全不知道自己實際上拿到的是 `RemoteImageProxy`。相簿列表可以一次建立成千上百個 `RemoteImageProxy`,不會因此觸發大量高解析圖檔的下載,只有當使用者真的把某張縮圖放大檢視、呼叫到 `getPixels()` 時,對應的原始檔案才會被下載與實體化。

## Resulting Context

套用 Proxy 之後:

- **得到**:Proxy 可以在 client 完全不知情的狀況下,在存取真正物件之前加上延遲載入、權限控管、監控或快取等行為;真正的物件甚至不需要一開始就存在,也不必和 client 在同一個記憶體空間中(Remote Proxy)。
- **代價**:多了一個 Proxy 類別要維護。如果把 Proxy 改成能代理「任何實作該介面的類別」而非固定代理某個具體類別,雖然更彈性,但會失去延遲建立的能力——因為 Proxy 不再知道要建立哪一個具體型別。
