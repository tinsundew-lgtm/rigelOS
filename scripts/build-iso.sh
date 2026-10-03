#!/usr/bin/env bash
# Rigel 1 «Orion» — сборка ISO.
#
#   sudo scripts/build-iso.sh                     обычная сборка (~1.2–1.8 ГиБ ISO)
#   sudo scripts/build-iso.sh --offline           + локальный репозиторий на ISO
#                                                 (установка без интернета, ISO больше)
#   sudo scripts/build-iso.sh --keep-work         не удалять рабочую папку (отладка)
#   sudo scripts/build-iso.sh --no-deps           не ставить пакеты сборки (в контейнере/CI)
#
# Скрипт: проверяет окружение → ставит зависимости → копирует установщик внутрь
# профиля → (опционально) собирает офлайн-репозиторий → запускает mkarchiso →
# проверяет, что в ISO действительно лежат ядро, initramfs и загрузчик.
#
# Запускать нужно на Arch Linux (или в контейнере archlinux — см. BUILD.md).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$REPO_ROOT/iso"
INSTALLER_SRC="$REPO_ROOT/installer"
STAGE_DIR="$PROFILE/airootfs/usr/local/lib/rigel-installer"
ISO_REPO_DIR="$PROFILE/airootfs/usr/local/share/rigel/repo/x86_64"
OUT_DIR="$REPO_ROOT/out"
WORK_DIR="${WORK_DIR:-/tmp/rigel-work}"

DO_DEPS=1
DO_OFFLINE=0
KEEP_WORK=0

c_ok=$'\033[1;32m'; c_err=$'\033[1;31m'; c_info=$'\033[1;36m'; c_off=$'\033[0m'
msg()  { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$c_ok" "$c_off" "$*"; }
die()  { printf '%s ошибка:%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --offline)   DO_OFFLINE=1; shift ;;
        --no-deps)   DO_DEPS=0; shift ;;
        --keep-work) KEEP_WORK=1; shift ;;
        --out)       OUT_DIR="${2:-}"; shift 2 ;;
        --work)      WORK_DIR="${2:-}"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "неизвестный параметр: $1 (см. --help)" ;;
    esac
done

# --------------------------------------------------------------- проверки
[ -f "$PROFILE/profiledef.sh" ] || die "не найден профиль: $PROFILE/profiledef.sh"
[ -d "$INSTALLER_SRC" ]         || die "не найдена папка установщика: $INSTALLER_SRC"
if [ ! -f /etc/arch-release ]; then
    die "сборка возможна только на Arch Linux (нет /etc/arch-release).
   Варианты без локального Linux:
     • GitHub Actions:  .github/workflows/build-iso.yml (кнопка Run workflow)
     • Docker:          scripts/build-in-docker.sh   (или .ps1 в Windows)
     • Подробности:     BUILD.md"
fi

if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || die "нужны права root (mkarchiso требует loop-устройства и mount)"
    msg "перезапускаю с sudo"
    exec sudo -E bash "$0" "$@"
fi

# --------------------------------------------------------------- зависимости
if [ "$DO_DEPS" = 1 ]; then
    msg "ставлю пакеты для сборки (archiso, syslinux, grub, squashfs-tools, libisoburn...)"
    pacman -S --needed --noconfirm \
        archiso syslinux grub mtools libisoburn squashfs-tools \
        dosfstools e2fsprogs libarchive zstd >/dev/null
    ok "зависимости на месте"
fi

# проверяем инструменты только после установки зависимостей
for cmd in mkarchiso bsdtar sha256sum pacman; do
    command -v "$cmd" >/dev/null 2>&1 || die "не найдена команда: $cmd (нужен пакет archiso или libarchive)"
done

# --------------------------------------------- переводы строк (LF)
# Страховка для правок, сделанных в Windows: CRLF в shebang ломает запуск скриптов.
msg "проверяю переводы строк"
crlf_fixed=0
while IFS= read -r f; do
    size="$(wc -c <"$f" 2>/dev/null || echo 0)"
    size_no_cr="$(tr -d '\r' <"$f" 2>/dev/null | wc -c)"
    if [ "$size" != "$size_no_cr" ]; then
        sed -i 's/\r$//' "$f"
        crlf_fixed=$((crlf_fixed + 1))
    fi
done < <(find "$REPO_ROOT" -type f -not -path '*/out/*' -not -path '*/work/*' -not -path '*/.git/*')
if [ "$crlf_fixed" -eq 0 ]; then ok "переводы строк в порядке (LF)"; else ok "исправлено CRLF в файлах: $crlf_fixed"; fi

# --------------------------------------------------- стейджинг установщика
msg "копирую установщик в профиль: installer/ → ${STAGE_DIR#$REPO_ROOT/}"
rm -rf "$STAGE_DIR"
mkdir -p "$(dirname "$STAGE_DIR")"
cp -a "$INSTALLER_SRC" "$STAGE_DIR"
chmod +x "$STAGE_DIR/rigel-install" "$STAGE_DIR/engine/rigel-engine.sh" "$STAGE_DIR/selftest.sh" \
         "$STAGE_DIR/tests/logic-test.sh" 2>/dev/null || true
chmod +x "$PROFILE/airootfs/usr/local/bin/rigel-install" \
         "$PROFILE/airootfs/usr/local/bin/rigel-welcome" \
         "$PROFILE/airootfs/usr/local/bin/rigel-live-setup" 2>/dev/null || true
ok "установщик внутри профиля ($(find "$STAGE_DIR" -type f | wc -l) файлов)"

# ------------------------------------------------- офлайн-репозиторий (опция)
if [ "$DO_OFFLINE" = 1 ]; then
    msg "собираю локальный репозиторий на ISO (установка без интернета)"
    mkdir -p "$ISO_REPO_DIR"
    # качаем только те пакеты, что нужны живой системе и офлайн-установке
    mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$PROFILE/packages.x86_64" | tr -d '\r')
    pacman -Sy --noconfirm >/dev/null
    pacman -Sw --noconfirm --needed --cachedir /var/cache/pacman/pkg "${PKGS[@]}" >/dev/null
    cp -n /var/cache/pacman/pkg/*.pkg.tar.* "$ISO_REPO_DIR/" 2>/dev/null || true
    ( cd "$ISO_REPO_DIR" && repo-add -q rigel-iso.db.tar.zst ./*.pkg.tar.* >/dev/null )
    ok "в репозитории $(ls "$ISO_REPO_DIR"/*.pkg.tar.* | wc -l) пакетов"
fi

# ------------------------------------------------------------------ mkarchiso
mkdir -p "$OUT_DIR" "$WORK_DIR"
msg "запускаю mkarchiso (это долго: от 15 минут на быстрой машине)"
rm -f "$OUT_DIR"/rigel-*.iso
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE"

ISO="$(ls -1t "$OUT_DIR"/rigel-*.iso 2>/dev/null | head -n1 || true)"
[ -n "$ISO" ] || die "mkarchiso завершился, но ISO не найден в $OUT_DIR"

# ------------------------------------------------- проверка содержимого ISO
msg "проверяю, что внутри ISO есть ядро, initramfs и загрузчики"
LIST="$(bsdtar -tf "$ISO")"
missing=0
check_in_iso() {
    if printf '%s\n' "$LIST" | grep -qx "$1"; then ok "$1"; else printf '  %sНЕТ%s %s\n' "$c_err" "$c_off" "$1"; missing=$((missing+1)); fi
}
check_in_iso "rigel/x86_64/airootfs.sfs"
check_in_iso "rigel/boot/x86_64/vmlinuz-linux"
check_in_iso "rigel/boot/x86_64/initramfs-linux.img"
check_in_iso "EFI/BOOT/BOOTx64.EFI"
check_in_iso "loader/loader.conf"
[ "$missing" -eq 0 ] || die "в ISO не хватает $missing важных файлов — загрузка не сработает"

# --------------------------------------------------------------------- итог
SIZE="$(du -h "$ISO" | cut -f1)"
SUM="$(sha256sum "$ISO" | cut -d' ' -f1)"
printf '%s\n' "$SUM  $(basename "$ISO")" > "$ISO.sha256"

if [ "$KEEP_WORK" != 1 ]; then
    rm -rf "$WORK_DIR"
else
    msg "рабочая папка сохранена: $WORK_DIR"
fi

cat <<EOF

${c_ok}ISO готов${c_off}

  файл:    $ISO
  размер:  $SIZE
  sha256:  $SUM

  Записать на флешку (Linux):   sudo scripts/make-usb.sh /dev/sdX "$ISO"
  Записать на флешку (Windows): Rufus → режим «DD-образ», или balenaEtcher
  Проверить без перезагрузки:   qemu-system-x86_64 -m 4G -enable-kvm -cdrom "$ISO" -boot d
EOF
