#!/usr/bin/env bash
# Rigel — сборка всех пользовательских пакетов и создание локального репозитория.
#
# Использование:
#   sudo bash scripts/build-packages.sh              # собрать всё
#   sudo bash scripts/build-packages.sh --install     # собрать и установить в систему
#
# Результат: packages/repo/rigel.db.tar.zst + пакеты .pkg.tar.zst

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$REPO_ROOT/packages/repo"
PKGS_DIR="$REPO_ROOT/packages"

: "${GPG_KEY:=}"

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()  { printf '  \033[1;32m[ok]\033[0m  %s\n' "$*"; }
die() { printf '\033[1;31mошибка:\033[0m %s\n' "$*" >&2; exit 1; }

# Проверка: нужен makepkg (Arch Linux)
command -v makepkg >/dev/null 2>&1 || die "makepkg не найден — запускайте на Arch Linux"

# Собираем каждый пакет
arch_pkgs=()
for pkgdir in "$PKGS_DIR"/*/; do
    pkgname="$(basename "$pkgdir")"
    [ -f "$pkgdir/PKGBUILD" ] || continue

    msg "собираю $pkgname"
    (
        cd "$pkgdir"

        # Чистая сборка (удалить старые сборки)
        rm -rf src pkg *.pkg.tar.zst 2>/dev/null || true

        # Сборка пакета
        if [ -n "$GPG_KEY" ]; then
            makepkg -s --sign --key "$GPG_KEY"
        else
            makepkg -s
        fi

        # Найти собранный пакет
        pkg_file="$(ls -1t *.pkg.tar.* 2>/dev/null | head -n1)" || {
            die "$pkgname: пакет не найден после сборки"
        }

        # Скопировать в репозиторий
        mkdir -p "$REPO_DIR"
        cp "$pkg_file" "$REPO_DIR/"
        arch_pkgs+=("$pkg_file")
        ok "$pkgname собран ($pkg_file)"
    )
done

# Создаём репозиторий
if [ ${#arch_pkgs[@]} -ge 1 ]; then
    msg "создаю репозиторий в $REPO_DIR"
    (
        cd "$REPO_DIR"
        if [ -n "$GPG_KEY" ]; then
            repo-add --sign "rigel.db.tar.zst" ./*.pkg.tar.zst
        else
            repo-add "rigel.db.tar.zst" ./*.pkg.tar.zst
        fi
        ok "репозиторий обновлён: $(ls -1 *.pkg.tar.* 2>/dev/null | wc -l) пакетов"
    )
fi

# Опционально: установить в систему
if [ "${1:-}" = "--install" ]; then
    msg "устанавливаю пакеты в систему"
    echo "[rigel]" >> /etc/pacman.conf
    echo "Server = file://$REPO_DIR" >> /etc/pacman.conf
    pacman -Sy --noconfirm
    pacman -S --noconfirm "${arch_pkgs[@]%.pkg.tar.*}"
    ok "пакеты установлены"
fi

msg "готово"