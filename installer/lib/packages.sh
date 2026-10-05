#!/usr/bin/env bash
# Rigel installer — пакеты: базовый набор, офлайн-репозиторий.

RIGEL_ISO_REPO_DIR="${RIGEL_ISO_REPO_DIR:-/usr/local/share/rigel/repo}"
RIGEL_ONLINE_RESOLVED=0

# --------------------------------------------------- сеть, зеркала
resolve_online() {
    if online; then RIGEL_ONLINE_RESOLVED=1; ok "сеть доступна"
    else RIGEL_ONLINE_RESOLVED=0; warn "сети нет — установка только из офлайн-репозитория"; fi
    RIGEL_ONLINE="$RIGEL_ONLINE_RESOLVED"
}

iso_repo_available() {
    [ -d "$RIGEL_ISO_REPO_DIR/x86_64" ] && ls "$RIGEL_ISO_REPO_DIR/x86_64"/*.pkg.tar.* >/dev/null 2>&1
}

build_offline_repo_from_cache() {
    local cache="/var/cache/pacman/pkg"
    local repo="$RIGEL_STATE_DIR/offline-repo"
    have repo-add || { warn "нет repo-add (пакет pacman) — офлайн-репозиторий не собрать"; return 1; }
    [ -d "$cache" ] || { warn "нет кэша пакетов $cache"; return 1; }
    if ! ls "$cache"/*.pkg.tar.* >/dev/null 2>&1; then
        warn "кэш $cache пуст — офлайн-установка невозможна"
        return 1
    fi
    rm -rf "$repo"; mkdir -p "$repo"
    find "$cache" -maxdepth 1 -name '*.pkg.tar.*' -exec cp -n {} "$repo/" \; 2>/dev/null || true
    ( cd "$repo" && repo-add -q rigel-offline.db.tar.zst ./*.pkg.tar.* >/dev/null 2>&1 ) || {
        warn "не удалось создать базу офлайн-репозитория"; return 1; }
    ok "офлайн-репозиторий собран из кэша ISO: $(ls "$repo"/*.pkg.tar.* | wc -l) пакетов"
    printf '%s' "$repo"
}

write_install_pacman_conf() {
    local conf="$RIGEL_STATE_DIR/pacman-install.conf"
    local offline_repo=""
    mkdir -p "$RIGEL_STATE_DIR"

    if [ "$RIGEL_ONLINE_RESOLVED" != "1" ] && ! iso_repo_available; then
        offline_repo="$(build_offline_repo_from_cache || true)"
    fi

    {
        cat <<'EOF'
[options]
HoldPkg = pacman glibc
Architecture = auto
Color
ParallelDownloads = 5
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
EOF
        if [ "$RIGEL_ONLINE_RESOLVED" = "1" ]; then
            cat <<'EOF'

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
        fi
        if iso_repo_available; then
            cat <<EOF

[rigel-iso]
SigLevel = Optional TrustAll
Server = file://$RIGEL_ISO_REPO_DIR/\$arch
EOF
        fi
        if [ -n "$offline_repo" ]; then
            cat <<EOF

[rigel-offline]
SigLevel = Optional TrustAll
Server = file://$offline_repo
EOF
        fi
    } >"$conf"

    if [ "$RIGEL_ONLINE_RESOLVED" != "1" ] && ! iso_repo_available && [ -z "$offline_repo" ]; then
        warn "нет ни сети, ни офлайн-репозитория — установка из сети невозможна"
    fi
    RIGEL_PACMAN_CONF="$conf"
    ok "конфиг pacman для установки: $conf"
}

# ------------------------------------------------------------- наборы пакетов
kernel_packages() {
    local k out=""
    for k in $RIGEL_KERNELS; do
        out="$out $k"
        case "$k" in
            *-lts)   out="$out linux-lts-headers" ;;
            *-zen)   out="$out linux-zen-headers" ;;
            *-hardened) out="$out linux-hardened-headers" ;;
            *)       out="$out linux-headers" ;;
        esac
    done
    printf '%s' "$(trim "$out")"
}

ucode_packages() {
    case "$RIGEL_UCODE" in
        intel) printf 'intel-ucode' ;;
        amd)   printf 'amd-ucode' ;;
        auto)  case "$(detect_cpu_vendor)" in
                   intel) printf 'intel-ucode' ;;
                   amd)   printf 'amd-ucode' ;;
                   *)     printf '' ;;
               esac ;;
        *)     printf '' ;;
    esac
}

fs_packages() {
    printf '%s' "btrfs-progs e2fsprogs dosfstools exfatprogs ntfs-3g gptfdisk parted"
}

system_packages() {
    local out
    out="base base-devel sudo efibootmgr networkmanager network-manager-applet"
    out="$out $(kernel_packages) linux-firmware $(ucode_packages)"
    out="$out $(fs_packages)"
    out="$out vim nano micro man-db man-pages bash-completion less"
    out="$out pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol"
    out="$out polkit polkit-gnome"
    out="$out gvfs gvfs-mtp udisks2 udiskie exfatprogs"
    out="$out fastfetch inxi lshw usbutils pciutils dmidecode"
    out="$out grub efibootmgr"
    [ "${RIGEL_TRIM:-0}" = "1" ] && out="$out util-linux"
    [ "${RIGEL_IS_LAPTOP:-0}" = "1" ] && out="$out tlp"
    [ "${RIGEL_VIRT:-none}" != "none" ] && [ "${RIGEL_VIRT:-none}" != "unknown" ] && out="$out qemu-guest-agent"
    printf '%s' "$(trim "$out")"
}

# ------------------------------------------------------------------ установка
pacstrap_base() {
    local pkgs
    pkgs="$(trim "$(system_packages)")"

    ok "базовые пакеты: $(wc -w <<<"$pkgs") шт."
    log "список: $pkgs"
    run pacstrap -K -C "$RIGEL_PACMAN_CONF" "$RIGEL_MOUNT" $pkgs
    ok "pacstrap завершён"
}