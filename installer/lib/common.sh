#!/usr/bin/env bash
# Rigel installer — общие функции и параметры.
# Подключается остальными модулями: . "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#
# Все модули расчитаны на bash 5 (Arch live-ISO). Никаких внешних зависимостей,
# кроме пакетов, перечисленных в PLAN.md (util-linux, gptfdisk, parted, e2fsprogs,
# btrfs-progs, dosfstools, dialog/libnewt).

RIGEL_LOG="${RIGEL_LOG:-/var/log/rigel-install.log}"
RIGEL_STATE_DIR="${RIGEL_STATE_DIR:-/run/rigel}"
RIGEL_VERSION="${RIGEL_VERSION:-1 (Orion)}"

# ---------------------------------------------------------------- вывод в лог
# Лог пишется и на экран, и в файл. Никаких конвейеров: сбой записи в лог не
# должен прерывать установку (в engine включён set -e).
_init_log() {
    mkdir -p "$(dirname "$RIGEL_LOG")" "$RIGEL_STATE_DIR" 2>/dev/null || true
    if ! : >>"$RIGEL_LOG" 2>/dev/null; then
        RIGEL_LOG="${TMPDIR:-/tmp}/rigel-install.log"
        : >>"$RIGEL_LOG" 2>/dev/null || RIGEL_LOG=/dev/null
    fi
}

_timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

_emit() {
    local level="$1"; shift
    local line="[$(_timestamp)] $level $*"
    printf '%s\n' "$line" >&2
    printf '%s\n' "$line" >>"$RIGEL_LOG" 2>/dev/null || true
}

log()  { _emit "..  " "$@"; }
ok()   { _emit "OK  " "$@"; }
warn() { _emit "WARN" "$@"; }
err()  { _emit "FAIL" "$@"; }
die()  { err "$*"; exit 1; }

# run CMD... — выполняет команду, пишет вывод в лог, при ошибке показывает хвост лога
run() {
    log "+ $*"
    if ! "$@" >>"$RIGEL_LOG" 2>&1; then
        tail -n 25 "$RIGEL_LOG" >&2 || true
        die "команда завершилась с ошибкой: $*"
    fi
}

# run_soft — как run, но ошибка не прерывает установку (для необязательных шагов)
run_soft() {
    log "+ $* (необязательно)"
    "$@" >>"$RIGEL_LOG" 2>&1 || warn "необязательный шаг не удался: $*"
}

have() { command -v "$1" >/dev/null 2>&1; }

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

require_root() { [ "$(id -u)" -eq 0 ] || die "нужны права root: запустите через sudo"; }

# ------------------------------------------------------------------ параметры
apply_defaults() {
    : "${RIGEL_HOSTNAME:=rigel-pc}"
    : "${RIGEL_TIMEZONE:=Europe/Moscow}"
    : "${RIGEL_LANG:=ru_RU.UTF-8}"
    : "${RIGEL_KEYMAP:=ru}"
    : "${RIGEL_LOCALE_MESSAGES:=ru_RU.UTF-8}"
    : "${RIGEL_PART_MODE:=auto}"          # auto | wipe | manual
    : "${RIGEL_ROOT_FS:=btrfs}"           # btrfs | ext4
    : "${RIGEL_HOME_MODE:=separate}"      # separate | none
    : "${RIGEL_HOME_FS:=ext4}"            # ext4 | btrfs
    : "${RIGEL_ESP_MIB:=1024}"            # ESP 1 ГиБ — ядра и initramfs живут на ESP
    : "${RIGEL_ROOT_SIZE:=}"              # напр. 45G; пусто = авто
    : "${RIGEL_SWAP:=file:4G}"            # none | file:4G | partition:4G
    : "${RIGEL_KERNELS:=linux linux-lts}"
    : "${RIGEL_UCODE:=auto}"              # auto | intel | amd | none
    : "${RIGEL_GPU:=auto}"                # auto | nvidia-open | nvidia | mesa
    : "${RIGEL_BOOTLOADER:=grub}"         # grub по умолчанию; systemd-boot — только при явном выборе
    : "${RIGEL_DESKTOP:=hyprland}"        # hyprland | gnome | both | minimal | none
    : "${RIGEL_APPS_BASE:=}"              # id категорий через пробел
    : "${RIGEL_APPS_PRO:=}"
    : "${RIGEL_ONLINE:=auto}"             # auto | 1 | 0
    : "${RIGEL_AUTOLOGIN:=0}"
    : "${RIGEL_FORCE_WIPE:=0}"
    : "${RIGEL_USE_METAPACKAGES:=auto}"   # auto | 1 | 0
    : "${RIGEL_MOUNT:=/mnt}"
    : "${RIGEL_TARGET_LABEL:=rigel}"
    : "${RIGEL_ESP_MOUNT:=/boot}"         # ESP: EFI-загрузчик GRUB и ядра
    : "${RIGEL_USERNAME:=user}"
    : "${RIGEL_ROOT_PASSWORD:=}"
    : "${RIGEL_USER_PASSWORD:=}"
    : "${RIGEL_DRY_RUN:=0}"
}

load_params() {
    local file="$1"
    [ -r "$file" ] || die "не найден или недоступен файл параметров: $file"
    # shellcheck disable=SC1090
    set -a; . "$file"; set +a
    apply_defaults
    RIGEL_PARAMS_FILE="$file"
}

validate_params() {
    [ -n "${RIGEL_DISK:-}" ] || die "не указан целевой диск (RIGEL_DISK=/dev/nvme0n1)"
    [ -n "$RIGEL_HOSTNAME" ] || die "не указано имя компьютера"
    [ -n "$RIGEL_KERNELS" ]  || die "не выбрано ни одного ядра"
    [ -n "$RIGEL_USERNAME" ] || die "не указано имя пользователя"
    case "$RIGEL_USERNAME" in
        [a-z_][a-z0-9_-]*) : ;;
        *) die "имя пользователя должно начинаться со строчной буквы: $RIGEL_USERNAME" ;;
    esac
    [ -n "$RIGEL_ROOT_PASSWORD" ] || die "не задан пароль root"
    [ -n "$RIGEL_USER_PASSWORD" ] || die "не задан пароль пользователя"
    case "$RIGEL_ROOT_FS" in btrfs|ext4) : ;; *) die "RIGEL_ROOT_FS: допустимо btrfs или ext4" ;; esac
    case "$RIGEL_HOME_MODE" in separate|none) : ;; *) die "RIGEL_HOME_MODE: separate или none" ;; esac
    case "$RIGEL_PART_MODE" in auto|wipe|manual) : ;; *) die "RIGEL_PART_MODE: auto | wipe | manual" ;; esac
    case "$RIGEL_DESKTOP" in
        hyprland|gnome|both|minimal|none) : ;;
        *) die "RIGEL_DESKTOP: допустимо hyprland | gnome | both | minimal | none (сейчас: $RIGEL_DESKTOP)" ;;
    esac
}

# ------------------------------------------------------------- диски и разделы
# NVMe/eMMC нумеруют разделы через «p»: /dev/nvme0n1 → /dev/nvme0n1p1
part_suffix() {
    case "$1" in
        *nvme*|*mmcblk*|*loop*|*md*) printf 'p' ;;
        *) printf '' ;;
    esac
}

# disk_part /dev/nvme0n1 2 → /dev/nvme0n1p2 ; disk_part /dev/sda 2 → /dev/sda2
disk_part() { printf '%s%s%s' "$1" "$(part_suffix "$1")" "$2"; }

# 45G → 46080 (МиБ)
to_mib() {
    local v="$1" n
    case "$v" in
        *[Tt][Ii][Bb]) n="${v%[Tt][Ii][Bb]}"; printf '%s' "$((n * 1024 * 1024))" ;;
        *[Gg][Ii][Bb]) n="${v%[Gg][Ii][Bb]}"; printf '%s' "$((n * 1024))" ;;
        *[Mm][Ii][Bb]) n="${v%[Mm][Ii][Bb]}"; printf '%s' "$n" ;;
        *[Tt])         n="${v%[Tt]}";         printf '%s' "$((n * 1000 * 1000))" ;;
        *[Gg])         n="${v%[Gg]}";         printf '%s' "$((n * 1000))" ;;
        *[Mm])         n="${v%[Mm]}";         printf '%s' "$n" ;;
        *)             printf '%s' "$v" ;;
    esac
}

disk_size_mib() { printf '%s' "$(( $(blockdev --getsize64 "$1") / 1024 / 1024 ))"; }

is_uefi() { [ -d /sys/firmware/efi ]; }

online() {
    case "$RIGEL_ONLINE" in
        1) return 0 ;;
        0) return 1 ;;
    esac
    if have curl; then curl -fsS --max-time 8 -o /dev/null https://archlinux.org/ 2>/dev/null; else
        ping -c1 -W3 archlinux.org >/dev/null 2>&1
    fi
}

# ------------------------------------------------- целевая система (chroot)
# Переменные передаются в chroot не через heredoc, а через файл — так исключены
# пустые $username/$password внутри chroot (главная ошибка исходного скрипта).
write_target_env() {
    local f="$RIGEL_MOUNT/root/rigel-target.env"
    install -d -m 0700 "$RIGEL_MOUNT/root"
    cat >"$f" <<EOF
RIGEL_VERSION='$RIGEL_VERSION'
RIGEL_HOSTNAME='$RIGEL_HOSTNAME'
RIGEL_TIMEZONE='$RIGEL_TIMEZONE'
RIGEL_LANG='$RIGEL_LANG'
RIGEL_KEYMAP='$RIGEL_KEYMAP'
RIGEL_LOCALE_MESSAGES='$RIGEL_LOCALE_MESSAGES'
RIGEL_USERNAME='$RIGEL_USERNAME'
RIGEL_ROOT_PASSWORD='$RIGEL_ROOT_PASSWORD'
RIGEL_USER_PASSWORD='$RIGEL_USER_PASSWORD'
RIGEL_AUTOLOGIN='$RIGEL_AUTOLOGIN'
RIGEL_KERNELS='$RIGEL_KERNELS'
RIGEL_UCODE='$RIGEL_UCODE'
RIGEL_GPU='$RIGEL_GPU'
RIGEL_DESKTOP='$RIGEL_DESKTOP'
RIGEL_BOOTLOADER='$RIGEL_BOOTLOADER'
RIGEL_ROOT_FS='$RIGEL_ROOT_FS'
RIGEL_ROOT_UUID='${RIGEL_ROOT_UUID:-}'
RIGEL_BTRFS_SUBVOL='${RIGEL_BTRFS_SUBVOL:-}'
RIGEL_TRIM='${RIGEL_TRIM:-0}'
RIGEL_ONLINE='${RIGEL_ONLINE_RESOLVED:-0}'
EOF
    chmod 600 "$f"
}

# run_target_script FILE — копирует скрипт в цель и выполняет его в chroot
run_target_script() {
    local src="$1" name
    name="$(basename "$src")"
    install -m 0755 "$src" "$RIGEL_MOUNT/root/$name"
    run arch-chroot "$RIGEL_MOUNT" "/root/$name"
    rm -f "$RIGEL_MOUNT/root/$name"
}

# Генерирует скрипт-этап во временном файле с общим прологом
make_stage_script() {
    local out="$1" title="$2"
    cat >"$out" <<EOF
#!/bin/bash
set -euo pipefail
title='$title'
echo "=== \$title ==="
set -a; . /root/rigel-target.env; set +a
EOF
}

chroot_run() { run arch-chroot "$RIGEL_MOUNT" /bin/bash -c "$*"; }

# ------------------------------------------------------------------ сводка
print_summary() {
    cat <<EOF
Rigel $RIGEL_VERSION — параметры установки
  диск:            ${RIGEL_DISK:-не выбран}
  режим разметки:  $RIGEL_PART_MODE
  ESP:             ${RIGEL_ESP_MIB} МиБ → $RIGEL_ESP_MOUNT
  корень:          $RIGEL_ROOT_FS ${RIGEL_ROOT_SIZE:+($RIGEL_ROOT_SIZE)}
  /home:           $RIGEL_HOME_MODE${RIGEL_HOME_MODE:+ ($RIGEL_HOME_FS)}
  swap:            $RIGEL_SWAP
  ядра:            $RIGEL_KERNELS
  ucode:           $RIGEL_UCODE
  GPU:             $RIGEL_GPU
  загрузчик:       $RIGEL_BOOTLOADER
  рабочий стол:    $RIGEL_DESKTOP
  приложения:      базовые=[$RIGEL_APPS_BASE] про=[$RIGEL_APPS_PRO]
  сеть:            RIGEL_ONLINE=$RIGEL_ONLINE
  пользователь:    $RIGEL_USERNAME@$RIGEL_HOSTNAME, автовход=$RIGEL_AUTOLOGIN
  локаль:          $RIGEL_LANG, раскладка=$RIGEL_KEYMAP, зона=$RIGEL_TIMEZONE
  живой режим:     dry-run=$RIGEL_DRY_RUN
EOF
}

_init_log
apply_defaults
