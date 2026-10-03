#!/usr/bin/env bash
# Rigel — запись готового ISO на флешку.
#
#   sudo scripts/make-usb.sh /dev/sdX [out/rigel-1.0-x86_64.iso]
#
# Скрипт проверяет, что это действительно съёмный диск, что он не смонтирован,
# и просит ввести имя устройства руками (защита от записи не на ту флешку).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

c_ok=$'\033[1;32m'; c_err=$'\033[1;31m'; c_warn=$'\033[1;33m'; c_info=$'\033[1;36m'; c_off=$'\033[0m'
msg() { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
die() { printf '%s ошибка:%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }

DEVICE="${1:-}"
ISO="${2:-}"

[ -n "$DEVICE" ] || die "укажите устройство: sudo scripts/make-usb.sh /dev/sdX [файл.iso]"
[ -b "$DEVICE" ] || die "$DEVICE не является блочным устройством"

if [ -z "$ISO" ]; then
    ISO="$(ls -1t "$REPO_ROOT"/out/rigel-*.iso 2>/dev/null | head -n1 || true)"
fi
[ -n "$ISO" ] && [ -f "$ISO" ] || die "не найден ISO (сначала соберите: sudo scripts/build-iso.sh)"

[ "$(id -u)" -eq 0 ] || { command -v sudo >/dev/null 2>&1 && exec sudo -E bash "$0" "$@"; die "нужны права root"; }

MODEL="$(lsblk -dno MODEL "$DEVICE" 2>/dev/null | xargs || true)"
SIZE="$(lsblk -dno SIZE "$DEVICE" 2>/dev/null | xargs || true)"
RM="$(lsblk -dno RM "$DEVICE" 2>/dev/null | xargs || true)"
MOUNTS="$(lsblk -rno MOUNTPOINT "$DEVICE" 2>/dev/null | grep -v '^$' || true)"

printf '\n  Устройство: %s\n  Модель:     %s\n  Размер:     %s\n  ISO:        %s (%s)\n\n' \
    "$DEVICE" "${MODEL:-неизвестно}" "${SIZE:-?}" "$ISO" "$(du -h "$ISO" | cut -f1)"

[ "$RM" = "1" ] || printf '  %sВНИМАНИЕ: устройство не помечено как съёмное (RM=%s).%s\n' "$c_warn" "${RM:-?}" "$c_off"
if [ -n "$MOUNTS" ]; then
    printf '  %sРазделы смонтированы:%s\n%s\n' "$c_warn" "$c_off" "$MOUNTS"
    die "отмонтируйте их (umount) и повторите — иначе запись может повредить файловую систему"
fi

printf '  Все данные на %s будут УНИЧТОЖЕНЫ.\n' "$DEVICE"
printf '  Введите путь устройства целиком для подтверждения: '
read -r CONFIRM
[ "$CONFIRM" = "$DEVICE" ] || die "подтверждение не совпало — ничего не записано"

msg "пишу образ (не вынимайте флешку)"
dd if="$ISO" of="$DEVICE" bs=4M status=progress conv=fsync oflag=direct
sync
msg "готово. Флешку можно вынимать, загружайтесь с неё (UEFI: обычно F12/F8 при старте)"
printf '  %sНе забудьте выключить Secure Boot, если система не грузится.%s\n' "$c_warn" "$c_off"
