#!/usr/bin/env bash
# Rigel installer — загрузчик GRUB, два ядра, ucode.

kernel_cmdline() {
    local opts="root=UUID=${RIGEL_ROOT_UUID:-} rw quiet"
    [ "$RIGEL_ROOT_FS" = "btrfs" ] && opts="$opts rootflags=subvol=@"
    printf '%s' "$opts"
}

gen_fstab() {
    run genfstab -U "$RIGEL_MOUNT" >>"$RIGEL_MOUNT/etc/fstab"
    ok "fstab сгенерирован"
    grep -v '^#' "$RIGEL_MOUNT/etc/fstab" | sed 's/^/    /' >>"$RIGEL_LOG"
}

install_bootloader() {
    install_grub
    inspect_esp
}

install_grub() {
    ok "устанавливаем GRUB"
    chroot_run "pacman -S --needed --noconfirm grub efibootmgr" || die "не удалось установить grub"

    local stage="$RIGEL_STATE_DIR/stage-grub.sh"
    make_stage_script "$stage" "grub"
    if is_uefi; then
        cat >>"$stage" <<'EOF'
grub-install --target=x86_64-efi --efi-directory=/boot --removable --recheck
EOF
    else
        cat >>"$stage" <<EOF
grub-install --target=i386-pc --recheck $RIGEL_DISK
EOF
    fi
    cat >>"$stage" <<EOF
grub-mkconfig -o /boot/grub/grub.cfg
EOF
    run_target_script "$stage"
    ok "GRUB установлен"
}

inspect_esp() {
    local esp="$RIGEL_MOUNT$RIGEL_ESP_MOUNT"
    ok "содержимое ESP ($RIGEL_ESP_MOUNT):"
    find "$esp" -maxdepth 2 -mindepth 1 2>/dev/null | sed "s|$RIGEL_MOUNT||" | sort | sed 's/^/    /' >>"$RIGEL_LOG"

    local missing=0
    for k in $RIGEL_KERNELS; do
        [ -f "$esp/vmlinuz-$k" ] || { err "на ESP нет ядра vmlinuz-$k"; missing=1; }
        [ -f "$esp/initramfs-$k.img" ] || { err "на ESP нет initramfs-$k.img"; missing=1; }
    done
    [ "$missing" = "1" ] && die "загрузчик установлен неполно — смотрите $RIGEL_LOG"
    ok "ядра и initramfs на месте"
}