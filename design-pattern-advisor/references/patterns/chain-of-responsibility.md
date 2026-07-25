# Chain of Responsibility(責任鏈模式)

## Context

程式需要支援很多種不同的請求類型,每種請求只對應到一種處理行為,而且處理者的集合會持續增加。也就是說,系統一開始就不只一種「請求該由誰處理」的判斷邏輯,而且這份判斷邏輯注定會隨著時間持續長出新的分支。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **行為變動性(由少到多)**:請求種類會持續新增,而且處理各種請求的行為彼此不同——不是「理論上可能增加」,而是已經觀察到請求類型不斷長出來的軌跡。
- **獨立性與擴充性**:希望每種請求的處理都是一段獨立的程式,不同處理者之間互不影響、互不干擾,以取得更好的擴充性和維護性——新增一種處理者不該牽動到既有處理者的程式碼。
- **彈性的支援範圍**:系統未來可能支援新請求、也可能停止支援某些請求,希望能有彈性地決定目前這套系統要支援哪些請求類型,而不是把「支援哪些請求」寫死在單一個判斷式裡。

當「行為變動性」持續存在、而「獨立性」與「彈性」的訴求又跟現況(用一長串條件式集中判斷每種請求該怎麼處理)相衝突時,Chain of Responsibility 就是值得考慮的候選。

## Solution

核心手法是把「依序嘗試多個處理者、直到找到能處理該請求的那一個」這件事,轉換成一條由物件彼此串連而成的鏈:

1. **萃取抽象 Handler**:定義一個抽象類別(或介面),每個 Handler 都認識「下一位 Handler」——也就是持有一個指向同一種抽象型別的參考,這讓鏈上每一個節點的形狀完全一致。
2. **實作責任判斷 + 轉交邏輯**:每個 concrete handler 在處理請求時,先判斷這個請求是否隸屬於自己的責任範圍;是的話就自己處理掉,否則就把請求原封不動地轉交給「下一位」處理。
3. **依賴注入串鏈**:透過建構子注入(或 setter 注入),把多個 concrete handler 依序串成一條鏈,原本呼叫請求處理的那一方,從頭到尾只依賴鏈上的第一個 Handler,完全不需要知道鏈的長度、順序或成員。

以下用「採購請款的簽核流程」為例(依請款金額路由到不同層級的核准者,核准者集合未來會持續調整)——這是一個原創範例,與課程範例無關:

```
// Step 1 的產物:抽象 Handler,持有下一位 Handler 的參考
abstract class ApprovalHandler {
  protected next: ApprovalHandler | null = null

  setNext(next: ApprovalHandler): ApprovalHandler {
    this.next = next
    return next
  }

  approve(request: PurchaseRequest): ApprovalResult {
    if (this.canHandle(request)) {
      return this.doApprove(request)
    }
    if (this.next != null) {
      return this.next.approve(request)
    }
    throw new NoHandlerFoundError(request)
  }

  protected abstract canHandle(request: PurchaseRequest): boolean
  protected abstract doApprove(request: PurchaseRequest): ApprovalResult
}

// Step 2 的產物:三個 concrete handler,各自認得自己的責任範圍
class ManagerApprovalHandler extends ApprovalHandler {
  protected canHandle(request: PurchaseRequest): boolean {
    return request.amount <= 1000
  }

  protected doApprove(request: PurchaseRequest): ApprovalResult {
    // 部門主管權限內,直接核准
    return ApprovalResult.approvedBy("部門主管", request)
  }
}

class FinanceApprovalHandler extends ApprovalHandler {
  protected canHandle(request: PurchaseRequest): boolean {
    return request.amount <= 10000
  }

  protected doApprove(request: PurchaseRequest): ApprovalResult {
    // 財務主管權限內,直接核准
    return ApprovalResult.approvedBy("財務主管", request)
  }
}

class CfoApprovalHandler extends ApprovalHandler {
  protected canHandle(request: PurchaseRequest): boolean {
    // 鏈上最後一位,其餘一律由財務長處理
    return true
  }

  protected doApprove(request: PurchaseRequest): ApprovalResult {
    return ApprovalResult.approvedBy("財務長", request)
  }
}

// Step 3 的產物:透過依賴注入把三個 handler 串成一條鏈
managerHandler = new ManagerApprovalHandler()
financeHandler = new FinanceApprovalHandler()
cfoHandler = new CfoApprovalHandler()

managerHandler.setNext(financeHandler).setNext(cfoHandler)

// 原本的請款系統只依賴鏈的第一個 Handler
class PurchaseRequestService {
  constructor(private firstHandler: ApprovalHandler) {}

  submit(request: PurchaseRequest): ApprovalResult {
    return this.firstHandler.approve(request)
  }
}

service = new PurchaseRequestService(managerHandler)
result = service.submit(new PurchaseRequest(amount = 5000))
```

`PurchaseRequestService` 從頭到尾都不知道究竟是哪一層核准者處理了這筆請款,也看不到任何一個 handler 內部的判斷細節;未來如果要新增一個「超過十萬需董事會核准」的層級,只需要新增一個 `BoardApprovalHandler` 並串進鏈的尾端即可。

## Resulting Context

套用 Chain of Responsibility 之後:

- **得到**:發起請求的一方完全看不到究竟是哪個 handler 處理了請求,也看不到處理細節,兩者完全解耦;支援新的請求類型只要撰寫新的 handler 並串進鏈中,完全不用修改既有程式(符合開放封閉原則,OCP);不同 handler 之間彼此獨立,可以由不同工程師平行開發、互不干擾。
- **代價**:各個 concrete handler 之間常常存在重複的「判斷是否為自己責任範圍→處理/否則交給下一位」樣板程式碼,隨著 handler 數量增加,這份重複會越來越明顯,通常會再套用 Template Method 把這段固定流程萃取出來,消除重複。
