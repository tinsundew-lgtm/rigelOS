#!/usr/bin/env bash
# Rigel installer — определение железа и рекомендации по драйверам.
#
# Использование:
#   hwdetect.sh --report        человекочитаемый отчёт
#   hwdetect.sh --recommend     строки KEY=VALUE для подстановки в параметры
#
# Может запускаться и вне установщика — из live-сессии для диагностики.

[[ "${BASH_SOURCE[0]}" == "$0" ]] && MODE="${1:---report}"

detect_cpu_vendor() {
    local vendor=""
    if have lscpu; then
        vendor="$(lscpu | awk -F: '/^Vendor ID/{gsub(/[ \t]/,"",$2); print $2}')"
    fi
    [ -n "$vendor" ] || vendor="$(awk -F: '/^vendor_id/{gsub(/[ \t]/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)"
    case "$vendor" in
        GenuineIntel) printf 'intel' ;;
        AuthenticAMD) printf 'amd' ;;
        *)            printf 'other' ;;
    esac
}

detect_cpu_name() {
    awk -F: '/^model name/{gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo 'неизвестно'
}

# Возвращает: none | amd | intel | nvidia | nvidia+amd | nvidia+intel | amd+intel
detect_gpus() {
    local out="" line
    if have lspci; then
        while IFS= read -r line; do
            case "$line" in
                *[Nn][Vv]idia*)  out="$out nvidia" ;;
                *[Aa][Mm][Dd]*|[Rr]adeon*) out="$out amd" ;;
                *[Ii]ntel*)      out="$out intel" ;;
            esac
        done < <(lspci 2>/dev/null | grep -Ei 'vga|3d|display')
    fi
    local uniq
    uniq="$(printf '%s\n' $out | awk '!seen[$0]++' | tr '\n' '+' | sed 's/+$//')"
    [ -n "$uniq" ] || uniq="none"
    printf '%s' "$uniq"
}

detect_gpu_model() {
    have lspci || { echo 'неизвестно'; return; }
    lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -n1 | sed 's/^[0-9a-f:.]* *//' || echo 'неизвестно'
}

# Рекомендация драйвера NVIDIA: open (Turing+) или проприетарный (старее)
detect_nvidia_driver() {
    if have nvidia-detect; then
        nvidia-detect 2>/dev/null | grep -o 'nvidia[a-z-]*dkms' | head -n1 && return 0
    fi
    # Без nvidia-detect: считаем, что карта современная; TUI даёт выбрать вручную
    printf 'nvidia-open'
}

detect_laptop() {
    local p
    for p in /sys/class/power_supply/*; do
        [ -r "$p/type" ] || continue
        [ "$(cat "$p/type" 2>/dev/null)" = "Battery" ] && { printf '1'; return; }
    done
    printf '0'
}

detect_virt() {
    if have systemd-detect-virt; then systemd-detect-virt 2>/dev/null || printf 'none'
    else printf 'unknown'; fi
}

detect_ssd() {
    local d rota
    for d in /sys/block/nvme* /sys/block/mmcblk* /sys/block/sd*; do
        [ -r "$d/rotational" ] || continue
        rota="$(cat "$d/rotational" 2>/dev/null)"
        [ "$rota" = "0" ] && { printf '1'; return; }
    done
    printf '0'
}

detect_secureboot() {
    if have bootctl && bootctl status 2>/dev/null | grep -qi 'Secure Boot: enabled'; then printf 'enabled'
    elif have mokutil && mokutil --sb-state 2>/dev/null | grep -qi enabled; then printf 'enabled'
    else printf 'disabled'; fi
}

detect_firmware_mode() { is_uefi && printf 'UEFI' || printf 'BIOS'; }

# Есть ли на дисках Windows или другие ОС (NTFS = Windows почти наверняка)
detect_other_os() {
    local found=""
    if have lsblk; then
        found="$(lsblk -rno NAME,FSTYPE 2>/dev/null | awk '$2=="ntfs"||$2=="ntfs3"||$2=="vfat"{print $1}' | tr '\n' ' ')"
    fi
    printf '%s' "$(trim "$found")"
}

hw_report() {
    local gpus laptop virt ssd sb fw otheros
    gpus="$(detect_gpus)"; laptop="$(detect_laptop)"; virt="$(detect_virt)"
    ssd="$(detect_ssd)"; sb="$(detect_secureboot)"; fw="$(detect_firmware_mode)"
    otheros="$(detect_other_os)"

    cat <<EOF
=== Отчёт о железе (Rigel hwdetect) ===
Процессор:        $(detect_cpu_name)
  производитель:  $(detect_cpu_vendor)  → ucode: $(ucode_recommendation)
Видео:            $(detect_gpu_model)
  найдено:        $gpus  → драйвер: $(gpu_recommendation "$gpus")
Тип устройства:   $([ "$laptop" = 1 ] && echo ноутбук || echo стационарный/иное)
Виртуализация:    $virt
Накопители:       $([ "$ssd" = 1 ] && echo 'есть SSD/NVMe (включим fstrim.timer)' || echo 'только HDD')
Прошивка:         $fw
Secure Boot:      $sb$([ "$sb" = enabled ] && echo '  ← установщик попросит выключить его в BIOS' || echo '')
Другие ОС:        ${otheros:-нет}
EOF
}

ucode_recommendation() {
    case "$(detect_cpu_vendor)" in
        intel) printf 'intel-ucode' ;;
        amd)   printf 'amd-ucode' ;;
        *)     printf 'нет' ;;
    esac
}

gpu_recommendation() {
    local gpus="$1"
    case "$gpus" in
        *nvidia*) printf '%s' "$(detect_nvidia_driver)" ;;
        *amd*)    printf 'mesa + vulkan-radeon' ;;
        *intel*)  printf 'mesa + vulkan-intel' ;;
        *)        printf 'mesa' ;;
    esac
}

hw_recommend() {
    local gpus laptop virt ssd fw ucode bootloader online resolved
    gpus="$(detect_gpus)"; laptop="$(detect_laptop)"; virt="$(detect_virt)"
    ssd="$(detect_ssd)"; fw="$(detect_firmware_mode)"
    ucode="$(detect_cpu_vendor)"; [ "$ucode" = other ] && ucode="none"

    bootloader="grub"

    case "$(detect_secureboot)" in enabled) online="1" ;; *) online="auto" ;; esac
    resolved="$online"

    cat <<EOF
# сгенерировано hwdetect $(date '+%Y-%m-%d %H:%M:%S')
RIGEL_UCODE=$ucode
RIGEL_GPU=$(case "$gpus" in *nvidia*) echo auto ;; *amd*) echo mesa ;; *intel*) echo mesa ;; *) echo mesa ;; esac)
RIGEL_BOOTLOADER=$bootloader
RIGEL_TRIM=$ssd
RIGEL_IS_LAPTOP=$laptop
RIGEL_VIRT=$virt
RIGEL_FIRMWARE=$fw
EOF
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    case "${MODE}" in
        --report)    hw_report ;;
        --recommend) hw_recommend ;;
        *)           echo "использование: $0 [--report|--recommend]" >&2; exit 2 ;;
    esac
fi
