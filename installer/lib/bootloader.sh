#!/usr/bin/env bash
# Rigel installer — загрузчик: systemd-boot (UEFI) и GRUB (UEFI/BIOS), два ядра,
# записи с ucode и параметром nvidia_drm.modeset.

kernel_cmdline() {
    local opts="root=UUID=${RIGEL_ROOT_UUID:-} rw quiet"
    [ "$RIGEL_ROOT_FS" = "btrfs" ] && opts="$opts rootflags=subvol=@"
    case "$RIGEL_GPU" in
        nvidia|nvidia-open|auto)
            case "$(detect_gpus)" in
                *nvidia*) opts="$opts nvidia_drm.modeset=1 nvidia_drm.fbdev=1" ;;
            esac ;;
    esac
    printf '%s' "$opts"
}

gen_fstab() {
    run genfstab -U "$RIGEL_MOUNT" >>"$RIGEL_MOUNT/etc/fstab"
    ok "fstab сгенерирован"
    grep -v '^#' "$RIGEL_MOUNT/etc/fstab" | sed 's/^/    /' >>"$RIGEL_LOG"
}

install_bootloader() {
    RIGEL_BOOTLOADER_RESOLVED="$RIGEL_BOOTLOADER"
    [ "$RIGEL_BOOTLOADER_RESOLVED" = "auto" ] && RIGEL_BOOTLOADER_RESOLVED="grub"
    echo "RIGEL_BOOTLOADER_RESOLVED='$RIGEL_BOOTLOADER_RESOLVED'" >>"$RIGEL_MOUNT/root/rigel-target.env"

    case "$RIGEL_BOOTLOADER_RESOLVED" in
        systemd-boot)
            is_uefi || die "systemd-boot требует UEFI; выберите grub для BIOS"
            install_systemd_boot ;;
        grub|syslinux)
            install_grub ;;
        *) die "неизвестный загрузчик: $RIGEL_BOOTLOADER_RESOLVED" ;;
    esac
    inspect_esp
}

install_systemd_boot() {
    ok "устанавливаем systemd-boot"
    local stage="$RIGEL_STATE_DIR/stage-systemd-boot.sh"
    make_stage_script "$stage" "systemd-boot"

    local cmdline; cmdline="$(kernel_cmdline)"
    cat >>"$stage" <<EOF
mkdir -p /boot/loader/entries

# сам загрузчик + fallback-запись BOOTX64.EFI
bootctl --esp-path=/boot install || bootctl install

cat >/boot/loader/loader.conf <<'LOADEREOF'
default  rigel-linux.conf
timeout  3
console-mode max
editor   no
LOADEREOF

write_entry() {
    local kernel="\$1" entry="/boot/loader/entries/rigel-\$1.conf" ucode=""
    [ -f /boot/intel-ucode.img ] && ucode="/boot/intel-ucode.img"
    [ -f /boot/amd-ucode.img ]   && ucode="/boot/amd-ucode.img"
    {
        echo "title   Rigel Linux (\$kernel)"
        echo "linux   /\$(basename "\$kernel")"
        [ -n "\$ucode" ] && echo "initrd  /\$(basename "\$ucode")"
        echo "initrd  /initramfs-\${kernel#vmlinuz-}.img"
        echo "options $cmdline"
    } >"\$entry"
    echo "  запись: \$entry"
}

for k in $RIGEL_KERNELS; do
    [ -f "/boot/vmlinuz-\$k" ] || { echo "!! нет ядра vmlinuz-\$k"; continue; }
    write_entry "vmlinuz-\$k"
done

# fallback-записи (страховка, если обычный initramfs не собрался после обновления)
for k in $RIGEL_KERNELS; do
    [ -f "/boot/initramfs-\$k-fallback.img" ] || continue
    sed "s|/initramfs-\$k.img|/initramfs-\$k-fallback.img|; s|(\$k)|(\$k, fallback)|" \
        "/boot/loader/entries/rigel-vmlinuz-\$k.conf" >"/boot/loader/entries/rigel-\$k-fallback.conf"
done
EOF
    run_target_script "$stage"
    ok "systemd-boot установлен, записи созданы"
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
    ok "GRUB установлен, конфиг создан"
}

# Что реально лежит на ESP — базовая проверка, что система загрузится
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
