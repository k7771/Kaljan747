# Kaljan747
# Скрипт стрес тесту
запуск командою:
curl -s https://raw.githubusercontent.com/k7771/Kaljan747/main/Kaljan747.sh | sed 's/\r//' > /usr/local/bin/kaljan && chmod +x /usr/local/bin/kaljan
Формат конфігів mhddos.ini:
--use-my-ip=0             # Не використовувати свою IP
-t 8000                   # Кількість потоків
--copies=2                # Кількість копій
--user-id=********        # Прихований user ID
Формат конфігів distress.ini:
--use-my-ip               # Використовувати IP
--disable-auto-update     # Вимкнути автооновлення
-c 35000                  # Потоки
--user-id=********        # ID
для вимкнення скрипту:
ctrl+c
Після виконання цієї команди, ви зможете запускати скрипт будь-де, просто ввівши:
kaljan
для згортання screen режиму
ctrl+a+d
вивід з фонового режиму 
screen -r
