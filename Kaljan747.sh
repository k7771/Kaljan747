#!/bin/bash
set -e

# === Функції для кольорового виведення ===
print_header() {
    echo -e "\e[1;36m========================================"
    echo -e "🚀  Запуск Kaljan747"
    echo -e "========================================\e[0m"
}

print_summary() {
    echo -e "\n\e[1;33m----------------------------------------"
    echo -e "📦  Встановлення залежностей: \e[1;32mOK\e[0m"
    echo -e "🌍  Завантаження WG-конфігів: \e[1;32mOK\e[0m"
    echo -e "⚙️  Запуск модуля: PID $1"
    echo -e "----------------------------------------\e[0m"
}

print_stage() {
    echo -e "\e[1;34m$1\e[0m"
}

# === Шляхи до файлів ===
SETTINGS_FILE="$HOME/.kaljan747_settings"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/wg.log"
MODULE_DIR="$HOME/modules"
WG_DIR="$HOME/wg_confs"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# === Встановлення прав доступу ===
set_permissions() {
    echo -e "\n📁  Встановлюю права доступу до папок і файлів..."
    sudo chmod -R 755 $HOME
    sudo chmod -R 755 $MODULE_DIR
    sudo chmod -R 755 $WG_DIR
    sudo chmod +x $MODULE_DIR/mhddos_proxy
    sudo chmod +x $MODULE_DIR/distress
    sudo chmod 644 $MODULE_DIR/mhddos.ini
    sudo chmod 644 $MODULE_DIR/distress.ini
    sudo chown -R $USER:$USER $HOME
    sudo chmod -R 755 $LOG_DIR
    sudo chown -R $USER:$USER $LOG_DIR
    sudo chmod 644 $LOG_FILE
    echo -e "✅ Права доступу встановлено."
}

# === Завантаження WG-конфігів ===
download_wg_configs() {
    echo -e "\n📥 Завантаження WG-конфігів..."
    
    # Оновлений GitHub URL для завантаження конфігурацій
    WG_REPO_URL="https://github.com/k7771/Kaljan747/tree/k7771/wg"
    
    # Збираємо список конфігураційних файлів з GitHub (raw URL)
    CONF_LIST=$(curl -fsSL "$WG_REPO_URL" | grep -oP '(?<=href=").*?\.conf(?=")' | sed -e 's|^/|https://raw.githubusercontent.com/|')

    if [ -z "$CONF_LIST" ]; then
        echo "[-] Не вдалося знайти конфігураційні файли за вказаним URL."
        exit 1
    fi

    # Завантаження всіх конфігураційних файлів
    for url in $CONF_LIST; do
        file=$(basename "$url")
        wget -qO "$WG_DIR/$file" "$url" || { echo "[-] Не вдалося завантажити конфігураційний файл $file"; exit 1; }
    done
}

# === Встановлення залежностей ===
install_dependencies() {
    if command -v apt >/dev/null 2>&1; then
        sudo apt update -y
        sudo apt install -y curl wget git screen sed wireguard zenity
    else
        echo "Підтримуваний пакетний менеджер не знайдено."
        exit 1
    fi
}

# === Завантаження обох модулів ===
download_modules() {
    echo -e "\n📥 Завантаження обох модулів..."

    mhddos_proxy_download_link="https://github.com/porthole-ascend-cinnamon/mhddos_proxy_releases/releases/latest/download/mhddos_proxy_linux"
    distress_download_link="https://github.com/Yneth/distress-releases/releases/latest/download/distress_x86_64-unknown-linux-musl"

    # Завантажуємо обидва модулі
    wget -qO "$MODULE_DIR/mhddos_proxy" "$mhddos_proxy_download_link" || { echo "[-] Не вдалося завантажити mhddos_proxy"; exit 1; }
    wget -qO "$MODULE_DIR/distress" "$distress_download_link" || { echo "[-] Не вдалося завантажити distress"; exit 1; }

    chmod +x "$MODULE_DIR/mhddos_proxy"
    chmod +x "$MODULE_DIR/distress"
}

# === Функції для запиту ===
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

# === Завантаження або запит налаштувань ===
if [ -f "$SETTINGS_FILE" ]; then
    source "$SETTINGS_FILE"
fi

if [ -z "$USER_ID" ]; then
    while true; do
        ask_user_id
        if [ -z "$USER_ID" ]; then
            echo "User-id обов'язковий. Завершення."
            exit 1
        fi
        if [[ "$USER_ID" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Помилка: USER-ID має містити тільки цифри!"
        fi
    done
fi

if [ -z "$SELECTED_MODULE" ] || [ -z "$EDIT_INI" ] || [ -z "$SELECTED_RUN_MODE" ]; then
    ask_run_parameters
fi

print_header
echo -e "📥  Отримано USER-ID: \e[1;32m$USER_ID\e[0m"
echo -e "🧩  Обраний модуль: \e[1;36m$SELECTED_MODULE\e[0m"
echo -e "🛠️  Режим запуску: \e[1;36m$SELECTED_RUN_MODE\e[0m"

# Встановлення прав доступу
set_permissions

# Завантаження обох модулів
download_modules

# Завантаження конфігурацій
download_wg_configs

# Встановлення залежностей
install_dependencies

# === Пошук або підтвердження папки wg_confs ===
if [ -z "$WG_DIR" ] || [ ! -d "$WG_DIR" ]; then
    print_stage "Шукаю папку wg_confs..."
    WG_DIRS=($(find "$HOME" -type d -name "wg_confs" 2>/dev/null))
    if [ ${#WG_DIRS[@]} -eq 0 ]; then
        echo "[!] У $HOME не знайдено, шукаю у всій файловій системі..."
        WG_DIRS=($(find / -type d -name "wg_confs" 2>/dev/null))
    fi
    if [ ${#WG_DIRS[@]} -eq 0 ]; then
        echo "[-] Папку wg_confs не знайдено."
        exit 1
    fi
    if [ ${#WG_DIRS[@]} -gt 1 ]; then
        echo "[+] Знайдено кілька папок wg_confs:"
        for i in "${!WG_DIRS[@]}"; do
            echo "$((i+1))) ${WG_DIRS[$i]}"
        done
        if [ -n "$DISPLAY" ] && command -v zenity >/dev/null 2>&1; then
            SELECTED_INDEX=$(zenity --list --title="Виберіть папку wg_confs" --column="Номер" --column="Папка" $(for i in "${!WG_DIRS[@]}"; do echo "$((i+1))" "${WG_DIRS[$i]}"; done) --width=600 --height=400 | awk '{print $1}')
        else
            read -p "Введіть номер потрібної папки: " SELECTED_INDEX
        fi
        WG_DIR="${WG_DIRS[$((SELECTED_INDEX-1))]}"
    else
        WG_DIR="${WG_DIRS[0]}"
    fi
    echo "WG_DIR=\"$WG_DIR\"" >> "$SETTINGS_FILE"
fi

echo -e "📡  VPN-інтерфейси: \e[1;36m$WG_DIR\e[0m"

# === Перевірка прав користувача ===
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "sudo не знайдено. Встановіть або увійдіть як root."
        exit 1
    fi
fi

# === Встановлення залежностей ===
if command -v apt >/dev/null 2>&1; then
    $SUDO apt update -y
    $SUDO apt install -y curl wget git screen sed wireguard zenity
else
    echo "Підтримуваний пакетний менеджер не знайдено."
    exit 1
fi

print_stage "Встановлення залежностей завершено."

# === Запуск вибраного модуля ===
echo -e "⚙️  Запускаю модуль..."
case "$SELECTED_RUN_MODE" in
    "screen у фоні") 
        screen -dmS "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE"); PID=$(pgrep -f "$MODULE")
        echo -e "✅ Модуль запущено в фоні." ;;
    "screen відкрито") 
        screen -S "$MODULE_NAME" "$MODULE" $(cat "$CONFIG_FILE"); PID=$(pgrep -f "$MODULE")
        echo -e "🖥️ Модуль запущено відкрито." ;;
    "без screen") 
        "$MODULE" $(cat "$CONFIG_FILE") & PID=$! 
        echo -e "🚫 Модуль запущено без screen." ;;
esac

print_summary "$PID"

exit 0
