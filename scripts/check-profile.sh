#!/usr/bin/env bash
# Rigel — проверка профиля archiso ДО сборки.
#
#   bash scripts/check-profile.sh
#
# Скрипт ничего не собирает и не требует Arch Linux: только читает файлы
# профиля, поэтому его можно запускать где угодно, включая Git Bash в Windows
# и шаг «проверка» в GitHub Actions. Ловит самые дорогие ошибки:
#   • пакеты, записанные в одну строку (сборка падает через 10 минут)
#   • отсутствие mkinitcpio / mkinitcpio-archiso (ISO не загрузится)
#   • расхождение списка пакетов и записей загрузчика
#   • забытые подстановки вроде %boot_dir% или UUID=...
#   • CRLF-переводы строк (типичная беда после правок в Windows)
#   • скрипты внутри airootfs без прав на запуск в file_permissions

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$REPO_ROOT/iso"
ERRORS=0
WARNS=0

err()     { printf '  [ОШИБКА]  %s\n' "$*"; ERRORS=$((ERRORS + 1)); }
warn()    { printf '  [предупр] %s\n' "$*"; WARNS=$((WARNS + 1)); }
ok()      { printf '  [ok]      %s\n' "$*"; }
section() { printf '\n=== %s ===\n' "$*"; }

# ------------------------------------------------------------------ 1. файлы
section "1. Обязательные файлы профиля"
req_files=(
    "profiledef.sh"
    "pacman.conf"
    "packages.x86_64"
    "syslinux/syslinux.cfg"
    "grub/grub.cfg"
    "airootfs/etc/locale.gen"
    "airootfs/etc/hostname"
    "airootfs/etc/pacman.d/hooks/10-rigel-live.hook"
    "airootfs/usr/local/bin/rigel-live-setup"
    "airootfs/usr/local/bin/rigel-welcome"
    "airootfs/usr/local/bin/rigel-install"
    "airootfs/etc/mkinitcpio.conf.d/archiso.conf"
)
for f in "${req_files[@]}"; do
    if [ -f "$PROFILE/$f" ]; then ok "$f"; else err "нет файла: iso/$f"; fi
done

# ------------------------------------------------------------- 2. profiledef
section "2. profiledef.sh"
# Значения читаем разбором файла, а не через source: в профиле есть массивы,
# и поведение ${arr[@]:-} в разных версиях bash отличается.
get_var() { sed -n "s/^$1=\"\(.*\)\"\$/\1/p" "$PROFILE/profiledef.sh" | head -n1; }
get_arr() { sed -n "/^$1=(/,/)/p" "$PROFILE/profiledef.sh" | tr -d "()'" | sed "s/^$1=//"; }

ISO_NAME="$(get_var iso_name)"
ISO_LABEL="$(get_var iso_label)"
ISO_VERSION="$(get_var iso_version)"
INSTALL_DIR="$(get_var install_dir)"
IMAGE_TYPE="$(get_var airootfs_image_type)"
BOOTMODES="$(get_arr bootmodes)"

[ -n "$ISO_NAME" ] || err "не задан iso_name"
case "$ISO_NAME" in *[!a-z0-9-]*) err "iso_name: допустимы только строчные латинские буквы, цифры и дефис" ;; *) ok "iso_name=$ISO_NAME" ;; esac

[ -n "$ISO_LABEL" ] || err "не задан iso_label"
case "$ISO_LABEL" in
    *[!A-Z0-9_]*) err "iso_label: только заглавные латинские буквы, цифры и подчёркивание" ;;
    *) if [ "${#ISO_LABEL}" -le 32 ]; then ok "iso_label=$ISO_LABEL (${#ISO_LABEL} символов)"; else err "iso_label длиннее 32 символов"; fi ;;
esac

case "$ISO_VERSION" in
    *" "*|*"/"*) err "iso_version не должен содержать пробелов и слэшей (попадает в имя файла): '$ISO_VERSION'" ;;
    *) ok "iso_version=$ISO_VERSION" ;;
esac

case "$INSTALL_DIR" in
    *[!a-z0-9]*) err "install_dir: только строчные латинские буквы и цифры" ;;
    "") err "не задан install_dir" ;;
    *) if [ "${#INSTALL_DIR}" -le 30 ]; then ok "install_dir=$INSTALL_DIR"; else err "install_dir длиннее 30 символов"; fi ;;
esac

case "$IMAGE_TYPE" in
    squashfs|ext4+squashfs|erofs) ok "airootfs_image_type=$IMAGE_TYPE" ;;
    *) err "airootfs_image_type: допустимо squashfs, ext4+squashfs или erofs" ;;
esac

grep -q '^kernel_params_x86_64=' "$PROFILE/profiledef.sh" \
    && ok "kernel_params_x86_64 задан (нужен для подстановки %KERNEL_PARAMS%)" \
    || err "в profiledef.sh нет kernel_params_x86_64 — mkarchiso упадёт на %KERNEL_PARAMS%"

for mode in $BOOTMODES; do
    case "$mode" in
        bios.syslinux)      [ -f "$PROFILE/syslinux/syslinux.cfg" ] && ok "bootmode $mode → syslinux/syslinux.cfg" || err "bootmode $mode, но нет syslinux/syslinux.cfg" ;;
        uefi.grub)          [ -f "$PROFILE/grub/grub.cfg" ] && ok "bootmode $mode → grub/grub.cfg" || err "bootmode $mode, но нет grub/grub.cfg" ;;
        *) err "неизвестный bootmode: $mode (допустимо bios.syslinux, uefi.grub)" ;;
    esac
done

# file_permissions: формат uid:gid:mode
while IFS= read -r line; do
    case "$line" in *'="'*) : ;; *) continue ;; esac
    val="${line##*=\"}"; val="${val%%\"*}"
    case "$val" in
        [0-9]*:[0-9]*:[0-7][0-7][0-7]|[0-9]*:[0-9]*:[0-7][0-7][0-7][0-7]) : ;;
        *) err "file_permissions: неверный формат '$line' (ожидается uid:gid:mode)" ;;
    esac
done < <(grep -n '\[\"' "$PROFILE/profiledef.sh" || true)

# ------------------------------------------------------------- 3. пакеты
section "3. packages.x86_64"
PKG_FILE="$PROFILE/packages.x86_64"
MULTI=0
while IFS= read -r raw; do
    line="${raw%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    words="$(printf '%s' "$line" | wc -w | tr -d ' ')"
    if [ "$words" -ne 1 ]; then
        err "в строке больше одного пакета (pacman поймёт это как одно имя): '$line'"
        MULTI=$((MULTI + 1))
        continue
    fi
    case "$line" in
        *[!a-z0-9@._+-]*) err "недопустимые символы в имени пакета: '$line'" ;;
        -*)               err "имя пакета не может начинаться с дефиса: '$line'" ;;
    esac
done < "$PKG_FILE"
[ "$MULTI" -eq 0 ] && ok "по одному пакету в строке"

for must in mkinitcpio mkinitcpio-archiso base linux; do
    grep -qx "$must" "$PKG_FILE" && ok "обязательный пакет: $must" || err "нет обязательного пакета: $must"
done

dups="$(grep -vE '^\s*(#|$)' "$PKG_FILE" | sort | uniq -d | tr '\n' ' ')"
[ -z "${dups// /}" ] && ok "дубликатов пакетов нет" || warn "дубликаты в списке: $dups"

for aur in paru yay aura trizen pamac pacaur; do
    if grep -qx "$aur" "$PKG_FILE"; then err "пакет $aur есть только в AUR — сборка ISO упадёт (официальные репозитории его не знают)"; fi
done

# ядра из записей загрузчика должны быть в списке пакетов
KERNELS="$(grep -rhoE 'vmlinuz-[a-z0-9-]+' "$PROFILE/syslinux" "$PROFILE/grub" 2>/dev/null | sort -u | sed 's/^vmlinuz-//')"
if [ -n "$KERNELS" ]; then
    for k in $KERNELS; do
        grep -qx "$k" "$PKG_FILE" && ok "ядро $k есть в packages.x86_64" || err "загрузчик ссылается на ядро $k, но пакета $k нет в списке"
    done
else
    warn "в конфигах загрузчиков не найдено vmlinuz-* — проверьте записи"
fi

# Проверяем UEFI GRUB live ISO: он должен загружать оба ядра и искать носитель по UUID.
GRUB_CFG="$PROFILE/grub/grub.cfg"
for kernel in linux linux-lts; do
    grep -q "vmlinuz-$kernel" "$GRUB_CFG" && ok "GRUB: запись для $kernel" || err "GRUB: нет записи для $kernel"
done
grep -q 'archisobasedir=%INSTALL_DIR%' "$GRUB_CFG" && ok "GRUB: archisobasedir на месте" || err "GRUB: нет archisobasedir=%INSTALL_DIR%"
grep -q 'archisosearchuuid=%ARCHISO_UUID%' "$GRUB_CFG" && ok "GRUB: поиск ISO по UUID" || err "GRUB: нет archisosearchuuid=%ARCHISO_UUID%"

BAD_PATTERNS=('%boot_dir%' 'UUID=\.\.\.' 'initrfi' 'multiboot2' 'archiso-x86_64')
for p in "${BAD_PATTERNS[@]}"; do
    if grep -rqE "$p" "$PROFILE/syslinux" "$PROFILE/grub" 2>/dev/null; then
        err "в конфигах загрузчиков остался мусор по шаблону: $p"
    fi
done
grep -rq '%INSTALL_DIR%' "$PROFILE/syslinux" "$PROFILE/grub" && ok "подстановки %INSTALL_DIR% на месте" || err "syslinux/grub: нет %INSTALL_DIR%"

# ------------------------------------------------------------- 5. airootfs
section "5. Живая система (airootfs)"

HN="$(tr -d '\r\n' < "$PROFILE/airootfs/etc/hostname")"
case "$HN" in
    "") err "/etc/hostname пуст" ;;
    *"="*|*" "*) err "/etc/hostname должен содержать только имя (сейчас: '$HN')" ;;
    *) ok "/etc/hostname = $HN" ;;
esac

grep -q 'ru_RU.UTF-8' "$PROFILE/airootfs/etc/locale.gen" && ok "locale.gen: ru_RU.UTF-8" || err "locale.gen: нет ru_RU.UTF-8"
grep -rq 'archiso' "$PROFILE/airootfs/etc/mkinitcpio.conf.d/" 2>/dev/null && ok "initramfs: хуки archiso на месте" || err "в mkinitcpio.conf.d нет хуков archiso (ISO не загрузится)"

HOOK="$PROFILE/airootfs/etc/pacman.d/hooks/10-rigel-live.hook"
if [ -f "$HOOK" ]; then
    grep -q 'When = PostTransaction' "$HOOK" && ok "pacman-хук: When = PostTransaction" || err "pacman-хук: нет 'When = PostTransaction'"
    # Exec = /usr/bin/bash /usr/local/bin/rigel-live-setup
    # Интерпретатор (/usr/bin/bash) появляется при установке пакетов, поэтому
    # проверяем только последний аргумент — сам скрипт из airootfs.
    exec_line="$(sed -n 's/^Exec *= *//p' "$HOOK" | head -n1)"
    exec_script="$(printf '%s' "$exec_line" | awk '{print $NF}')"
    if [ -n "$exec_script" ] && [ -f "$PROFILE/airootfs$exec_script" ]; then
        ok "pacman-хук: скрипт $exec_script есть в airootfs"
    else
        err "pacman-хук: скрипт '$exec_script' не найден в airootfs"
    fi
fi

grep -q 'rigel-live-setup' "$PROFILE/airootfs/usr/local/bin/rigel-live-setup" 2>/dev/null || true
grep -q 'locale-gen' "$PROFILE/airootfs/usr/local/bin/rigel-live-setup" && ok "live-setup: генерирует локали" || err "live-setup: нет locale-gen"

# скрипты в usr/local/bin должны иметь права из file_permissions
if [ -d "$PROFILE/airootfs/usr/local/bin" ]; then
    for f in "$PROFILE/airootfs/usr/local/bin"/*; do
        [ -f "$f" ] || continue
        rel="/usr/local/bin/$(basename "$f")"
        grep -q "\[\"$rel\"\]" "$PROFILE/profiledef.sh" && ok "file_permissions: $rel" || warn "нет в file_permissions: $rel (скрипт будет не исполняемым)"
    done
fi

# синтаксис всех shell-скриптов внутри airootfs
if command -v bash >/dev/null 2>&1; then
    bad=0
    while IFS= read -r f; do
        case "$(head -c 2 "$f")" in
            '#!') bash -n "$f" 2>/dev/null || { err "синтаксис: ${f#$PROFILE/}"; bad=$((bad + 1)); } ;;
        esac
    done < <(find "$PROFILE/airootfs" -type f 2>/dev/null)
    [ "$bad" -eq 0 ] && ok "синтаксис скриптов airootfs в порядке"
fi

# --------------------------------------------------- 6. гигиена репозитория
section "6. Гигиена файлов"
# Проверяем байты, а не grep: grep в Git Bash (MSYS) неверно трактует CR-шаблон
# и даёт ложные срабатывания почти на каждом файле.
crlf_list=""
while IFS= read -r f; do
    size="$(wc -c <"$f" 2>/dev/null || echo 0)"
    size_no_cr="$(tr -d '\r' <"$f" 2>/dev/null | wc -c)"
    if [ "$size" != "$size_no_cr" ]; then
        crlf_list="$crlf_list
         ${f#$REPO_ROOT/}"
    fi
done < <(find "$REPO_ROOT" -type f -not -path '*/out/*' -not -path '*/work/*' -not -path '*/.git/*' 2>/dev/null)
if [ -n "$crlf_list" ]; then
    err "CRLF-переводы строк (Linux не поймёт shebang). Исправьте: pwsh -File scripts/fix-line-endings.ps1"
    printf '%s\n' "$crlf_list"
else
    ok "переводы строк LF во всём проекте"
fi

for junk in aiprootfs kernels.txt airootfs/boot; do
    [ -e "$PROFILE/$junk" ] && err "остался мусорный файл: iso/$junk"
done
ok "мусорных файлов нет"

if [ -x "$PROFILE/airootfs/usr/local/lib/rigel-installer/rigel-install" ]; then
    ok "установщик застейджен в профиль"
else
    warn "установщик не застейджен — соберите через scripts/build-iso.sh, иначе команда rigel-install на флешке не заработает"
fi

# ------------------------------------------------------------------- итог
section "Итог"
printf '  ошибок: %d, предупреждений: %d\n' "$ERRORS" "$WARNS"
if [ "$ERRORS" -gt 0 ]; then
    printf '  Профиль НЕ готов к сборке — исправьте ошибки выше.\n'
    exit 1
fi
printf '  Профиль готов к сборке: sudo scripts/build-iso.sh\n'
exit 0
