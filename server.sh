#!/bin/bash

# Функция для проверки имени пользователя
validate_username() {
    local username=$1
    if [[ "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
        return 0
    else
        echo "Неверное имя пользователя. Имя может содержать только буквы, цифры и подчёркивания."
        return 1
    fi
}

# Вопросы
echo -e "\n### Настройка сервера ###"

# Создание нового пользователя
echo -e "\nХотите создать нового пользователя для входа в систему вместо root? (да/нет)"
read -p "Ваш ответ: " create_new_user
create_new_user=$(echo "$create_new_user" | tr '[:upper:]' '[:lower:]' | tr -s ' ')

if [[ "$create_new_user" =~ ^(да|y|yes)$ ]]; then
    while true; do
        read -p "Введите имя нового пользователя (без пробелов и специальных символов): " username
        validate_username "$username" && break
    done

    while true; do
        read -s -p "Введите пароль для нового пользователя: " password
        echo
        read -s -p "Повторите пароль: " password_confirm
        echo
        if [[ "$password" == "$password_confirm" && -n "$password" ]]; then
            break
        else
            echo "Пароли не совпадают или пусты. Попробуйте снова."
        fi
    done
else
    echo -e "\nОставляем root-пользователя для входа в систему."
    username="root"
fi

# Настройка порта для SSH
while true; do
    echo -e "\nДля повышения безопасности сервера рекомендуется изменить стандартный порт SSH."
    read -p "Введите новый порт SSH (рекомендуется диапазон от 1024 до 65535): " ssh_port
    if [[ "$ssh_port" =~ ^[0-9]+$ ]] && ((ssh_port >= 1024 && ssh_port <= 65535)); then
        break
    else
        echo "Пожалуйста, введите корректный порт в диапазоне от 1024 до 65535."
    fi
done

# Запрет root-доступа по SSH
echo -e "\nХотите запретить вход по SSH для root-пользователя? (да/нет)"
read -p "Ваш ответ: " disable_root_ssh
disable_root_ssh=$(echo "$disable_root_ssh" | tr '[:upper:]' '[:lower:]' | tr -s ' ')

# Добавление публичного ключа
if [[ "$username" != "root" ]]; then
    echo -e "\nВведите ваш публичный SSH-ключ (начинается с 'ssh-rsa' или 'ssh-ed25519'):"
    read -r public_key
fi

# Выполнение действий
echo -e "\n### Выполнение настроек ###"

# Установка и обновление пакетов
apt-get update -y && echo "Обновление списка пакетов... [OK]"
apt-get upgrade -y && echo "Обновление установленных пакетов... [OK]"

# Создание нового пользователя
if [[ "$create_new_user" =~ ^(да|y|yes)$ ]]; then
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    usermod -aG sudo "$username"
    echo -e "\nПользователь $username успешно создан и добавлен в группу sudo."
fi

# Настройка порта для SSH
sed -i "s/^#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
systemctl restart ssh
echo -e "Порт SSH успешно изменён на $ssh_port."

# Настройка firewall с UFW
echo "Настройка фаервола (ufw)..."
ufw allow "$ssh_port"/tcp && echo "Разрешён порт SSH: $ssh_port [OK]"
ufw allow http && echo "Разрешён HTTP трафик [OK]"
ufw allow https && echo "Разрешён HTTPS трафик [OK]"
ufw default deny incoming && echo "Входящий трафик запрещён [OK]"
ufw default allow outgoing && echo "Исходящий трафик разрешён [OK]"
ufw --force enable && echo "Фаервол включён [OK]"

# Запрет root-доступа по SSH
if [[ "$disable_root_ssh" =~ ^(да|y|yes)$ ]]; then
    sed -i '/^#*PermitRootLogin/s/^#*.*/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart ssh
    echo -e "\nВход по SSH для root-пользователя успешно запрещен."
else
    echo -e "\nВход по SSH для root-пользователя оставлен включённым."
fi

# Добавление публичного ключа
if [[ "$username" != "root" ]]; then
    if [[ "$public_key" =~ ^ssh-(rsa|ed25519) ]]; then
        mkdir -p "/home/$username/.ssh"
        chmod 700 "/home/$username/.ssh"

        echo "$public_key" > "/home/$username/.ssh/authorized_keys"
        chmod 600 "/home/$username/.ssh/authorized_keys"
        chown -R "$username:$username" "/home/$username/.ssh"

        echo -e "\nВаш публичный ключ был успешно добавлен в authorized_keys для пользователя $username."
    else
        echo -e "\nНеверный формат ключа. Вы можете добавить его вручную позже в файл /home/$username/.ssh/authorized_keys."
    fi
fi

echo -e "\nНастройка сервера завершена."
