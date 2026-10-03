#!/usr/bin/env bash
# Rigel 1 «Orion» — движок установки (неинтерактивный).
#
# Использование:
#   rigel-engine.sh --config /run/rigel/params.env [--dry-run] [--yes] [--step N]
#
#   --config FILE   файл параметров (см. installer/params.example.env)
#   --dry-run       только показать план, ничего не менять на диске
#   --yes           без вопросов (обязательно для неинтерактивного запуска)
#   --offline       принудительно офлайн-режим (не проверять сеть)
#   --online        принудительно считать, что сеть есть
#   --steps         показать список этапов и выйти
#   --step N        выполнить только этап N (для отладки)
#
# Движок — это переработанный archinstall.sh пользователя: интерактивные
# read -p убраны, всё приходит из файла параметров, добавлены проверки,
# офлайн-репозиторий, отдельный /home, btrfs-subvolumes, два ядра,
# загрузчик через systemd-boot/GRUB, snapper и отчёт.

set -euo pipefail

INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$INSTALLER_DIR/lib/common.sh"
# shellcheck source=../lib/hwdetect.sh
. "$INSTALLER_DIR/lib/hwdetect.sh"
# shellcheck source=../lib/disk.sh
. "$INSTALLER_DIR/lib/disk.sh"
# shellcheck source=../lib/packages.sh
. "$INSTALLER_DIR/lib/packages.sh"
# shellcheck source=../lib/bootloader.sh
. "$INSTALLER_DIR/lib/bootloader.sh"
# shellcheck source=../lib/post.sh
. "$INSTALLER_DIR/lib/post.sh"

CONFIG_FILE=""
ONLY_STEP=""

STEPS=(
    "preflight|Проверки окружения и диска"
    "network|Определение сети и репозиториев"
    "disk-partition|Разметка диска"
    "disk-format|Файловые системы и subvolumes"
    "disk-mount|Монтирование и swap"
    "pacstrap|Установка базовых пакетов"
    "fstab|Генерация fstab"
    "post|Локаль, пользователи, сервисы, snapper"
    "bootloader|Загрузчик и записи ядер"
    "extras|Докачка приложений из сети"
    "finish|Итоговый отчёт и очистка"
)

usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --config)  CONFIG_FILE="${2:-}"; shift 2 ;;
        --dry-run) RIGEL_DRY_RUN=1; shift ;;
        --yes)     RIGEL_ASSUME_YES=1; shift ;;
        --offline) RIGEL_ONLINE=0; shift ;;
        --online)  RIGEL_ONLINE=1; shift ;;
        --step)    ONLY_STEP="${2:-}"; shift 2 ;;
        --steps)   for s in "${STEPS[@]}"; do printf '  %-16s %s\n' "${s%%|*}" "${s#*|}"; done; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) die "неизвестный аргумент: $1 (см. --help)" ;;
    esac
done

require_root
[ -n "$CONFIG_FILE" ] || die "не указан --config FILE (пример: installer/params.example.env)"
load_params "$CONFIG_FILE"
validate_params

_init_log
log "Rigel installer, версия $RIGEL_VERSION"
print_summary | tee -a "$RIGEL_LOG" >&2

[ "$RIGEL_DRY_RUN" = "1" ] && warn "РЕЖИМ DRY-RUN: диск не будет изменён"

step_enabled() { [ -z "$ONLY_STEP" ] || [ "$ONLY_STEP" = "$1" ]; }

# ------------------------------------------------------------------ этапы
step_preflight() {
    ok "проверка окружения"
    have pacstrap || die "не найден pacstrap — вы не в live-окружении Arch ISO"
    have sgdisk   || die "не найден sgdisk (пакет gptfdisk)"
    have arch-chroot || die "не найден arch-chroot (пакет arch-install-scripts)"
    have genfstab || die "не найден genfstab"
    [ -d /run/archiso ] || warn "похоже, это не официальная live-среда Arch ISO"

    if is_uefi; then ok "прошивка: UEFI"; else warn "прошивка: BIOS (legacy)"; fi
    local sb; sb="$(detect_secureboot)"
    if [ "$sb" = "enabled" ]; then
        warn "Secure Boot включён — после установки система может не загрузиться."
        warn "Rigel 1 не подписывает загрузчик: выключите Secure Boot в BIOS перед первой загрузкой."
    fi

    check_existing_systems "$RIGEL_DISK"
    if [ "$RIGEL_PART_MODE" = "manual" ]; then
        ok "режим manual: разметку делает пользователь, движок только монтирует"
    else
        validate_target_disk "$RIGEL_DISK"
    fi
}

step_network() {
    resolve_online
    write_install_pacman_conf
    if [ "$RIGEL_ONLINE_RESOLVED" != "1" ] && [ -z "$(app_offline_packages_for "$RIGEL_APPS_BASE $RIGEL_APPS_PRO")" ]; then
        warn "офлайн-режим и пустой набор приложений: система будет минимальной"
    fi
}

step_disk_partition() {
    if [ "$RIGEL_PART_MODE" = "manual" ]; then
        partitions_detect_manual "$RIGEL_DISK"
        return 0
    fi
    partitions_create "$RIGEL_DISK"
}

step_disk_format() {
    local rootpart="${RIGEL_ROOT_PART:-$(disk_part "$RIGEL_DISK" 2)}"
    [ -n "$RIGEL_ROOT_PART" ] || RIGEL_ROOT_PART="$rootpart"
    if [ "$RIGEL_PART_MODE" = "manual" ] && [ "$RIGEL_KEEP_FS" = "1" ]; then
        ok "ручной режим: существующие ФС сохраняются (RIGEL_KEEP_FS=1)"
    else
        mkfs_all
        btrfs_create_subvolumes
    fi
}

step_disk_mount() {
    mount_target
    create_swap "$RIGEL_SWAP"
    write_target_env
    # рекомендации железа — в целевую систему, чтобы потом было видно, что найдено
    hw_recommend >"$RIGEL_MOUNT/root/rigel-hw.txt" 2>/dev/null || true
    hw_report    >"$RIGEL_MOUNT/root/rigel-hw-report.txt" 2>/dev/null || true
}

step_pacstrap() {
    pacstrap_base
    journal_offline_plan
}

step_fstab() { gen_fstab; }

step_post() {
    post_configure
    local online_pkgs
    online_pkgs="$(app_online_packages_for "$RIGEL_APPS_BASE $RIGEL_APPS_PRO")"
    if [ "$RIGEL_ONLINE_RESOLVED" != "1" ] && [ -n "$online_pkgs" ]; then
        write_offline_note "$online_pkgs"
    fi
}

step_bootloader() { install_bootloader; }

step_extras() {
    local online_pkgs
    online_pkgs="$(app_online_packages_for "$RIGEL_APPS_BASE $RIGEL_APPS_PRO")"
    install_online_extras "$online_pkgs"
}

step_finish() {
    cleanup_target_secrets
    sync
    final_report
}

run_step() {
    local name="$1"
    step_enabled "$name" || return 0
    if [ "$RIGEL_DRY_RUN" = "1" ]; then
        log "[dry-run] этап: $name (изменения на диске не выполняются)"
        return 0
    fi
    if ! "$name"; then
        err "этап '$name' завершился с ошибкой — смотрите $RIGEL_LOG"
        on_error
        exit 1
    fi
}

on_error() {
    err "установка прервана. Что делать:"
    err "  1) посмотрите лог: $RIGEL_LOG"
    err "  2) разделы могли быть уже созданы — установку можно продолжить:"
    err "     sudo rigel-engine.sh --config $CONFIG_FILE --yes --step pacstrap"
    err "  3) полностью начать заново: снова запустите установщик"
    umount_target 2>/dev/null || true
}

main() {
    run_step step_preflight
    run_step step_network
    run_step step_disk_partition
    run_step step_disk_format
    run_step step_disk_mount
    run_step step_pacstrap
    run_step step_fstab
    run_step step_post
    run_step step_bootloader
    run_step step_extras
    run_step step_finish

    if [ "$RIGEL_DRY_RUN" = "1" ]; then
        ok "dry-run завершён: параметры корректны, диск не изменялся"
    else
        ok "готово: установка завершена, можно перезагружаться"
    fi
}

main "$@"
