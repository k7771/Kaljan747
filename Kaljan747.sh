#!/bin/bash

set -e

# Перевірка root/sudo
[ "$(id -u)" -eq 0 ] && SUDO="" || SUDO="sudo"

# Пакетний менеджер та встановлення залежностей
if command -v apt >/dev/null; then
    $SUDO apt update -qq
    $SUDO DEBIAN_FRONTEND=noninteractive apt install -y -qq curl wget git screen sed wireguard zenity
elif command -v dnf >/dev/null; then
    $SUDO dnf install -y curl wget git screen sed wireguard-tools zenity
elif command -v yum >/dev/null; then
    $SUDO yum install -y curl wget git screen sed wireguard-tools zenity
elif command -v apk >/dev/null; then
    $SUDO apk add curl wget git screen sed wireguard-tools zenity
else
    zenity --error --text="Не знайдено підтримуваного пакетного менеджера."
    exit 1
fi

MODULE_DIR="$HOME/modules"
WG_DIR="$HOME/wg_confs"
mkdir -p "$MODULE_DIR" "$WG_DIR"

# GUI вибір модуля
MODULE_CHOICE=$(zenity --list --radiolist \
--title="Вибір модуля" \
--text="Оберіть модуль для запуску:" \
--column="" --column="Модуль" \
TRUE "mhddos_proxy" FALSE "distress")

[ -z "$MODULE_CHOICE" ] && { zenity --error --text="Модуль не обрано"; exit 1; }

# Завантаження модулів
case "$MODULE_CHOICE" in
    mhddos_proxy)
        MODULE="$MODULE_DIR/mhddos_proxy"
        [ -f "$MODULE" ] || wget -qO "$MODULE" "https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
        chmod +x "$MODULE"
        INI="$MODULE_DIR/mhddos.ini"
        PARAM="--ifaces"
        ;;
    distress)
        MODULE="$MODULE_DIR/distress"
        [ -f "$MODULE" ] || wget -qO "$MODULE" "https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"
        chmod +x "$MODULE"
        INI="$MODULE_DIR/distress.ini"
        PARAM="--interface"
        ;;
esac

# Завантаження WG-конфігів
WG_RAW_BASE="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"
WG_LIST=(wg1.conf wg2.conf wg3.conf wg4.conf wg5.conf)

for conf in "${WG_LIST[@]}"; do
    wget -q "$WG_RAW_BASE/$conf" -O "$WG_DIR/$conf"
done

# Вибір WG-конфігів
WG_SELECTED=$(zenity --list --checklist \
--title="WireGuard" \
--text="Оберіть WG-конфіги:" \
--column="" --column="Конфіг" \
$(for i in "${WG_LIST[@]}"; do echo TRUE "$i"; done))

[ -z "$WG_SELECTED" ] && { zenity --error --text="WG-конфіги не обрано"; exit 1; }

# Вимкнення WG-інтерфейсів
wg show interfaces | xargs -I{} $SUDO wg-quick down {} 2>/dev/null || true

# Підключення WG
VPN_LIST=""
for conf in $WG_SELECTED; do
    iface=${conf%.conf}
    $SUDO ip link delete "$iface" 2>/dev/null || true
    $SUDO wg-quick up "$WG_DIR/$conf"
    VPN_LIST+="$iface "
done

VPN_LIST=${VPN_LIST%% }
[ "$MODULE_CHOICE" = "distress" ] && VPN_LIST=${VPN_LIST// /,}

echo "$PARAM $VPN_LIST" > "$INI"

# Редагування ini-файлу
zenity --text-info --editable --filename="$INI" --title="Редагування $INI" > "$INI.tmp" && mv "$INI.tmp" "$INI"

# Режим запуску
RUN_MODE=$(zenity --list --radiolist \
--title="Режим запуску" \
--text="Оберіть режим запуску:" \
--column="" --column="Режим" \
TRUE "screen у фоні" FALSE "screen відкрито" FALSE "без screen")

[ -z "$RUN_MODE" ] && { zenity --error --text="Режим не обрано"; exit 1; }

case "$RUN_MODE" in
    "screen у фоні")
        screen -dmS "$MODULE_CHOICE" "$MODULE" $(cat "$INI")
        zenity --info --text="Модуль запущено у фоні (screen)"
        ;;
    "screen відкрито")
        zenity --info --text="Модуль відкриється у screen. Для виходу: Ctrl+A, D"
        screen -S "$MODULE_CHOICE" "$MODULE" $(cat "$INI")
        ;;
    "без screen")
        zenity --info --text="Модуль запускається у терміналі."
        "$MODULE" $(cat "$INI")
        ;;
esac
