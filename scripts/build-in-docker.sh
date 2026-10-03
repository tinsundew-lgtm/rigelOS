#!/usr/bin/env bash
# Rigel — сборка ISO в контейнере Arch Linux.
# Позволяет собрать ISO из любой системы с Docker (в том числе из Windows).
#
#   scripts/build-in-docker.sh                 обычная сборка
#   scripts/build-in-docker.sh --offline       с локальным репозиторием на ISO
#
# Требуется Docker с поддержкой Linux-контейнеров и флаг --privileged
# (mkarchiso создаёт loop-устройства и монтирует их).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTRA_ARGS="$*"

command -v docker >/dev/null 2>&1 || {
    echo "Docker не найден. Варианты: GitHub Actions (.github/workflows/build-iso.yml) или Arch в WSL2 — см. BUILD.md" >&2
    exit 1
}

docker info >/dev/null 2>&1 || { echo "Docker-демон не запущен." >&2; exit 1; }

echo "==> собираю в контейнере archlinux:latest (первый запуск качает ~500 МБ)"
docker run --privileged --rm \
    -v "$REPO_ROOT:/build" \
    -w /build \
    -e EXTRA_ARGS="$EXTRA_ARGS" \
    archlinux:latest \
    bash -c '
        set -euo pipefail
        pacman-key --init >/dev/null 2>&1 || true
        pacman-key --populate archlinux >/dev/null 2>&1 || true
        pacman -Sy --noconfirm archlinux-keyring >/dev/null
        pacman -S --noconfirm --needed base-devel >/dev/null
        bash scripts/build-iso.sh --no-deps $EXTRA_ARGS
    '

echo "==> ISO в: $REPO_ROOT/out/"
ls -lh "$REPO_ROOT/out/"*.iso 2>/dev/null || true
