#!/usr/bin/env bash
# Rigel installer — разметка диска, файловые системы, subvolumes, монтирование.
#
# Схема по умолчанию (PLAN.md, раздел 7.5.1):
#   p1  ESP     1 ГиБ   FAT32  → /boot   (EFI-загрузчик GRUB и ядра)
#   p2  корень  45 ГиБ  btrfs  → /       (@ и @snapshots создаются сразу, до pacstrap)
#   p3  /home   остаток ext4   → /home
#   swap        4 ГиБ   файлом внутри корня

RIGEL_ESP_PART=""
RIGEL_ROOT_PART=""
RIGEL_HOME_PART=""
RIGEL_ROOT_UUID=""
RIGEL_HOME_UUID=""
RIGEL_BTRFS_SUBVOL=""
ROOT_MOUNT_OPTS=""

# ------------------------------------------------------------------ проверки
validate_target_disk() {
    local disk="$1"
    [ -n "$disk" ] || die "не указан целевой диск"
    [ -b "$disk" ] || die "не блочное устройство: $disk"
    case "$disk" in
        *[0-9]) die "укажите диск целиком (/dev/nvme0n1 или /dev/sda), а не раздел $disk" ;;
    esac

    local size_mib; size_mib="$(disk_size_mib "$disk")"
    [ "$size_mib" -ge 20480 ] || die "диск $disk слишком мал: ${size_mib} МиБ (нужно ≥ 20 ГиБ)"
    ok "диск $disk: $((size_mib / 1024)) ГиБ"

    # Ничего из этого диска не должно быть смонтировано
    if lsblk -rno MOUNTPOINT "$disk" | grep -q '^/'; then
        lsblk -rno NAME,MOUNTPOINT "$disk" >&2
        die "на $disk есть смонтированные разделы — отмонтируйте их перед установкой"
    fi

    # Защита от записи установщика на собственный носитель
    local live_src live_disk
    if [ -e /run/archiso/bootmnt ]; then
        live_src="$(findmnt -rno SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
        if [ -n "$live_src" ]; then
            live_disk="/dev/$(lsblk -rno PKNAME "$live_src" 2>/dev/null | head -n1)"
            [ "$live_disk" = "$disk" ] && die "$disk — это носитель, с которого загружен установщик"
        fi
    fi
    ok "проверки диска пройдены"
}

# Существующие ОС: без явного подтверждения ничего не стираем
check_existing_systems() {
    local disk="$1" ntfs
    ntfs="$(lsblk -rno FSTYPE "$disk" 2>/dev/null | grep -Eic 'ntfs' || true)"
    if [ "${ntfs:-0}" -gt 0 ] && [ "$RIGEL_FORCE_WIPE" != "1" ]; then
        lsblk -rno NAME,SIZE,FSTYPE,LABEL "$disk" >&2
        die "на $disk найдены NTFS-разделы (похоже на Windows). Установка остановлена, чтобы не потерять данные. Если это осознанное решение — задайте RIGEL_FORCE_WIPE=1"
    fi
    [ "${ntfs:-0}" -gt 0 ] && warn "NTFS-разделы будут уничтожены (RIGEL_FORCE_WIPE=1)"
    return 0
}

# ---------------------------------------------------------------- разметка
calc_root_mib() {
    local disk_mib="$1" esp_mib="$2"
    local avail=$((disk_mib - esp_mib - 8))       # 8 МиБ запас на выравнивание
    if [ -n "$RIGEL_ROOT_SIZE" ]; then
        local want; want="$(to_mib "$RIGEL_ROOT_SIZE")"
        if [ "$want" -ge "$avail" ]; then
            warn "RIGEL_ROOT_SIZE=$RIGEL_ROOT_SIZE больше доступного места — отдаём корню всё"
            printf '%s' "$avail"
        else
            printf '%s' "$want"
        fi
        return
    fi
    # Авто: 45 ГиБ, но не больше 60% диска и не меньше 20 ГиБ
    local auto=46080
    local max_allowed=$((avail * 60 / 100))
    [ "$auto" -gt "$max_allowed" ] && auto="$max_allowed"
    [ "$auto" -lt 20480 ] && auto=20480
    [ "$auto" -gt "$avail" ] && auto="$avail"
    printf '%s' "$auto"
}

partitions_create() {
    local disk="$1" disk_mib esp_mib root_mib
    disk_mib="$(disk_size_mib "$disk")"
    esp_mib="$(to_mib "${RIGEL_ESP_MIB}MiB")"
    root_mib="$(calc_root_mib "$disk_mib" "$esp_mib")"

    partprobe "$disk" >/dev/null 2>&1 || true

    run wipefs -a "$disk"
    run sgdisk --zap-all "$disk"
    run sgdisk -n "1:1MiB:${esp_mib}MiB" -t 1:ef00 -c 1:ESP "$disk"
    run sgdisk -n "2:0:+${root_mib}MiB" -t 2:8300 -c 2:rigel-root "$disk"
    if [ "$RIGEL_HOME_MODE" = "separate" ]; then
        run sgdisk -n "3:0:0" -t 3:8300 -c 3:rigel-home "$disk"
    fi

    partprobe "$disk"
    udevadm settle 2>/dev/null || sleep 2

    RIGEL_ESP_PART="$(disk_part "$disk" 1)"
    RIGEL_ROOT_PART="$(disk_part "$disk" 2)"
    [ "$RIGEL_HOME_MODE" = "separate" ] && RIGEL_HOME_PART="$(disk_part "$disk" 3)"

    [ -b "$RIGEL_ESP_PART" ]  || die "не появился раздел ESP: $RIGEL_ESP_PART"
    [ -b "$RIGEL_ROOT_PART" ] || die "не появился корневой раздел: $RIGEL_ROOT_PART"
    ok "разметка готова: ESP $RIGEL_ESP_PART, корень $RIGEL_ROOT_PART ${RIGEL_HOME_PART:+, home $RIGEL_HOME_PART}"
}

# Для ручной разметки: пользователь сам создал разделы, мы их только валидируем
partitions_detect_manual() {
    local disk="$1" esp root home
    esp="$(lsblk -rno NAME,PARTTYPENAME "$disk" 2>/dev/null | awk -F' ' '$2 ~ /EFI/ {print "/dev/"$1}' | head -n1)"
    [ -n "$esp" ] || esp="$(lsblk -rno NAME,FSTYPE "$disk" 2>/dev/null | awk '$2=="vfat"{print "/dev/"$1}' | head -n1)"
    [ -n "$esp" ] || die "на $disk не найден EFI-раздел (FAT32). Создайте его вручную и повторите"

    local parts=()
    while IFS= read -r line; do parts+=("$line"); done < <(lsblk -rno NAME,FSTYPE "$disk" | awk -v e="${esp#/dev/}" '$1!=e && $2!=""{print "/dev/"$1}')
    root="${parts[0]:-}"
    home="${parts[1]:-}"
    [ -n "$root" ] || die "на $disk не найден корневой раздел"

    RIGEL_ESP_PART="$esp"
    RIGEL_ROOT_PART="$root"
    RIGEL_HOME_PART="$home"
    ok "ручная разметка: ESP $esp, корень $root ${home:+, home $home}"
}

# ------------------------------------------------------------------- ФС и монтирование
mkfs_all() {
    run mkfs.fat -F 32 -n ESP "$RIGEL_ESP_PART"

    if [ "$RIGEL_ROOT_FS" = "btrfs" ]; then
        run mkfs.btrfs -f -L "${RIGEL_TARGET_LABEL}-root" "$RIGEL_ROOT_PART"
        ROOT_MOUNT_OPTS="subvol=@,noatime,compress=zstd:3"
    else
        run mkfs.ext4 -F -L "${RIGEL_TARGET_LABEL}-root" "$RIGEL_ROOT_PART"
        ROOT_MOUNT_OPTS="noatime"
    fi

    if [ -n "$RIGEL_HOME_PART" ]; then
        if [ "$RIGEL_HOME_FS" = "btrfs" ]; then
            run mkfs.btrfs -f -L "${RIGEL_TARGET_LABEL}-home" "$RIGEL_HOME_PART"
        else
            run mkfs.ext4 -F -L "${RIGEL_TARGET_LABEL}-home" "$RIGEL_HOME_PART"
        fi
    fi
    ok "файловые системы созданы"
}

btrfs_create_subvolumes() {
    [ "$RIGEL_ROOT_FS" = "btrfs" ] || return 0
    local tmp="$RIGEL_STATE_DIR/btrfs-top"
    mkdir -p "$tmp"
    run mount "$RIGEL_ROOT_PART" "$tmp"
    run btrfs subvolume create "$tmp/@"
    run btrfs subvolume create "$tmp/@snapshots"
    run umount "$tmp"
    rmdir "$tmp" 2>/dev/null || true
    ok "subvolumes @ и @snapshots созданы (шпаргалка: до pacstrap, конвертер не нужен)"
}

mount_target() {
    run mkdir -p "$RIGEL_MOUNT"
    run mount -o "$ROOT_MOUNT_OPTS" "$RIGEL_ROOT_PART" "$RIGEL_MOUNT"
    run mkdir -p "$RIGEL_MOUNT$RIGEL_ESP_MOUNT" "$RIGEL_MOUNT/home"
    run mount "$RIGEL_ESP_PART" "$RIGEL_MOUNT$RIGEL_ESP_MOUNT"
    [ -n "$RIGEL_HOME_PART" ] && run mount "$RIGEL_HOME_PART" "$RIGEL_MOUNT/home"

    if [ "$RIGEL_ROOT_FS" = "btrfs" ]; then
        run mkdir -p "$RIGEL_MOUNT/.snapshots"
        run mount -o subvol=@snapshots "$RIGEL_ROOT_PART" "$RIGEL_MOUNT/.snapshots"
    fi

    RIGEL_ROOT_UUID="$(blkid -s UUID -o value "$RIGEL_ROOT_PART")"
    [ "$RIGEL_ROOT_FS" = "btrfs" ] && RIGEL_BTRFS_SUBVOL="@"
    ok "целевая система смонтирована в $RIGEL_MOUNT (root UUID=$RIGEL_ROOT_UUID)"
}

create_swap() {
    local spec="$1" size file
    case "$spec" in
        none|"") ok "swap не создаём"; return 0 ;;
        file:*)  size="${spec#file:}" ;;
        partition:*) warn "swap-раздел не создаём в Rigel 1, используем файл"; size="${spec#partition:}" ;;
        *) die "RIGEL_SWAP: ожидается none или file:4G, получено '$spec'" ;;
    esac
    file="$RIGEL_MOUNT/swapfile"

    if [ "$RIGEL_ROOT_FS" = "btrfs" ]; then
        # btrfs: файл подкачки должен быть без CoW и без сжатия
        run truncate -s 0 "$file"
        run_soft chattr +C "$file"
        if ! fallocate -l "$size" "$file" >>"$RIGEL_LOG" 2>&1; then
            warn "fallocate не сработал на btrfs — заполняем dd"
            run dd if=/dev/zero of="$file" bs=1M count="$(to_mib "$size")" status=none
        fi
    else
        run fallocate -l "$size" "$file"
    fi

    run chmod 600 "$file"
    run mkswap "$file"
    run swapon "$file"
    ok "swap-файл $size создан и включён"
}

umount_target() {
    for m in "$RIGEL_MOUNT/.snapshots" "$RIGEL_MOUNT/boot" "$RIGEL_MOUNT/home" "$RIGEL_MOUNT"; do
        mountpoint -q "$m" 2>/dev/null && umount -R "$m" >/dev/null 2>&1 || true
    done
    swapoff "$RIGEL_MOUNT/swapfile" 2>/dev/null || true
    ok "разделы отмонтированы"
}

# ------------------------------------------------------------------- итог
disk_summary() {
    [ -n "$RIGEL_DISK" ] || return 0
    lsblk -rno NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$RIGEL_DISK" 2>/dev/null | sed 's/^/    /'
}
