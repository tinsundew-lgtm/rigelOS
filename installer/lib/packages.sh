#!/usr/bin/env bash
# Rigel installer — пакеты: базовый набор, рабочий стол, категории приложений,
# офлайн-репозиторий с ISO и докачка из сети.

RIGEL_APPS_DIR="${RIGEL_APPS_DIR:-/usr/local/lib/rigel-installer/apps.d}"
RIGEL_ISO_REPO_DIR="${RIGEL_ISO_REPO_DIR:-/usr/local/share/rigel/repo}"
RIGEL_ONLINE_RESOLVED=0

# --------------------------------------------------- сеть, зеркала, pacman.conf
# Plasma (plasma-meta) не лежит на флешке — её обязательно надо качать из сети.
desktop_needs_network() {
    case "${RIGEL_DESKTOP:-hyprland}" in plasma|both) return 0 ;; *) return 1 ;; esac
}

resolve_online() {
    if online; then RIGEL_ONLINE_RESOLVED=1; ok "сеть доступна"
    else RIGEL_ONLINE_RESOLVED=0; warn "сети нет — устанавливать можно только офлайн-набор"; fi
    RIGEL_ONLINE="$RIGEL_ONLINE_RESOLVED"
    if desktop_needs_network && [ "$RIGEL_ONLINE_RESOLVED" != "1" ]; then
        die "выбран рабочий стол KDE Plasma (RIGEL_DESKTOP=$RIGEL_DESKTOP), но его нет на флешке: plasma-meta весит больше всего остального ISO.
   Что делать: подключите сеть (кабель или Wi-Fi через nmtui) и запустите установку снова,
   либо выберите Hyprland — он ставится без интернета."
    fi
}

iso_repo_available() {
    [ -d "$RIGEL_ISO_REPO_DIR/x86_64" ] && ls "$RIGEL_ISO_REPO_DIR/x86_64"/*.pkg.tar.* >/dev/null 2>&1
}

# Офлайн-режим: если своего репозитория на ISO нет, собираем его «на лету» из
# кэша pacman внутри squashfs (/var/cache/pacman/pkg). Так RIGEL_ONLINE=0
# действительно ставит систему без сети — при условии, что все нужные пакеты
# попали на ISO при сборке (это делает `scripts/build-iso.sh --offline`).
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

# Собирает временный pacman.conf для pacstrap/chroot:
#  - зеркала Arch (если есть сеть)
#  - локальный репозиторий Rigel с ISO (всегда, если найден)
#  - офлайн-репозиторий из кэша ISO (если сети нет)
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
    if [ "$RIGEL_ONLINE_RESOLVED" = "1" ] && ! grep -q '^\[multilib\]' /etc/pacman.conf 2>/dev/null; then
        warn "в /etc/pacman.conf нет multilib — игры (Steam/lib32) не установятся из сети"
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

gpu_packages() {
    local base="mesa vulkan-icd-loader"
    case "$RIGEL_GPU" in
        nvidia-open) printf '%s nvidia-open-dkms nvidia-utils libva-nvidia-driver nvidia-settings' "$base" ;;
        nvidia)      printf '%s nvidia-dkms nvidia-utils libva-nvidia-driver nvidia-settings' "$base" ;;
        auto)        case "$(detect_gpus)" in
                         *nvidia*) printf '%s nvidia-open-dkms nvidia-utils libva-nvidia-driver nvidia-settings' "$base" ;;
                         *amd*)    printf '%s vulkan-radeon libva-mesa-driver' "$base" ;;
                         *intel*)  printf '%s vulkan-intel intel-media-driver' "$base" ;;
                         *)        printf '%s' "$base" ;;
                     esac ;;
        *)           printf '%s vulkan-radeon vulkan-intel' "$base" ;;
    esac
}

fs_packages() {
    local out="btrfs-progs e2fsprogs dosfstools exfatprogs ntfs-3g gptfdisk parted"
    [ "$RIGEL_ROOT_FS" = "ext4" ] && out="$out"
    printf '%s' "$out"
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
    # GRUB нужен заранее, иначе в офлайне его неоткуда взять
    if [ "$RIGEL_BOOTLOADER" = "grub" ] || { [ "$RIGEL_BOOTLOADER" = "auto" ] && ! is_uefi; }; then
        out="$out grub os-prober"
    fi
    [ "${RIGEL_TRIM:-0}" = "1" ] && out="$out util-linux"
    [ "${RIGEL_IS_LAPTOP:-0}" = "1" ] && out="$out tlp"
    [ "${RIGEL_VIRT:-none}" != "none" ] && [ "${RIGEL_VIRT:-none}" != "unknown" ] && out="$out qemu-guest-agent"
    printf '%s' "$(trim "$out")"
}

desktop_common_packages() {
    printf '%s' "firefox kitty thunar file-roller unzip p7zip nwg-look papirus-icon-theme \
ttf-jetbrains-mono-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-dejavu brightnessctl playerctl \
cups cups-pdf system-config-printer python-gobject gtk4 libadwaita pacman-contrib flatpak"
}

# Hyprland есть на ISO → этот набор ставится без интернета.
desktop_hyprland_packages() {
    printf '%s' "hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpaper hyprlock hypridle \
waybar fuzzel mako swaync cliphist wl-clipboard grim slurp wlogout"
}

# KDE Plasma качается из сети (в ISO её нет: plasma-meta весит больше всего остального ISO).
# sddm в plasma-meta не входит — добавляем отдельно.
desktop_plasma_packages() {
    printf '%s' "plasma-meta sddm konsole dolphin ark gwenview okular spectacle kde-gtk-config \
xdg-desktop-portal-kde plasma-nm plasma-pa bluedevil powerdevil breeze-gtk kscreen print-manager"
}

# Рабочий стол целевой системы:
#   hyprland — лёгкий, ставится офлайн
#   plasma   — KDE Plasma (нужна сеть)
#   both     — оба: Plasma как основной, Hyprland в меню сеансов
#   minimal  — браузер, файлы, терминал
#   none     — чистая консоль
desktop_packages() {
    case "$RIGEL_DESKTOP" in
        none)    printf '' ;;
        minimal) printf 'kitty thunar firefox' ;;
        plasma)  printf '%s %s' "$(desktop_plasma_packages)" "$(desktop_common_packages)" ;;
        both)    printf '%s %s %s' "$(desktop_plasma_packages)" "$(desktop_hyprland_packages)" "$(desktop_common_packages)" ;;
        *)       printf '%s %s' "$(desktop_hyprland_packages)" "$(desktop_common_packages)" ;;
    esac
}

metapackage_list() {
    local out=""
    if [ "$RIGEL_USE_METAPACKAGES" != "0" ]; then
        if have pacman && pacman -Ssq '^rigel-meta$' >/dev/null 2>&1; then
            out="rigel-meta"
            case "$RIGEL_DESKTOP" in
                hyprland|both) out="$out rigel-hyprland rigel-dotfiles rigel-branding rigel-extras" ;;
            esac
        fi
    fi
    printf '%s' "$(trim "$out")"
}

# ------------------------------------------------------- категории приложений
app_file_by_id() {
    local id="$1" f
    for f in "$RIGEL_APPS_DIR"/*.conf; do
        [ -r "$f" ] || continue
        if [ "$( set -a; . "$f"; printf '%s' "${APP_ID:-}" )" = "$id" ]; then
            printf '%s' "$f"; return 0
        fi
    done
    return 1
}

app_field() {
    local id="$1" field="$2" f
    f="$(app_file_by_id "$id")" || return 1
    ( set -a; . "$f"; eval "printf '%s' \"\${$field:-}\"" )
}

list_apps() {
    local f
    for f in "$RIGEL_APPS_DIR"/*.conf; do
        [ -r "$f" ] || continue
        ( set -a; . "$f"
          printf '%s|%s|%s|%s|%s\n' "${APP_ID:-}" "${APP_TAB:-base}" "${APP_TITLE:-}" "${APP_ONLINE:-0}" "${APP_DESC:-}" )
    done
}

app_packages_for() {
    local ids="$1" id out="" p
    for id in $ids; do
        p="$(app_field "$id" APP_PACKAGES 2>/dev/null || true)"
        [ -n "$p" ] && out="$out $p"
    done
    printf '%s' "$(trim "$out")"
}

app_online_packages_for() {
    local ids="$1" id out="" p
    for id in $ids; do
        [ "$(app_field "$id" APP_ONLINE 2>/dev/null || echo 0)" = "1" ] || continue
        p="$(app_field "$id" APP_PACKAGES 2>/dev/null || true)"
        [ -n "$p" ] && out="$out $p"
    done
    printf '%s' "$(trim "$out")"
}

app_offline_packages_for() {
    local ids="$1" id out="" p
    for id in $ids; do
        [ "$(app_field "$id" APP_ONLINE 2>/dev/null || echo 0)" = "1" ] && continue
        p="$(app_field "$id" APP_PACKAGES 2>/dev/null || true)"
        [ -n "$p" ] && out="$out $p"
    done
    printf '%s' "$(trim "$out")"
}

# ------------------------------------------------------------------ установка
pacstrap_base() {
    local pkgs
    pkgs="$(trim "$(system_packages) $(desktop_packages) $(metapackage_list)")"
    local offline_pkgs online_pkgs
    offline_pkgs="$(app_offline_packages_for "$RIGEL_APPS_BASE $RIGEL_APPS_PRO")"

    ok "базовые пакеты: $(wc -w <<<"$pkgs") шт."
    log "список: $pkgs"
    run pacstrap -K -C "$RIGEL_PACMAN_CONF" "$RIGEL_MOUNT" $pkgs $offline_pkgs
    ok "pacstrap завершён"
}

install_online_extras() {
    local pkgs="$1"
    [ -n "$pkgs" ] || { ok "докачивать нечего"; return 0; }
    if [ "$RIGEL_ONLINE_RESOLVED" != "1" ]; then
        warn "без сети нельзя установить: $pkgs — установщик пропустит их, README подскажет команду"
        return 0
    fi
    ok "докачиваем из сети: $pkgs"
    chroot_run "pacman -Sy --needed --noconfirm $pkgs" || warn "часть пакетов не установилась — проверьте лог"
}

journal_offline_plan() {
    local online_pkgs
    online_pkgs="$(app_online_packages_for "$RIGEL_APPS_BASE $RIGEL_APPS_PRO")"
    if [ -n "$online_pkgs" ]; then
        log "после установки при необходимости: pacman -S --needed $online_pkgs"
    fi
}
