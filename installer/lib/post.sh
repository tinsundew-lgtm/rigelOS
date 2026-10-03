#!/usr/bin/env bash
# Rigel installer — настройка установленной системы: локаль, время, хостнейм,
# пользователи, sudo, сервисы, snapper, автовход в Hyprland.

post_configure() {
    local stage="$RIGEL_STATE_DIR/stage-post.sh"
    make_stage_script "$stage" "настройка системы"

    cat >>"$stage" <<'STAGEEOF'

# ---------------------------------------------------------------- локаль
cat >/etc/locale.gen <<'LOCALE'
en_US.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
LOCALE
locale-gen

cat >/etc/locale.conf <<LOCALECONF
LANG=$RIGEL_LANG
LC_MESSAGES=$RIGEL_LOCALE_MESSAGES
LC_TIME=$RIGEL_LOCALE_MESSAGES
LC_COLLATE=$RIGEL_LOCALE_MESSAGES
LOCALECONF

cat >/etc/vconsole.conf <<VCONSOLE
KEYMAP=$RIGEL_KEYMAP
FONT=cyr-sun16
VCONSOLE

# ---------------------------------------------------------------- время и имя
ln -sf "/usr/share/zoneinfo/$RIGEL_TIMEZONE" /etc/localtime
hwclock --systohc

echo "$RIGEL_HOSTNAME" >/etc/hostname
cat >/etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $RIGEL_HOSTNAME.localdomain $RIGEL_HOSTNAME
HOSTS

# ---------------------------------------------------------------- пользователи
echo "root:$RIGEL_ROOT_PASSWORD" | chpasswd
if ! id "$RIGEL_USERNAME" >/dev/null 2>&1; then
    useradd -m -G wheel,video,audio,storage,optical,lp -s /bin/bash "$RIGEL_USERNAME"
fi
echo "$RIGEL_USERNAME:$RIGEL_USER_PASSWORD" | chpasswd

# sudo для группы wheel — отдельным файлом, а не sed по sudoers
cat >/etc/sudoers.d/10-wheel <<'SUDOERS'
%wheel ALL=(ALL:ALL) ALL
SUDOERS
chmod 0440 /etc/sudoers.d/10-wheel
visudo -c >/dev/null

# ---------------------------------------------------------------- сервисы
systemctl enable NetworkManager
systemctl enable bluetooth 2>/dev/null || true
[ "${RIGEL_TRIM:-0}" = "1" ] && systemctl enable fstrim.timer

# ---------------------------------------------------------------- рабочий стол
# gnome/both — графический вход через SDDM; hyprland — автовход на tty1 без DM.
case "$RIGEL_DESKTOP" in
    gnome|both)
        systemctl enable sddm
        if [ "$RIGEL_AUTOLOGIN" = "1" ]; then
            install -d -m 0755 /etc/sddm.conf.d
            cat >/etc/sddm.conf.d/10-rigel-autologin.conf <<SDDMCONF
[Autologin]
User=$RIGEL_USERNAME
Session=gnome
Relogin=false
SDDMCONF
            log "GNOME: SDDM включён, автовход для $RIGEL_USERNAME"
        else
            log "GNOME: SDDM включён, вход по паролю"
        fi
        if [ "$RIGEL_DESKTOP" = "both" ]; then
            log "Hyprland тоже установлен — он доступен в меню сеансов SDDM"
        fi
        ;;
    hyprland)
        if [ "$RIGEL_AUTOLOGIN" = "1" ]; then
            mkdir -p /etc/systemd/system/getty@tty1.service.d
            cat >/etc/systemd/system/getty@tty1.service.d/autologin.conf <<AUTOLOGIN
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $RIGEL_USERNAME --noclear %I \$TERM
AUTOLOGIN

            cat >"/home/$RIGEL_USERNAME/.bash_profile" <<'PROFILE'
# Автовход в Hyprland на первой консоли (настроено установщиком Rigel)
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec Hyprland
fi
PROFILE
            chown "$RIGEL_USERNAME:$RIGEL_USERNAME" "/home/$RIGEL_USERNAME/.bash_profile"
            log "автовход в Hyprland включён для $RIGEL_USERNAME"
        else
            log "Hyprland: автовход выключен — вход через tty, затем команда Hyprland"
        fi
        ;;
    *)
        log "рабочий стол: $RIGEL_DESKTOP — дополнительная настройка не нужна"
        ;;
esac

# ---------------------------------------------------------------- snapper
if [ "$RIGEL_ROOT_FS" = "btrfs" ] && command -v snapper >/dev/null 2>&1; then
    snapper -c root create-config / || true
    if [ -f /etc/snapper/configs/root ]; then
        sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/'      /etc/snapper/configs/root
        sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/'        /etc/snapper/configs/root
        sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/'      /etc/snapper/configs/root
        sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/'    /etc/snapper/configs/root
        sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/'      /etc/snapper/configs/root
    fi
    systemctl enable snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
fi

# ---------------------------------------------------------------- initramfs и итог
mkinitcpio -P
echo "SYSTEM OK"
STAGEEOF

    # RIGEL_ROOT_FS/TRIM/AUTOLOGIN подставляем как переменные окружения chroot
    RIGEL_ROOT_FS="$RIGEL_ROOT_FS" RIGEL_TRIM="${RIGEL_TRIM:-0}" RIGEL_AUTOLOGIN="$RIGEL_AUTOLOGIN" \
        run_target_script "$stage"
    ok "система настроена: локаль $RIGEL_LANG, раскладка $RIGEL_KEYMAP, зона $RIGEL_TIMEZONE"
}

# Инструкция для друзей, если часть пакетов не удалось поставить офлайн
write_offline_note() {
    local note="$RIGEL_MOUNT/home/$RIGEL_USERNAME/ЧТО-ДОДЕЛАТЬ.txt"
    local pkgs="${1:-}"
    [ -n "$pkgs" ] || return 0
    {
        echo "Rigel: часть выбранных приложений не установлена — не было сети."
        echo
        echo "Подключите интернет и выполните:"
        echo "    sudo pacman -S --needed $pkgs"
        echo
        echo "Документация: /usr/share/doc/rigel/ (после установки пакета rigel-meta)"
    } >"$note"
    chown "$RIGEL_USERNAME:$RIGEL_USERNAME" "$note"
    ok "для пользователя создана памятка: ${note#$RIGEL_MOUNT}"
}

cleanup_target_secrets() {
    rm -f "$RIGEL_MOUNT/root/rigel-target.env"
    ok "файл с паролями удалён из целевой системы"
}

final_report() {
    cat <<EOF | tee -a "$RIGEL_LOG"
================================================================
  Rigel $RIGEL_VERSION — установка завершена
================================================================
  система:      $RIGEL_ROOT_FS на $RIGEL_ROOT_PART
  /home:        ${RIGEL_HOME_PART:-в корне}${RIGEL_HOME_PART:+ ($RIGEL_HOME_FS)}
  ESP:          $RIGEL_ESP_PART → $RIGEL_ESP_MOUNT
  swap:         $RIGEL_SWAP
  загрузчик:    ${RIGEL_BOOTLOADER_RESOLVED:-auto}
  ядра:         $RIGEL_KERNELS
  пользователь: $RIGEL_USERNAME@$RIGEL_HOSTNAME
  лог:          $RIGEL_LOG (копия: /var/log/rigel-install.log внутри системы)

  Дальше: выньте флешку и перезагрузитесь (reboot).
  Если система не грузится — загрузитесь с ISO и смотрите раздел
  «Восстановление» в документации Rigel.
================================================================
EOF
    install -Dm644 "$RIGEL_LOG" "$RIGEL_MOUNT/var/log/rigel-install.log" 2>/dev/null || true
}
