#!/usr/bin/env bash
# Rigel — проверка, что ВСЕ имена пакетов проекта существуют в репозиториях Arch.
#
#   sudo scripts/check-packages.sh          (на Arch Linux или в контейнере archlinux)
#
# Зачем: одна опечатка в списке — и сборка падает через 10 минут на pacstrap.
# Здесь то же самое выясняется за минуту: pacman разрешает зависимости
# по всем спискам сразу (--print, ничего не ставится).
#
# Проверяются:
#   • iso/packages.x86_64              — пакеты живой системы
#   • installer/lib/packages.sh        — базовый набор целевой системы

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MISSING=0
CHECKED=0

c_ok=$'\033[1;32m'; c_err=$'\033[1;31m'; c_info=$'\033[1;36m'; c_off=$'\033[0m'
msg() { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
die() { printf '%s ошибка:%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }

command -v pacman >/dev/null 2>&1 || die "нужен pacman: скрипт запускается на Arch Linux
   (в Windows/CI используйте контейнер archlinux: scripts/build-in-docker.sh либо GitHub Actions)"

if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    msg "включаю multilib в /etc/pacman.conf (нужен для Steam и lib32)"
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>/etc/pacman.conf
fi
msg "обновляю базы пакетов"
pacman -Sy --noconfirm >/dev/null 2>&1 || printf '  (не удалось обновить базы — проверяю по тому, что есть)\n'

# check_list "описание" "пакет1 пакет2 ..."
check_list() {
    local what="$1" pkgs="$2"
    [ -n "${pkgs// /}" ] || return 0
    local count out
    count="$(printf '%s' "$pkgs" | wc -w | tr -d ' ')"
    if out="$(pacman -Sp --print-format '%n' $pkgs 2>&1 >/dev/null)"; then
        printf '  %s[ok]%s   %-28s %s пакетов\n' "$c_ok" "$c_off" "$what" "$count"
    else
        printf '  %s[ОШИБКА]%s %s\n' "$c_err" "$c_off" "$what"
        printf '%s\n' "$out" | sed 's/^/           /'
        MISSING=$((MISSING + 1))
    fi
    CHECKED=$((CHECKED + count))
}

# --- 1. пакеты живой системы -------------------------------------------------
msg "1/2 пакеты живой системы (iso/packages.x86_64)"
check_list "живой ISO" "$(grep -vE '^\s*(#|$)' "$REPO_ROOT/iso/packages.x86_64" | tr -d '\r' | tr '\n' ' ')"

# --- 2. набор целевой системы ------------------------------------------------
msg "2/2 пакеты целевой системы (installer/lib/packages.sh)"
# shellcheck source=/dev/null
. "$REPO_ROOT/installer/lib/common.sh"
# shellcheck source=/dev/null
. "$REPO_ROOT/installer/lib/packages.sh"

RIGEL_KERNELS="linux linux-lts"
RIGEL_UCODE=intel
RIGEL_ROOT_FS=btrfs
RIGEL_HOME_FS=ext4
RIGEL_TRIM=1
RIGEL_IS_LAPTOP=1
RIGEL_VIRT=none
check_list "база системы" "$(system_packages)"
check_list "ucode intel" "$(ucode_packages)"
RIGEL_UCODE=auto

# --- итог -------------------------------------------------------------------
printf '\n'
if [ "$MISSING" -eq 0 ]; then
    printf '%sВсе пакеты найдены%s (проверено имён: %s)\n' "$c_ok" "$c_off" "$CHECKED"
    exit 0
fi
printf '%sПроблемных списков: %d%s (проверено имён: %s)\n' "$c_err" "$MISSING" "$c_off" "$CHECKED"
printf 'Исправьте имена пакетов выше и запустите проверку снова.\n'
exit 1