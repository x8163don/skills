# Command(指令模式)

## Context

程式中有一個類別暴露了多項操作,每項操作對應到一道指令,而 client 希望能在外部輕易改變「操作」與「指令」的綁定規則。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **綁死的分派邏輯**:client 透過某個操作(例如按下某個按鈕)來請求執行某道指令,但指令的執行邏輯目前寫死在 switch/case(或一長串 if/else)裡——負責分派的類別必須認識每一種具體的執行邏輯,才能決定該做什麼。
- **綁定規則的彈性需求**:想輕易地改變操作與指令的綁定規則(例如同一個按鈕在不同情境下要觸發不同指令),而且未來要支援新指令時要能遵守開放封閉原則(OCP)——新增一種指令不該迫使負責分派的類別跟著修改。
- **(加分情境)還原/重做的需求**:如果指令的執行過程都被封裝成物件而不是散落在條件式分支裡,就能輕易地把「已執行過的指令」記錄下來,進而實作還原(Undo)/重做(Redo)——這件事在邏輯寫死在 switch/case 裡時幾乎無從下手。

## Solution

核心手法是把「指令」本身升格成物件:把每一道指令(以及它實際要操作的接收者,即 Receiver)封裝進一個實作共同 `Command` 介面(至少要有 `execute()`)的物件裡;原本負責分派的類別(稱為 Invoker)不再需要認識任何 Receiver,它只認識 `Command` 這個介面,收到操作請求時呼叫對應 `Command` 物件的 `execute()` 即可——至於 `execute()` 內部實際找誰、做什麼,Invoker 完全不關心。

以「文字編輯器的工具列」為例——工具列上有多顆按鈕(粗體、斜體、插入圖片),每顆按鈕都要綁定一個編輯動作,且要能支援 Undo/Redo:

```
// Command 介面:所有具體指令都要實作
interface EditorCommand {
  execute(): void
}

// 具體指令:各自封裝自己要操作的 Receiver(Document)與執行邏輯
class BoldCommand implements EditorCommand {
  constructor(private document: Document, private selection: Range) {}

  execute(): void {
    this.document.applyStyle(this.selection, "bold")
  }
}

class ItalicCommand implements EditorCommand {
  constructor(private document: Document, private selection: Range) {}

  execute(): void {
    this.document.applyStyle(this.selection, "italic")
  }
}

class InsertImageCommand implements EditorCommand {
  constructor(private document: Document, private position: Position, private imageUrl: string) {}

  execute(): void {
    this.document.insertImage(this.position, this.imageUrl)
  }
}

// Invoker:只認識 Command 介面,不認識任何 Receiver(Document)
class Toolbar {
  private bindings: Map<string, EditorCommand> = new Map()

  bindButton(buttonId: string, command: EditorCommand): void {
    this.bindings.set(buttonId, command)
  }

  onButtonClicked(buttonId: string): void {
    const command = this.bindings.get(buttonId)
    command.execute()
  }
}

// 組裝:想改變按鈕與指令的綁定規則,只需要換一個 bindButton 的參數
toolbar = new Toolbar()
toolbar.bindButton("bold-button", new BoldCommand(document, currentSelection))
toolbar.bindButton("italic-button", new ItalicCommand(document, currentSelection))
toolbar.bindButton("insert-image-button", new InsertImageCommand(document, cursorPosition, chosenImageUrl))
```

若要進一步支援 Undo/Redo,只需要在 `Command` 介面上再加一個 `undo()`,並讓 Invoker 用兩個 Stack 記錄「已執行指令」與「已復原指令」:

```
interface EditorCommand {
  execute(): void
  undo(): void
}

class BoldCommand implements EditorCommand {
  constructor(private document: Document, private selection: Range) {}

  execute(): void {
    this.document.applyStyle(this.selection, "bold")
  }

  undo(): void {
    this.document.removeStyle(this.selection, "bold")
  }
}

class Toolbar {
  private bindings: Map<string, EditorCommand> = new Map()
  private executedStack: EditorCommand[] = []
  private undoneStack: EditorCommand[] = []

  bindButton(buttonId: string, command: EditorCommand): void {
    this.bindings.set(buttonId, command)
  }

  onButtonClicked(buttonId: string): void {
    const command = this.bindings.get(buttonId)
    command.execute()
    this.executedStack.push(command)
    this.undoneStack = [] // 一旦有新指令執行,重做歷史就失效
  }

  undo(): void {
    const command = this.executedStack.pop()
    if (command == null) return
    command.undo()
    this.undoneStack.push(command)
  }

  redo(): void {
    const command = this.undoneStack.pop()
    if (command == null) return
    command.execute()
    this.executedStack.push(command)
  }
}
```

`Toolbar` 從頭到尾都不知道「粗體」「斜體」「插入圖片」實際上是怎麼做到的,它只認得 `EditorCommand` 這個介面;要新增一種指令(例如未來要支援「插入表格」),只需要新增一個實作類別並呼叫 `bindButton`,`Toolbar` 本身完全不用修改。

## Resulting Context

套用 Command 之後:

- **得到**:Invoker 與 Receiver 之間完全解耦,Invoker 只懂得下達指令,不知道也不在乎指令實際上怎麼執行;新增或刪除指令時無需修改 Invoker(符合開放封閉原則,OCP);每道指令的執行邏輯被封裝成獨立、可以單獨測試與除錯的類別;副作用是因為執行邏輯已經物件化,很容易在此基礎上加上 Undo/Redo。
- **代價**:指令的種類越多,`Command` 的具體實作類別數量就越多,系統整體的類別數目會隨之增加。不過因為每個具體指令類別通常都很小、職責單一(只封裝一道指令的執行邏輯),這通常不是問題;如果指令的種類固定且極少、也確定未來不會再擴充,直接在 Invoker 裡用簡單的條件式處理可能反而更直接。
