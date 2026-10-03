#!/usr/bin/env bash
# Rigel installer — самопроверка (запускать в live-ISO или на Arch).
#
#   ./installer/selftest.sh            все проверки
#   ./installer/selftest.sh --short    только список приложений и отчёт о железе
#
# Ничего не изменяет на дисках: только читает файлы и опрашивает систему.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHORT=0
[ "${1:-}" = "--short" ] && SHORT=1
FAILURES=0

pass() { printf '  [OK]   %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

. "$HERE/lib/common.sh"
RIGEL_APPS_DIR="$HERE/apps.d"
. "$HERE/lib/hwdetect.sh"
. "$HERE/lib/packages.sh"
. "$HERE/lib/disk.sh"
. "$HERE/lib/bootloader.sh"
. "$HERE/lib/post.sh"

echo "=== 1. Синтаксис скриптов ==="
while IFS= read -r f; do
    if bash -n "$f" 2>/dev/null; then pass "синтаксис: ${f#$HERE/}"; else fail "синтаксис: ${f#$HERE/}"; fi
done < <(find "$HERE" -name '*.sh' -o -name 'rigel-install' | sort)

echo
echo "=== 2. Необходимые программы live-среды ==="
for cmd in pacstrap arch-chroot genfstab sgdisk parted mkfs.fat mkfs.btrfs mkfs.ext4 blkid lsblk findmnt repo-add whiptail; do
    if have "$cmd"; then pass "$cmd"; else
        case "$cmd" in
            whiptail) fail "$cmd (пакет libnewt — TUI переключится в текстовый режим)" ;;
            *)        fail "$cmd" ;;
        esac
    fi
done

echo
echo "=== 3. Категории приложений (apps.d) ==="
declare -A seen=()
bad=0
while IFS='|' read -r id tab title online desc; do
    [ -n "$id" ] || continue
    if [ -n "${seen[$id]:-}" ]; then fail "дубликат APP_ID: $id"; bad=1; fi
    seen[$id]=1
    case "$tab" in base|pro) : ;; *) fail "$id: неизвестная вкладка '$tab' (ожидается base или pro)"; bad=1 ;; esac
    [ -n "$title" ] || { fail "$id: пустой APP_TITLE"; bad=1; }
    case "$online" in 0|1) : ;; *) fail "$id: APP_ONLINE должен быть 0 или 1"; bad=1 ;; esac
done < <(list_apps)
[ "$bad" = "0" ] && pass "все категории корректны ($(list_apps | wc -l) шт.)"

echo
printf '  %-14s %-5s %-6s %s\n' "ID" "ВКЛ" "СЕТЬ" "НАЗВАНИЕ"
while IFS='|' read -r id tab title online desc; do
    [ -n "$id" ] || continue
    printf '  %-14s %-5s %-6s %s\n' "$id" "$tab" "$([ "$online" = 1 ] && echo online || echo офлайн)" "$title"
done < <(list_apps | sort -t'|' -k2,2 -k1,1)

echo
echo "=== 4. Разбор выбора приложений ==="
sel="base office games drivers"
off="$(app_offline_packages_for "$sel")"
onl="$(app_online_packages_for "$sel")"
pass "офлайн-пакеты: $(wc -w <<<"$off") шт."
pass "онлайн-пакеты: $(wc -w <<<"$onl") шт."
[ -n "$off" ] || fail "офлайн-набор пуст — проверьте APP_ONLINE в apps.d"

echo
echo "=== 5. Логика разметки ==="
for d in /dev/sda /dev/nvme0n1 /dev/mmcblk0 /dev/vda; do
    printf '  %-16s → раздел 2: %s\n' "$d" "$(disk_part "$d" 2)"
done
printf '  45G = %s МиБ, 1GiB = %s МиБ\n' "$(to_mib 45G)" "$(to_mib 1GiB)"
RIGEL_ROOT_SIZE=""
printf '  авто-корень на диске 500 ГиБ: %s МиБ\n' "$(calc_root_mib 512000 1024)"
RIGEL_ROOT_SIZE="200G"
printf '  корень 200G на диске 500 ГиБ: %s МиБ\n' "$(calc_root_mib 512000 1024)"
RIGEL_ROOT_SIZE=""

echo
echo "=== 6. Параметры ядра для загрузчика ==="
RIGEL_ROOT_UUID="TEST-UUID"; RIGEL_ROOT_FS=btrfs; RIGEL_GPU=mesa
printf '  cmdline: %s\n' "$(kernel_cmdline)"

if [ "$SHORT" = "0" ]; then
    echo
    echo "=== 7. Отчёт о железе ==="
    hw_report | sed 's/^/  /'
    echo
    echo "=== 8. Рекомендации для параметров ==="
    hw_recommend | sed 's/^/  /'
fi

echo
if [ "$FAILURES" -eq 0 ]; then
    echo "ИТОГ: все проверки пройдены."
else
    echo "ИТОГ: проблем — $FAILURES. Смотрите строки [FAIL] выше."
fi
exit "$FAILURES"
