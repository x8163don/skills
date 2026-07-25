# Template Method(樣板方法模式)

## Context

程式中有一組類似的行為(演算法/流程),彼此高度相似——步驟數量、執行順序幾乎一致,但撰寫時卻被迫用「複製貼上再修改」的方式來實作每一個變種:先把既有的一份程式碼整份複製過來,再挑出幾行改成新的邏輯。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **重複性**:這組類似的行為導致撰寫者寫出大量重複的程式碼——每一個變種都各自重複著同一套流程骨架。
- **局部變動性**:但這些重複的程式碼之中,又有一小部分彼此不同。整個流程並非全部都會變,只有其中某一小步驟依情境而異。
- **擴充與維護的代價**:每當要開發一種新的類似行為時,開發者被迫用複製貼上再改寫的方式實作。這樣做在擴充上很吃力——新增一種變種要重新複製一整套流程；也不好維護——流程骨架若要修正一個共通的錯誤或調整順序,必須回頭改動每一份複製出來的程式碼,很容易漏改。

當「重複性」與「局部變動性」同時存在——也就是流程大部分固定、只有少數步驟因情境而異——而現況又是用複製貼上因應這個變動時,Template Method 就是值得考慮的候選。

## Solution

核心手法是:辨識出這組行為之中「重複/不變的部分」與「會變的部分」,把不變的部分提取成一個抽象類別上的「樣板方法」(template method),由這個方法固定住整體的呼叫順序;把會變的部分萃取成抽象方法(代表流程中的某個步驟),交給子類別各自複寫。

以「批次匯入」為例——系統中有多個資料來源的匯入工作,每個匯入工作都遵循同一套流程:「讀檔 → 逐列解析 → 驗證 → 寫入資料庫」,其中只有「逐列解析」這一步會依來源格式(CSV / 固定寬度文字檔)而不同,其餘步驟在所有來源之間都是共用的:

```
// 抽象類別:固定流程順序、共用步驟的實作都放在這裡
abstract class ImportJob {
  // 樣板方法:定義好整體執行順序,不允許子類別更動這個順序
  run(filePath: string): void {
    lines = this.readFile(filePath)
    for (line of lines) {
      record = this.parseRow(line)   // 唯一因來源格式而異的步驟,交給子類別
      this.validate(record)
      this.save(record)
    }
  }

  // 具體方法,所有子類別共用,不需要、也不允許複寫
  private readFile(filePath: string): string[] {
    return FileReader.readAllLines(filePath)
  }

  // 抽象方法:每一列文字要怎麼解析成 Record,由子類別決定
  protected abstract parseRow(line: string): Record

  // 具體方法,驗證規則對所有來源一致,所有子類別共用
  private validate(record: Record): void {
    if (!record.isValid()) {
      throw new InvalidRecordError(record)
    }
  }

  // 具體方法,寫入邏輯對所有來源一致,所有子類別共用
  private save(record: Record): void {
    Database.insert(record)
  }
}

// 子類別只需要複寫 parseRow,其餘流程完全繼承不變
class CsvImportJob extends ImportJob {
  protected parseRow(line: string): Record {
    fields = line.split(",")
    return Record.fromFields(fields)
  }
}

class FixedWidthImportJob extends ImportJob {
  protected parseRow(line: string): Record {
    // 固定寬度格式:依欄位寬度切割,而非用分隔符號
    fields = FixedWidthParser.splitByColumnWidths(line, COLUMN_WIDTHS)
    return Record.fromFields(fields)
  }
}

// 呼叫端只需要選擇要用哪一種匯入工作,流程本身不必重新理解
job = new CsvImportJob()
job.run("orders.csv")
```

`ImportJob` 的 `run()` 方法固定了「讀檔 → 逐列解析 → 驗證 → 寫入」這個順序,子類別完全不需要、也無法更動這個順序,只能透過複寫 `parseRow()` 來提供自己那一種格式的解析邏輯。

## Resulting Context

套用 Template Method 之後:

- **得到**:原本重複的程式碼(讀檔、驗證、寫入)被提取到樣板方法所在的抽象類別中,只需要維護一次;子類別的實作內容只剩下真正變動的部分,新增一種來源格式(例如未來要支援 JSON 匯入)只需要新增一個子類別、撰寫一個 `parseRow` 複寫即可,非常輕鬆,不必再複製整套流程。
- **代價**:這個模式的作用範圍被限制在單一方法內,而且是透過繼承關係綁死的——子類別在編譯期就決定了要用哪一種變動步驟的實作,無法在執行期動態抽換。如果未來需求變成「同一個匯入工作要能在執行期切換不同的解析邏輯」(而不只是用不同子類別在編譯期決定),就必須考慮改用、或搭配 Strategy 來取得執行期抽換的彈性。
