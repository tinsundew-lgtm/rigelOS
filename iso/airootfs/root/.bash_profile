# Rigel live: на первой консоли показываем приветствие вместо приглашения shell.
# RIGEL_WELCOME_SHOWN не даёт зациклиться, когда пользователь выбирает «Терминал».
if [ -z "${RIGEL_WELCOME_SHOWN:-}" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    export RIGEL_WELCOME_SHOWN=1
    exec /usr/local/bin/rigel-welcome
fi

# Удобства живой системы
alias rigel='rigel-install'
alias ll='ls -lah'
alias disks='lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,MODEL'
