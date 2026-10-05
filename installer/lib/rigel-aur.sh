#!/usr/bin/env bash
# Rigel AUR Helper — установка AUR-пакетов через yay.
#
# Зависимости: git base-devel (устанавливаются в процессе)
#
# Использование:
#   rigel-aur пакет1 пакет2 ...
#
# Работает внутри chroot (уже смонтированная целевая система).

set -euo pipefail

# ---------------------------------------------------------------- цвета (если есть)
if [ -t 1 ]; then
    BOLD='\033[1m'; DIM='\033[2m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; NC='\033[0m'
else
    BOLD=; DIM=; GREEN=; YELLOW=; RED=; NC=
fi

ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "${RED}✗${NC} %s\n" "$*"; }

# ---------------------------------------------------------------- установка yay
__ensure_yay() {
    if command -v yay &>/dev/null; then
        ok "yay уже установлен"
        return 0
    fi

    warn "yay не найден — устанавливаю из AUR"
    local workdir
    workdir="$(mktemp -d)"

    # Зависимости для сборки
    if ! pacman -Qi git base-devel &>/dev/null; then
        pacman -S --needed --noconfirm git base-devel
    fi

    git clone --depth=1 https://aur.archlinux.org/yay.git "$workdir/yay"
    cd "$workdir/yay"
    makepkg -si --needed --noconfirm
    cd /
    rm -rf "$workdir"

    if command -v yay &>/dev/null; then
        ok "yay успешно установлен"
    else
        err "не удалось установить yay"
        exit 1
    fi
}

# ---------------------------------------------------------------- установка AUR-пакетов
__install_packages() {
    local pkgs=("$@")
    if [ ${#pkgs[@]} -eq 0 ]; then
        warn "не указаны пакеты для установки"
        return 0
    fi

    ok "устанавливаю AUR-пакеты: ${pkgs[*]}"
    yay -S --needed --noconfirm "${pkgs[@]}"
}

# ---------------------------------------------------------------- точка входа
__ensure_yay
__install_packages "$@"