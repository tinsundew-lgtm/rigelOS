#!/usr/bin/env bash
# Сборка кастомных пакетов Rigel из папки pacman-rigel/
#
# Использование:
#   bash pacman-rigel/build.sh                    # собрать всё
#   bash pacman-rigel/build.sh --install           # собрать и установить
#   bash pacman-rigel/build.sh rigel-installer     # собрать только один пакет

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$REPO_ROOT/pacman-rigel"
REPO_DIR="$PKG_DIR/repo"

command -v makepkg >/dev/null 2>&1 || { echo "Ошибка: нужен makepkg (Arch Linux)"; exit 1; }

build_pkg() {
    local dir="$1"
    local name
    name="$(basename "$dir")"
    [ -f "$dir/PKGBUILD" ] || return 0

    echo "==> собираю $name"
    (
        cd "$dir"
        rm -rf src pkg *.pkg.tar.* 2>/dev/null || true
        makepkg -s --noconfirm
        local pkg_file
        pkg_file="$(ls -1t *.pkg.tar.* 2>/dev/null | head -n1)" || {
            echo "  ошибка: пакет $name не собран"
            return 1
        }
        mkdir -p "$REPO_DIR"
        cp "$pkg_file" "$REPO_DIR/"
        echo "  [ok] $pkg_file"
    )
}

# Сборка
if [ $# -ge 1 ] && [ "$1" != "--install" ]; then
    build_pkg "$PKG_DIR/$1"
else
    for d in "$PKG_DIR"/*/; do
        [ -d "$d" ] || continue
        build_pkg "$d"
    done
fi

# Репозиторий
if [ -d "$REPO_DIR" ] && [ "$(ls -A "$REPO_DIR"/*.pkg.tar.* 2>/dev/null)" ]; then
    echo "==> создаю репозиторий в $REPO_DIR"
    cd "$REPO_DIR"
    repo-add "rigel.db.tar.zst" ./*.pkg.tar.zst 2>/dev/null || true
    echo "  [ok] репозиторий обновлён"
fi

# Установка
if [ "${1:-}" = "--install" ]; then
    echo "==> устанавливаю в систему"
    for f in "$REPO_DIR"/*.pkg.tar.*; do
        [ -f "$f" ] || continue
        sudo pacman -U --noconfirm "$f"
    done
    echo "  [ok] установлено"
fi

echo "==> готово"