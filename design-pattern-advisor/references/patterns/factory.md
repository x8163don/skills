# Factory(簡單工廠 Simple Factory)

## Context

程式中需要依某個條件(例如使用者偏好、設定值、輸入的型別標記)建立一個複雜物件族中的其中一種。這個物件族的成員彼此相關,但具體實作各不相同。「該建立哪一種物件、要傳哪些參數、要不要額外初始化」這些知識,目前散落在每一個呼叫 `new` 的地方,和「拿到物件之後要怎麼使用它」混在一起,沒有被集中管理。

## Forces

套用這個 pattern 之前,場景中通常同時存在以下幾股互相拉扯的力量:

- **物件族的存在**:存在一組相關但實作不同的類別(物件族),程式需要依條件選擇建立哪一種——不是單一固定的類別,而是要在多個候選之間做選擇。
- **建立知識不該重複**:建立這些物件的細節(建構子要傳哪些參數、建立後是否還要額外設定或初始化)如果散落在每個呼叫端,每個呼叫端就得各自知道、各自重複實作同一套邏輯,一旦某個建立步驟需要調整,就得回頭修改所有呼叫的地方。
- **對未來擴充的期待**:這個物件族未來可能會新增成員(例如新增一種通知管道、新增一種檔案格式的解析器),而工程師希望新增時只需要動一個地方,不必翻遍整個程式碼庫、修改所有呼叫 `new` 的位置。

當「物件族的選擇邏輯」與「該邏輯的建立細節」同時散落在多個呼叫端、且物件族有持續成長的可能時,這個 pattern 就是值得考慮的候選。

## Solution

核心手法是把「依條件建立哪一種物件」的邏輯,從呼叫端抽離出來,集中到一個獨立的工廠函式(或工廠類別)裡。呼叫端不再自己寫 `new` 加上型別判斷,只需要告訴工廠「我要什麼類型」,實際要 `new` 哪一個具體類別、要怎麼初始化,全部交由工廠內部決定並封裝起來。

以「依使用者通知偏好建立不同的 `Notification` 物件」為例——使用者可以選擇透過 Email、簡訊(SMS)或推播(Push)接收通知,呼叫端不該自己判斷型別再 `new` 對應的類別:

```
// 共同介面:所有通知管道都提供一致的 send 能力
interface Notification {
  send(message: string): void
}

// 每一種通知管道各自一個類別,封裝各自的建立與初始化細節
class EmailNotification implements Notification {
  private smtpClient: SmtpClient

  constructor(recipientEmail: string) {
    // 建立時需要準備好 SMTP 連線設定
    this.smtpClient = SmtpClient.connect(SMTP_CONFIG)
    this.recipientEmail = recipientEmail
  }

  send(message: string): void {
    this.smtpClient.sendMail(this.recipientEmail, message)
  }
}

class SmsNotification implements Notification {
  private smsGateway: SmsGateway

  constructor(phoneNumber: string) {
    // 建立時需要驗證電話號碼格式、準備簡訊閘道
    validatePhoneNumber(phoneNumber)
    this.smsGateway = SmsGateway.getInstance()
    this.phoneNumber = phoneNumber
  }

  send(message: string): void {
    this.smsGateway.sendText(this.phoneNumber, message)
  }
}

class PushNotification implements Notification {
  private deviceToken: string

  constructor(deviceToken: string) {
    // 建立時需要確認裝置 token 是否仍然有效
    this.deviceToken = ensureTokenValid(deviceToken)
  }

  send(message: string): void {
    PushService.push(this.deviceToken, message)
  }
}

// 工廠:集中「依偏好決定要建立哪一種物件」的知識
class NotificationFactory {
  create(preference: NotificationChannel, user: User): Notification {
    switch (preference) {
      case NotificationChannel.EMAIL:
        return new EmailNotification(user.email)
      case NotificationChannel.SMS:
        return new SmsNotification(user.phoneNumber)
      case NotificationChannel.PUSH:
        return new PushNotification(user.deviceToken)
      default:
        throw new UnsupportedChannelError(preference)
    }
  }
}

// 呼叫端只需要告訴工廠要什麼類型,不需要自己 new 並處理型別判斷
notification = notificationFactory.create(user.preference, user)
notification.send(message)
```

呼叫端從頭到尾不知道 `EmailNotification`、`SmsNotification`、`PushNotification` 各自的建構子要傳什麼參數、要做什麼額外初始化,它只需要呼叫 `notificationFactory.create(user.preference, user)`,拿到的就是一個可以直接 `send` 的 `Notification`。

這種「用一個 `switch`/`if` 集中判斷、依參數決定要建立哪一種物件」的做法,一般稱為「簡單工廠(Simple Factory)」。它和 GoF 的 Factory Method 不同:Factory Method 是由抽象 Creator 類別宣告一個工廠方法,再由不同的具體 Creator *子類別* override 該方法來決定產出哪一種產品——是「用哪個子類別」決定產物,而不是像這裡一樣靠一個執行期傳入的參數決定。如果你需要的是「依繼承的子類別而非參數來決定建立哪個產品」,這篇文件描述的並不是那個 pattern。

## Resulting Context

套用這個 pattern 之後:

- **得到**:建立物件的知識集中在工廠裡管理,呼叫端不需要知道每種通知類型的建構細節(要傳哪些參數、要不要額外初始化)。未來新增一種通知管道(例如站內訊息)時,只需要新增一個實作類別、並在工廠內部加一個分支——修改集中在一處,呼叫端程式碼完全不變。
- **代價**:多了一層工廠類別的間接性,想追蹤「這個物件到底是怎麼被建立出來的」時,得多跳一層去看工廠內部邏輯。如果這個物件族的成員數量固定、很少變動(例如就只會有一種通知管道,未來也不會擴充),套用這個 pattern 反而是過度設計——直接在呼叫端 `new` 更直白,沒有變動性支撐的抽象只是徒增間接層。
