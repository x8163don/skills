# Composite(複合模式)

## Context

Client 需要用一致的方式操作一組物件,而這組物件組成一棵樹——這是一種遞迴的部分-整體階層(part-whole hierarchy):樹中某些物件是「容器」,包含著同一抽象類型的子物件;某些物件則是「葉節點」,不再往下延伸。Client 想對這棵樹做某件事(例如統計、計算大小),但不想被迫先分辨自己拿到的究竟是單一葉節點還是整棵子樹。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **結構複雜度高**:結構中存在遞迴關聯(self-association)——容器可以包含容器,讓整個結構能夠無限延伸、長成任意深度的樹。
- **結構變動性**:樹中節點的具體種類未來可能增加,例如新增一種容器類型或一種葉節點類型;結構本身不是一次定型、往後不再變動的。
- **一致操作的訴求**:Client 想在完成自己的意圖時(例如計算大小、統計數量)不必在乎自己面對的是單一葉節點還是整棵子樹;容器類別的實作也不希望為每一種子節點型別各寫一套分支邏輯來處理不同種類的子物件。

當這棵樹的結構複雜、還可能持續變動,而 client 與容器類別又都不想被迫感知子節點的具體型別時,Composite 就是值得考慮的候選。

## Solution

核心手法是萃取一個抽象的 Component 型別,同時代表葉節點與容器這兩種角色。容器持有一份 Component 型別的子節點清單(而不是按照子節點的具體型別分開維護好幾份清單),並透過對每個子節點遞迴呼叫同一個操作來實作自己的操作;client 全程只依賴這個 Component 型別,不需要知道底下實際上是葉節點還是容器。

以「電商商品分類樹」為例(`Category` 可以包含子分類與商品,要計算某個分類底下含所有子分類的商品總數):

```
// 抽象的 Component,葉節點與容器都實作這個介面
abstract class CatalogItem {
  abstract countProducts(): int
}

// 葉節點:單一商品,本身就是「1 個商品」
class Product extends CatalogItem {
  countProducts(): int {
    return 1
  }
}

// 容器:分類,持有一份 Component 型別的子節點清單
class Category extends CatalogItem {
  private children: List<CatalogItem> = []

  addChild(item: CatalogItem): void {
    this.children.push(item)
  }

  countProducts(): int {
    // 對每個子節點遞迴呼叫同一個操作,不必分辨子節點是 Product 還是 Category
    total = 0
    for (child of this.children) {
      total += child.countProducts()
    }
    return total
  }
}

// Client:只依賴 CatalogItem,不必知道自己拿到的是單一商品還是整棵分類子樹
class StorefrontPage {
  render(item: CatalogItem): void {
    productCount = item.countProducts()
    display(`此分類共有 ${productCount} 項商品`)
  }
}

// 組出一棵任意深度的分類樹
electronics = new Category()
electronics.addChild(new Product())
electronics.addChild(new Product())

phones = new Category()
phones.addChild(new Product())
electronics.addChild(phones)  // 容器裡還可以再放容器

page = new StorefrontPage()
page.render(electronics)  // 傳入整棵子樹,或傳入單一 Product,呼叫端完全不用改
```

`StorefrontPage` 只呼叫某個 `CatalogItem.countProducts()`,完全不需要知道自己拿到的是單一商品還是整棵分類子樹;`Category.countProducts()` 也不需要為「子節點是 Product 還是 Category」寫任何分支邏輯,遞迴呼叫自然處理了樹的深度。

## Resulting Context

套用 Composite 之後:

- **得到**:client 變得對結構無感(structure-agnostic)——完全不必知道自己面對的是葉節點還是整棵子樹,也不必因為結構變動(樹變深、變廣)而修改自己的程式碼;新增一種節點型別(例如未來要新增「促銷組合」這種特殊容器)不需要修改 client 或既有的容器類別,符合開放封閉原則(OCP);容器類別也不再需要為不同子節點型別各寫一份重複邏輯,遞迴呼叫同一個介面就足夠。
- **代價**:「透明度」與「操作安全性」這兩股力量會互相衝突。「透明度」指的是把所有操作(包含只有容器才有意義的操作,例如 `addChild()`)都放進共用的 Component 介面,讓葉節點與容器操作起來完全一致、client 完全不用區分兩者;但如果真的把 `addChild()` 放進 Component,葉節點(例如 `Product`)就必須為這個它本來就不支援的操作丟出執行期例外,操作安全性因此打了折扣。這兩股力量沒有標準答案,必須根據實際情境的 client 需求權衡,選擇影響較大的那道 force 優先解決。
