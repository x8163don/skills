# 決策表：購物車免運門檻 × 全店現折 × 折扣碼 × VIP 免運券

系統條件：
- **條件 A（基本免運門檻）**：小計滿 $1,500（含）以上免運（原運費 $60）
- **條件 B（全店滿額現折）**：小計滿 $3,000（含）以上，自動現折 $300，與條件 D 互斥
- **條件 C（折扣碼 SUMMER90）**：結帳輸入序號，商品小計打 9 折
- **條件 D（VIP 免運券 VIPFREE）**：結帳輸入序號，直接免運，不受 $1,500 門檻限制；與條件 C 互斥（同一輸入框）、與條件 B 互斥（B 觸發時系統禁止 D）

計算順序：Subtotal → 套用 B（現折）→ 套用 C（9 折，四捨五入至整數）→ 判斷運費（A 或 D）→ Total = 折扣後金額 + 運費

## 測試檔案對應規則

編號採用 **Use Case（行為動詞片語）+ 序號**，而不是流水號或抽象代碼。編號前綴即為對應的測試檔名（去掉副檔名），兩者永遠同步，不需要額外維護對照表：

```
tests/checkout-shipping-discount/
  apply-free-shipping-threshold.spec.ts        # apply-free-shipping-threshold-01/02/03
  apply-full-store-discount.spec.ts             # apply-full-store-discount-01/02
  redeem-discount-code.spec.ts                   # redeem-discount-code-01/02
  stack-store-discount-with-code.spec.ts         # stack-store-discount-with-code-01
  redeem-vip-free-shipping-code.spec.ts          # redeem-vip-free-shipping-code-01/02
  enforce-vip-conflict-with-store-discount.spec.ts # enforce-vip-conflict-with-store-discount-01/02
  enforce-code-mutual-exclusivity.spec.ts        # enforce-code-mutual-exclusivity-01
```

測試標題直接寫上完整編號，方便 `grep -r "apply-free-shipping-threshold-02"` 同時定位到決策表列與測試案例：

```ts
it('[apply-free-shipping-threshold-02] 小計為 0 -> 運費 $60', () => { ... })
```

日後若真的拆出對應的 Application Service／UseCase 類別（例如 `ApplyFreeShippingThresholdUseCase`），檔名可以直接對應類別名稱，不需要重新命名測試案例編號。

---

## 決策表 1：免運門檻（A）× 現折（B）× 折扣碼 9 折（C）疊加與計算順序

| 編號 | 說明 | 重要性 | 商品小計金額 | 折扣碼輸入 | B 是否觸發 | C 是否套用 | 折扣後商品金額 | 運費 | Total |
|---|---|---|---|---|---|---|---|---|---|
| apply-free-shipping-threshold-01 | 未達任何門檻的基本情境 | 基本 happy path | 1000 | 無 | 否 | 否 | 1000 | $60 | 1060 |
| apply-free-shipping-threshold-02 | 空值/零元邊界 | 防禦性測試，避免除以零/負數等異常 | 0 | 無 | 否 | 否 | 0 | $60 | 60 |
| apply-free-shipping-threshold-03 | 恰好達 A 門檻 | 邊界值，驗證 `>=` 而非 `>` | 1500 | 無 | 否 | 否 | 1500 | $0 | 1500 |
| apply-full-store-discount-01 | 剛好低於 B 門檻 | 確認 2999 與 3000 的行為差異，防止差一元誤判 | 2999 | 無 | 否 | 否 | 2999 | $0 | 2999 |
| apply-full-store-discount-02 | 恰好達 B 門檻，B 自動觸發後仍自然滿足 A | 高：驗證 B 觸發後其實是靠 A 免運，不是巧合 | 3000 | 無 | 是 | 否 | 3000-300=2700 | $0 | 2700 |
| redeem-discount-code-01 | 驗證 A 門檻判斷用的是「折扣後」金額，不是原始小計 | 極高風險：若實作誤用原始金額判斷門檻，會給出錯誤的免運資格 | 1600 | SUMMER90 | 否 | 是 | 1600×0.9=1440 | $60 | 1500 |
| redeem-discount-code-02 | 原始金額剛好等於 A 門檻，套用 C 後卻跌破 | 極高風險：原始金額剛好等於門檻，最容易被誤判 | 1500 | SUMMER90 | 否 | 是 | 1500×0.9=1350 | $60 | 1410 |
| stack-store-discount-with-code-01 | B+C 疊加，且落在 .5 的四捨五入邊界 | 高：驗證計算順序「先減 $300 再打 9 折」，且驗證四捨五入規則 | 3015 | SUMMER90 | 是 | 是 | (3015-300)×0.9=2443.5→2444 | $0 | 2444 |

## 決策表 2：VIP 免運券（D）與互斥規則（B vs D、C vs D）

| 編號 | 說明 | 重要性 | 商品小計金額 | 折扣碼輸入 | B 是否觸發 | D 是否被允許生效 | 系統回應（待確認） | 折扣後商品金額 | 運費 | Total |
|---|---|---|---|---|---|---|---|---|---|---|
| redeem-vip-free-shipping-code-01 | 驗證 D 的免運資格不依賴金額門檻 | 高：D 存在的核心價值，若失效等同 D 功能形同虛設 | 1000 | VIPFREE | 否 | 是 | 正常套用 | 1000 | $0 | 1000 |
| redeem-vip-free-shipping-code-02 | 驗證 B/D 互斥的邊界精確性：2999 元時 B 未觸發，D 不該被提前禁用 | 高：差一元就決定 D 能不能用 | 2999 | VIPFREE | 否 | 是 | 正常套用 | 2999 | $0 | 2999 |
| enforce-vip-conflict-with-store-discount-01 | 重點案例：B 觸發時系統應自動禁止 D | 極高：需求標註「重點」，且免運的歸因原因（A vs D）若記錄錯誤會影響報表/歸因統計 | 3000 | VIPFREE | 是 | 否 | 假設：靜默忽略 VIPFREE，僅套用 B | 3000-300=2700 | $0 | 2700 |
| enforce-vip-conflict-with-store-discount-02 | 同上，驗證衝突規則不受金額大小影響 | 中：延伸驗證，防止金額更大時邏輯跑掉 | 3500 | VIPFREE | 是 | 否 | 假設：靜默忽略 VIPFREE，僅套用 B | 3500-300=3200 | $0 | 3200 |
| enforce-code-mutual-exclusivity-01 | 驗證序號互斥是後端強制，而非只靠前端單一輸入框限制 | 高：純前端限制容易被 API 直接呼叫繞過，屬資安/防呆層級測試 | 2000 | SUMMER90 + VIPFREE（同時輸入） | 否 | 否（互斥） | 假設：API 應回傳驗證錯誤，不進行任何折扣計算 | N/A | N/A | 請求應被拒絕（HTTP 400 或等效錯誤） |

---

## 待確認假設（Review 前必須釐清）

1. **enforce-vip-conflict-with-store-discount-01/02（B 觸發時 VIPFREE 的系統回應）**：需求只說「系統將自動禁止用戶使用條件 D」，沒說具體怎麼禁止——前端擋掉輸入框？允許輸入但送出時回錯誤？還是靜默忽略？目前假設「靜默忽略」。
2. **enforce-code-mutual-exclusivity-01（C/D 同時輸入的後端防呆）**：需求只提到前端輸入框只能生效一組，若後端 API 沒有對應驗證、被繞過會怎樣？目前假設「後端應拒絕請求」。
3. **四捨五入規則（stack-store-discount-with-code-01）**：採用一般四捨五入（.5 進位），若實際是無條件捨去或銀行家捨入法，這個案例的預期值需要調整。
4. **「條件 A 判斷時機」**：假設是套用完 B、C 之後的金額才判斷是否滿 $1,500（redeem-discount-code-01/02、stack-store-discount-with-code-01 的存在前提）。若理解錯誤，這三格全部要重算。
