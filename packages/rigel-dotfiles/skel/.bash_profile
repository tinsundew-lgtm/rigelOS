# ~/.bash_profile — запускается при входе в tty
# rigel — алиас для вызова установщика (если он в системе)

alias rigel='sudo rigel-install'

if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# Если мы в live-режиме — показать приветствие
if [ -f /usr/local/bin/rigel-welcome ]; then
    /usr/local/bin/rigel-welcome
fi