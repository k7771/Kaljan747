#!/bin/bash

set -e

# === Перевірка прав користувача ===
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        zenity --error --text="sudo не знайдено. Встановіть або увійдіть як root."; exit 1
    fi
fi

# === Встановлення залежностей ===
if command -v apt >/dev/null 2>&1; then
    $SUDO apt update -y
    $SUDO apt install -y curl wget git screen sed wireguard zenity x11-utils xterm htop iftop tmux
elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y curl wget git screen sed wireguard-tools zenity xterm htop iftop tmux
elif command -v yum >/dev/null 2>&1; then
    $SUDO yum install -y curl wget git screen sed wireguard-tools zenity xterm htop iftop tmux
elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add curl wget git screen sed wireguard-tools zenity xterm htop iftop tmux
else
    zenity --error --text="Підтримуваний пакетний менеджер не знайдено."; exit 1
fi

MODULE_DIR="$HOME/modules"
WG_DIR="$HOME/wg_confs"
mkdir -p "$MODULE_DIR" "$WG_DIR"
touch "$MODULE_DIR/mhddos.ini" "$MODULE_DIR/distress.ini"

MODULE_NAME="mhddos"
MODULE="$MODULE_DIR/mhddos_proxy"
CONFIG_FILE="$MODULE_DIR/mhddos.ini"
RUN_MODE="screen у фоні"
MONITORING=1

# === Завантаження WG-конфігів ===
WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
WG_RAW_BASE="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"
CONF_LIST=$(curl -fsSL "$WG_REPO_HTML" | grep -oP '(?<=href=").*?\.conf(?=")' | grep '/k7771/Kaljan747/blob/' | sed -e 's|^/|https://github.com/|' -e 's|blob/|raw/|')

for url in $CONF_LIST; do
    file=$(basename "$url")
    wget -qO "$WG_DIR/$file" "$url"
done

$SUDO chmod 600 "$WG_DIR"/*.conf 2>/dev/null || true

launch_monitoring() {
    xterm -T "Kaljan747 Моніторинг" -bg black -fg white +sb -fa 'Monospace' -fs 11 -e "bash -c '
    tmux new-session -d \"htop\"
    tmux split-window -h \"iftop -i \\$(ip route | grep default | awk \\\"{print \\\\$5}\\\")\"
    tmux select-layout even-horizontal
    tmux attach
    '" &
}

launch_module() {
    screen -dmS "$MODULE_NAME" bash -c "$MODULE $(cat $CONFIG_FILE)"
    if [ "$MONITORING" -eq 1 ]; then
        launch_monitoring
    fi
}

stop_module() {
    screen -S "$MODULE_NAME" -X stuff "^C"
    sleep 2
    screen -S "$MODULE_NAME" -X quit
}

restart_wg() {
    for iface in $(wg show interfaces 2>/dev/null); do
        $SUDO wg-quick down "$iface" || true
        $SUDO ip link delete "$iface" || true
    done

    WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf | head -n 4))
    WG_IFACES=()
    for conf in "${WG_FILES[@]}"; do
        IFACE_NAME=$(basename "$conf" .conf)
        $SUDO wg-quick up "$conf"
        WG_IFACES+=("$IFACE_NAME")
    done

    VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
    VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")

    echo "--use-my-ip 0 --copies 4 -t 12000 --ifaces $VPN_LIST --user-id=********" > "$MODULE_DIR/mhddos.ini"
    echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000 --interface=$VPN_LIST_COMMAS --user-id=********" > "$MODULE_DIR/distress.ini"
}

while true; do
    ACTION=$(zenity --list --title="Kaljan747 Пульт Управління" --text="Оберіть дію:" --column="Дії" \
        "Вибрати модуль" "Редагувати INI" "Вибрати режим запуску" "Моніторинг показати/приховати" \
        "Перезапустити модуль" "Згорнути модуль" "Зупинити модуль" "Вийти")

    case "$ACTION" in
        "Вибрати модуль")
            MOD=$(zenity --list --title="Вибір модуля" --column="Модуль" "mhddos_proxy" "distress")
            stop_module
            restart_wg
            if [ "$MOD" = "mhddos_proxy" ]; then
                MODULE_NAME="mhddos"
                MODULE="$MODULE_DIR/mhddos_proxy"
                CONFIG_FILE="$MODULE_DIR/mhddos.ini"
            else
                MODULE_NAME="distress"
                MODULE="$MODULE_DIR/distress"
                CONFIG_FILE="$MODULE_DIR/distress.ini"
            fi
            launch_module
            ;;
        "Редагувати INI")
            EDIT=$(zenity --list --title="Редагувати INI" --column="Опція" "Так" "Ні")
            if [ "$EDIT" = "Так" ]; then
                zenity --text-info --editable --filename="$CONFIG_FILE" --title="Редагування INI" > "$CONFIG_FILE.tmp"
                mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            fi
            ;;
        "Вибрати режим запуску")
            RUN_MODE=$(zenity --list --title="Режим запуску" --column="Режим" "screen у фоні" "screen відкрито" "без screen")
            ;;
        "Моніторинг показати/приховати")
            MONITOR=$(zenity --list --title="Моніторинг" --column="Опція" "Показати" "Приховати")
            if [ "$MONITOR" = "Показати" ]; then
                MONITORING=1
            else
                MONITORING=0
            fi
            ;;
        "Перезапустити модуль")
            stop_module
            restart_wg
            launch_module
            ;;
        "Згорнути модуль")
            screen -S "$MODULE_NAME" -X detach
            ;;
        "Зупинити модуль")
            stop_module
            ;;
        "Вийти")
            exit 0
            ;;
    esac
done

