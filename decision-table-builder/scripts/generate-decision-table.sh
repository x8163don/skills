#!/bin/bash
#
# 決策表組合產生器：依條件與規則印出所有組合的 Markdown 表格
#
# 用法：
#   ./generate-decision-table.sh -c "條件名稱:值1,值2,..." [-c ...] [-r "規則"] [-r ...]
#
# 參數：
#   -c "名稱:值1,值2,..."   定義一個條件（Criteria）與其可能的值，逗號分隔。可重複使用多個 -c。
#                            條件名稱與值不可包含冒號（:）或逗號（,），否則會被誤判為分隔符號。
#   -r "規則"                定義 EXCLUDE 或 OVERRIDE 規則。可重複使用多個 -r。
#
# 規則語法：
#   EXCLUDE:條件A==值A && 條件B==值B && ...
#       當「所有」條件同時成立時，該組合會被剪掉、不列印。支援任意數量條件用 && 串接。
#
#   OVERRIDE:條件A==值A && 條件B==值B && ... -> 目標條件=覆蓋值
#       當「所有」條件同時成立時，將目標條件的值強制改成覆蓋值。
#       改寫後若與其他組合重複，只會列印一次（自動去重）。
#       若多條 OVERRIDE 規則同時命中同一組合，會依 -r 參數的先後順序依序套用，
#       後面的規則可能覆蓋前面規則的結果，請避免定義互相衝突的 OVERRIDE。
#
# 注意：
#   本工具會窮舉所有條件值的笛卡兒積（再套用 EXCLUDE/OVERRIDE 剪枝），
#   不會自動判斷「哪些組合有測試價值」。建議先依決策表方法論
#   （只挑邊界值、關鍵交互情境）縮小每個條件的值列表，再用本工具展開驗證覆蓋率，
#   而非直接塞入大量條件與值。組合數過多時（見下方警告）請用 EXCLUDE 收斂。
#
# 範例：
#   ./generate-decision-table.sh \
#     -c "啤酒:0,1,6,7,12" \
#     -c "可樂:0,1,6" \
#     -r "EXCLUDE:啤酒==7 && 可樂==6" \
#     -r "OVERRIDE:啤酒==12 && 可樂==6 -> 可樂=0"
#

declare -a COND_NAMES
declare -a COND_VALUES
declare -a RULES

# 解析參數
while getopts "c:r:" opt; do
  case ${opt} in
    c )
      IFS=':' read -r name values_str <<< "$OPTARG"
      COND_NAMES+=("$(echo "$name" | xargs)")
      COND_VALUES+=("$(echo "$values_str" | xargs)")
      ;;
    r )
      RULES+=("$OPTARG")
      ;;
  esac
done

TOTAL_CONDS=${#COND_NAMES[@]}

# 防呆：條件名稱或數值格式異常（例如含空白）會讓兩個陣列長度對不上，
# 若不擋下來，後續會靜默印出空表格，讓人誤以為是規則沒有命中。
if [ "$TOTAL_CONDS" -eq 0 ]; then
  echo "錯誤：至少需要用 -c 定義一個條件" >&2
  exit 1
fi
if [ "$TOTAL_CONDS" -ne "${#COND_VALUES[@]}" ]; then
  echo "錯誤：條件名稱與數值列表數量不一致（${TOTAL_CONDS} vs ${#COND_VALUES[@]}），請檢查 -c 參數是否含有空白或格式錯誤" >&2
  exit 1
fi

# 用一個普通的字串變數來記錄已經印出過的組合，格式為 [combo1][combo2]
SEEN_COMBOS=""

# 輔助函式：根據名稱取得在組合中的 index
get_index_by_name() {
  local target_name=$1
  for ((i=0; i<TOTAL_CONDS; i++)); do
    if [ "${COND_NAMES[$i]}" == "$target_name" ]; then
      echo "$i"
      return
    fi
  done
  echo "-1"
}

# 輔助函式：解析 "條件A==值A && 條件B==值B && ..." 字串
# 結果寫入全域陣列 _PARSED_IDXS / _PARSED_VALS（支援任意數量的 && 串接）
parse_and_conditions() {
  local expr="$1"
  local and_sentinel=$'\x1e'
  local eq_sentinel=$'\x1f'

  _PARSED_IDXS=()
  _PARSED_VALS=()

  local normalized="${expr//&&/$and_sentinel}"
  local -a raw_conds
  IFS="$and_sentinel" read -ra raw_conds <<< "$normalized"

  local raw cname cval cidx
  for raw in "${raw_conds[@]}"; do
    IFS="$eq_sentinel" read -r cname cval <<< "${raw//==/$eq_sentinel}"
    cname=$(echo "$cname" | xargs); cval=$(echo "$cval" | xargs)
    cidx=$(get_index_by_name "$cname")
    _PARSED_IDXS+=("$cidx")
    _PARSED_VALS+=("$cval")
  done
}

# 核心遞迴
generate_combinations() {
  local index=$1
  shift
  local current_combo=("$@")

  # --- 剪枝與過濾層 (套用 EXCLUDE 規則，支援任意數量的 && 條件) ---
  for rule in "${RULES[@]}"; do
    if [[ "$rule" == *"EXCLUDE"* ]]; then
      IFS=':' read -r _ detail <<< "$rule"
      parse_and_conditions "$detail"

      local max_idx=-1
      local k
      for ((k=0; k<${#_PARSED_IDXS[@]}; k++)); do
        [ "${_PARSED_IDXS[$k]}" -gt "$max_idx" ] && max_idx=${_PARSED_IDXS[$k]}
      done

      if [ "$index" -gt "$max_idx" ]; then
        local all_match=1
        for ((k=0; k<${#_PARSED_IDXS[@]}; k++)); do
          if [ "${current_combo[${_PARSED_IDXS[$k]}]}" != "${_PARSED_VALS[$k]}" ]; then
            all_match=0
            break
          fi
        done
        [ "$all_match" -eq 1 ] && return
      fi
    fi
  done

  # 終止條件：所有條件處理完畢
  if [ "$index" -eq "$TOTAL_CONDS" ]; then
    # 處理「強弱覆蓋 (OVERRIDE)」規則，支援任意數量的 && 條件同時成立才觸發
    for rule in "${RULES[@]}"; do
      if [[ "$rule" == *"OVERRIDE"* ]]; then
        IFS=':' read -r _ detail <<< "$rule"

        local arrow_sentinel=$'\x02'
        local condition_part action_part
        IFS="$arrow_sentinel" read -r condition_part action_part <<< "${detail/->/$arrow_sentinel}"

        parse_and_conditions "$condition_part"

        local all_match=1
        local k
        for ((k=0; k<${#_PARSED_IDXS[@]}; k++)); do
          if [ "${current_combo[${_PARSED_IDXS[$k]}]}" != "${_PARSED_VALS[$k]}" ]; then
            all_match=0
            break
          fi
        done

        if [ "$all_match" -eq 1 ]; then
          local eq_sentinel=$'\x1f'
          local act_name act_val
          IFS="$eq_sentinel" read -r act_name act_val <<< "${action_part/=/$eq_sentinel}"
          act_name=$(echo "$act_name" | xargs); act_val=$(echo "$act_val" | xargs)
          local a_idx
          a_idx=$(get_index_by_name "$act_name")
          current_combo[$a_idx]="$act_val"
        fi
      fi
    done

    # 組合轉成標準 Markdown 字串
    local line="|"
    for item in "${current_combo[@]}"; do
      line="$line $item |"
    done
    
    # 舊版 Bash 去重邏輯：用字串包圍並搜尋是否存在
    if [[ "$SEEN_COMBOS" != *"[${line}]"* ]]; then
      echo "$line"
      SEEN_COMBOS="${SEEN_COMBOS}[${line}]"
    fi
    return
  fi

  # 正常遞迴展開
  local raw_values=${COND_VALUES[$index]}
  # 相容舊版 Bash 的字串切分方式
  local saved_IFS=$IFS
  IFS=','
  local -a values_array=($raw_values)
  IFS=$saved_IFS

  for val in "${values_array[@]}"; do
    val=$(echo "$val" | xargs)
    next_combo=("${current_combo[@]}" "$val")
    generate_combinations $((index + 1)) "${next_combo[@]}"
  done
}

# 剪枝前預估總組合數（笛卡兒積），提醒使用者組合是否過多
estimate_total_combos() {
  local total=1
  local i raw_values saved_IFS
  for ((i=0; i<TOTAL_CONDS; i++)); do
    raw_values=${COND_VALUES[$i]}
    saved_IFS=$IFS
    IFS=','
    local -a vals=($raw_values)
    IFS=$saved_IFS
    total=$((total * ${#vals[@]}))
  done
  echo "$total"
}

ESTIMATED_COMBOS=$(estimate_total_combos)
if [ "$ESTIMATED_COMBOS" -gt 20 ]; then
  echo "警告：未套用 EXCLUDE 前，預估組合數為 ${ESTIMATED_COMBOS} 組。" >&2
  echo "決策表方法論建議只挑選有業務意義的組合，規則數超過 8 條時應拆分子表；" >&2
  echo "請考慮用 EXCLUDE 收斂，或先減少條件/數值再展開。" >&2
fi

# 印出標題
printf "| %s " "${COND_NAMES[@]}"; printf "|\n"
for ((i=0; i<TOTAL_CONDS; i++)); do printf "|---"; done; printf "|\n"

# 啟動
generate_combinations 0
