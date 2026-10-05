#!/usr/bin/env bash
# Rigel installer — настройка установленной системы: локаль, время, хостнейм,
# пользователи, sudo, сервисы, snapper.

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

cat >/etc/sudoers.d/10-wheel <<'SUDOERS'
%wheel ALL=(ALL:ALL) ALL
SUDOERS
chmod 0440 /etc/sudoers.d/10-wheel
visudo -c >/dev/null

# ---------------------------------------------------------------- сервисы
systemctl enable NetworkManager
systemctl enable bluetooth 2>/dev/null || true
[ "${RIGEL_TRIM:-0}" = "1" ] && systemctl enable fstrim.timer

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

# ---------------------------------------------------------------- initramfs
mkinitcpio -P
echo "SYSTEM OK"
STAGEEOF

    RIGEL_ROOT_FS="$RIGEL_ROOT_FS" RIGEL_TRIM="${RIGEL_TRIM:-0}" \
        run_target_script "$stage"
    ok "система настроена: локаль $RIGEL_LANG, раскладка $RIGEL_KEYMAP, зона $RIGEL_TIMEZONE"
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
  загрузчик:    GRUB
  ядра:         $RIGEL_KERNELS
  пользователь: $RIGEL_USERNAME@$RIGEL_HOSTNAME
  лог:          $RIGEL_LOG (копия: /var/log/rigel-install.log внутри системы)

  Дальше: выньте флешку и перезагрузитесь (reboot).
================================================================
EOF
    install -Dm644 "$RIGEL_LOG" "$RIGEL_MOUNT/var/log/rigel-install.log" 2>/dev/null || true
}