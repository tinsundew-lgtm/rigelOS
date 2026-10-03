#!/usr/bin/env bash
# Rigel installer — тесты чистой логики (без дисков и без Arch).
#
# Запускается где угодно, где есть bash: в live-ISO, на Arch, в Git Bash.
#   bash installer/tests/logic-test.sh
#
# Проверяются: имена разделов для NVMe/SATA, расчёт размеров, парсинг категорий
# приложений, сборка параметров для chroot (та самая ошибка исходного скрипта),
# валидация параметров и параметры ядра.
#
# ВАЖНО: имена t_ok/t_fail/t_check, а не ok/fail — иначе их перезапишет common.sh.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
INST="$ROOT/installer"

PASS=0
FAIL=0
SKIP=0
t_ok()   { PASS=$((PASS + 1)); printf '  [ok]   %s\n' "$*"; }
t_bad()  { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
t_skip() { SKIP=$((SKIP + 1)); printf '  [skip] %s\n' "$*"; }
t_check() { if [ "$2" = "$3" ]; then t_ok "$1 → $2"; else t_bad "$1 → получено '$2', ожидалось '$3'"; fi; }
t_check_ne() { if [ "$2" != "$3" ]; then t_ok "$1"; else t_bad "$1 (не должно быть '$3')"; fi; }

RIGEL_APPS_DIR="$INST/apps.d"
RIGEL_LOG="${TMPDIR:-/tmp}/rigel-logic-test.log"

. "$INST/lib/common.sh"
. "$INST/lib/disk.sh"
. "$INST/lib/packages.sh"
. "$INST/lib/bootloader.sh"
. "$INST/lib/hwdetect.sh"

is_windows_shell() { case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac; }

echo "=== 1. Имена разделов ==="
t_check "/dev/sda 2"     "$(disk_part /dev/sda 2)"      "/dev/sda2"
t_check "/dev/nvme0n1 2" "$(disk_part /dev/nvme0n1 2)"  "/dev/nvme0n1p2"
t_check "/dev/nvme0n1 1" "$(disk_part /dev/nvme0n1 1)"  "/dev/nvme0n1p1"
t_check "/dev/mmcblk0 3" "$(disk_part /dev/mmcblk0 3)"  "/dev/mmcblk0p3"
t_check "/dev/vda 2"     "$(disk_part /dev/vda 2)"      "/dev/vda2"
t_check "/dev/md0 1"     "$(disk_part /dev/md0 1)"      "/dev/md0p1"

echo
echo "=== 2. Перевод размеров ==="
t_check "45G"    "$(to_mib 45G)"    "45000"
t_check "1GiB"   "$(to_mib 1GiB)"   "1024"
t_check "512MiB" "$(to_mib 512MiB)" "512"
t_check "2T"     "$(to_mib 2T)"     "2000000"

echo
echo "=== 3. Авторазмер корня ==="
RIGEL_ROOT_SIZE=""
t_check "диск 500 ГиБ, авто"        "$(calc_root_mib 512000 1024)" "46080"
t_check "диск 30 ГиБ, авто"         "$(calc_root_mib 30000 1024)"  "20480"
RIGEL_ROOT_SIZE="200G"
t_check "диск 500 ГиБ, корень 200G" "$(calc_root_mib 512000 1024)" "200000"
RIGEL_ROOT_SIZE="900G"
t_check "корень больше диска"       "$(calc_root_mib 512000 1024)" "510968"
RIGEL_ROOT_SIZE=""

echo
echo "=== 4. Категории приложений (apps.d) ==="
t_check "всего категорий"   "$(list_apps | wc -l | tr -d ' ')"                    "11"
t_check "вкладка «Базовые»" "$(list_apps | awk -F'|' '$2=="base"' | wc -l | tr -d ' ')" "6"
t_check "вкладка «Про»"     "$(list_apps | awk -F'|' '$2=="pro"' | wc -l | tr -d ' ')"  "5"
t_check "дубликаты id"      "$(trim "$(list_apps | cut -d'|' -f1 | sort | uniq -d | tr '\n' ' ')")" ""
t_check "APP_TITLE у base"  "$(app_field base APP_TITLE)" "База: браузер, файлы, терминал"
t_check_ne "APP_PACKAGES у games" "$(app_field games APP_PACKAGES)" ""
t_check "APP_KIND у manual-boot"  "$(app_field manual-boot APP_KIND)" "option"

echo
echo "=== 5. Разделение офлайн/онлайн ==="
sel="base office games drivers"
off="$(app_offline_packages_for "$sel")"
onl="$(app_online_packages_for "$sel")"
case "$off" in *firefox*)          t_ok "офлайн содержит firefox" ;;    *) t_bad "офлайн без firefox: $off" ;; esac
case "$off" in *libreoffice-fresh*) t_ok "офлайн содержит libreoffice" ;; *) t_bad "офлайн без libreoffice: $off" ;; esac
case "$off" in *steam*)            t_bad "steam попал в офлайн-набор" ;; *) t_ok "steam не в офлайне" ;; esac
case "$onl" in *steam*)            t_ok "онлайн содержит steam" ;;      *) t_bad "онлайн без steam: $onl" ;; esac
case "$onl" in *firefox*)          t_bad "firefox попал в онлайн-набор" ;; *) t_ok "firefox не в онлайне" ;; esac

echo
echo "=== 6. Параметры ядра ==="
RIGEL_ROOT_UUID="TEST-UUID"; RIGEL_ROOT_FS=btrfs; RIGEL_GPU=mesa
t_check "btrfs + mesa" "$(kernel_cmdline)" "root=UUID=TEST-UUID rw quiet rootflags=subvol=@"
RIGEL_ROOT_FS=ext4
t_check "ext4" "$(kernel_cmdline)" "root=UUID=TEST-UUID rw quiet"
RIGEL_ROOT_FS=btrfs

echo
echo "=== 7. Параметры для chroot (проверка ошибки №1 исходного скрипта) ==="
TMP="$(mktemp -d)"
RIGEL_MOUNT="$TMP"
RIGEL_HOSTNAME="rigel-pc"
RIGEL_USERNAME="tester"
RIGEL_USER_PASSWORD="s3cret"
RIGEL_ROOT_PASSWORD="r00tpw"
RIGEL_TRIM=1
write_target_env
TENV="$TMP/root/rigel-target.env"
if [ -f "$TENV" ]; then t_ok "файл параметров создан"; else t_bad "файл параметров не создан"; fi
t_check "hostname в chroot"    "$( . "$TENV"; printf '%s' "$RIGEL_HOSTNAME" )"     "rigel-pc"
t_check "username в chroot"    "$( . "$TENV"; printf '%s' "$RIGEL_USERNAME" )"     "tester"
t_check "пароль пользователя"  "$( . "$TENV"; printf '%s' "$RIGEL_USER_PASSWORD" )" "s3cret"
t_check "trim для fstrim"      "$( . "$TENV"; printf '%s' "$RIGEL_TRIM" )"         "1"
if is_windows_shell; then
    t_skip "права 600 на файл с паролями (Windows-ФС не поддерживает chmod)"
else
    t_check "права на файл с паролями" "$(stat -c '%a' "$TENV")" "600"
fi
rm -rf "$TMP"

echo
echo "=== 8. Валидация параметров ==="
if ( RIGEL_DISK=""; validate_params ) >/dev/null 2>&1; then t_bad "пустой диск принят"; else t_ok "пустой диск отвергнут"; fi
if ( RIGEL_DISK=/dev/sda; RIGEL_USERNAME="Bad Name"; validate_params ) >/dev/null 2>&1; then t_bad "плохое имя пользователя принято"; else t_ok "плохое имя пользователя отвергнуто"; fi
if ( RIGEL_DISK=/dev/sda; RIGEL_ROOT_PASSWORD=""; validate_params ) >/dev/null 2>&1; then t_bad "пустой пароль root принят"; else t_ok "пустой пароль root отвергнут"; fi
if ( RIGEL_DISK=/dev/sda; RIGEL_ROOT_FS=zfs; validate_params ) >/dev/null 2>&1; then t_bad "неизвестная ФС принята"; else t_ok "неизвестная ФС отвергнута"; fi

echo
echo "=== 9. Определение железа (не должно падать) ==="
vendor="$(detect_cpu_vendor)"
case "$vendor" in intel|amd|other) t_ok "производитель CPU: $vendor" ;; *) t_bad "detect_cpu_vendor → '$vendor'" ;; esac
gpus="$(detect_gpus)"
[ -n "$gpus" ] && t_ok "GPU: $gpus" || t_bad "detect_gpus вернул пусто"
mode="$(detect_firmware_mode)"
case "$mode" in UEFI|BIOS) t_ok "прошивка: $mode" ;; *) t_bad "detect_firmware_mode → '$mode'" ;; esac
case "$(detect_secureboot)" in enabled|disabled) t_ok "Secure Boot определяется" ;; *) t_bad "detect_secureboot сломан" ;; esac
case "$(ucode_recommendation)" in intel-ucode|amd-ucode|нет) t_ok "ucode: $(ucode_recommendation)" ;; *) t_bad "ucode_recommendation сломан" ;; esac

echo
echo "=== 10. Рабочий стол: Hyprland / KDE Plasma ==="
RIGEL_DESKTOP=hyprland
case "$(desktop_packages)" in *hyprland*) t_ok "hyprland: Hyprland в наборе" ;; *) t_bad "hyprland: нет пакета hyprland" ;; esac
case "$(desktop_packages)" in *plasma-meta*) t_bad "hyprland: не должен тянуть Plasma" ;; *) t_ok "hyprland: Plasma не тянется" ;; esac
t_check "hyprland ставится офлайн" "$(desktop_needs_network && echo нужна-сеть || echo офлайн)" "офлайн"
RIGEL_DESKTOP=plasma
case "$(desktop_packages)" in *plasma-meta*) t_ok "plasma: есть plasma-meta" ;; *) t_bad "plasma: нет plasma-meta" ;; esac
case "$(desktop_packages)" in *sddm*) t_ok "plasma: есть sddm (менеджер входа)" ;; *) t_bad "plasma: нет sddm" ;; esac
case "$(desktop_packages)" in *hyprland*) t_bad "plasma: не должен тянуть Hyprland" ;; *) t_ok "plasma: Hyprland не тянется" ;; esac
t_check "plasma требует сеть" "$(desktop_needs_network && echo нужна-сеть || echo офлайн)" "нужна-сеть"
RIGEL_DESKTOP=both
case "$(desktop_packages)" in *plasma-meta*) t_ok "both: есть Plasma" ;; *) t_bad "both: нет Plasma" ;; esac
case "$(desktop_packages)" in *hyprland*) t_ok "both: есть Hyprland" ;; *) t_bad "both: нет Hyprland" ;; esac
case "$(desktop_packages)" in *sddm*) t_ok "both: есть sddm" ;; *) t_bad "both: нет sddm" ;; esac
RIGEL_DESKTOP=minimal
t_check "minimal: браузер и терминал" "$(desktop_packages)" "kitty thunar firefox"
RIGEL_DESKTOP=none
t_check "none: пустой набор" "$(desktop_packages)" ""
aur=""
for d in hyprland plasma both minimal; do
    RIGEL_DESKTOP="$d"
    for p in $(desktop_packages); do
        case "$p" in paru|yay|aura|trizen|pamac|pacaur) aur="$aur $d:$p" ;; esac
    done
done
t_check "в наборах нет пакетов из AUR" "$(trim "$aur")" ""
if ( RIGEL_DISK=/dev/sda; RIGEL_DESKTOP=windows; RIGEL_ROOT_PASSWORD=p; RIGEL_USER_PASSWORD=p; validate_params ) >/dev/null 2>&1; then
    t_bad "неизвестный RIGEL_DESKTOP принят"
else
    t_ok "неизвестный RIGEL_DESKTOP отвергнут"
fi
if ( RIGEL_DISK=/dev/sda; RIGEL_DESKTOP=plasma; RIGEL_ROOT_PASSWORD=p; RIGEL_USER_PASSWORD=p; validate_params ) >/dev/null 2>&1; then
    t_ok "RIGEL_DESKTOP=plasma проходит валидацию"
else
    t_bad "RIGEL_DESKTOP=plasma отвергнут валидацией"
fi
RIGEL_DESKTOP=hyprland

echo
echo "=================================================="
printf 'Пройдено: %d, провалено: %d, пропущено: %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
