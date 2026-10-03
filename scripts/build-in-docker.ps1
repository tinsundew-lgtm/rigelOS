# Rigel — сборка ISO в Docker из Windows (PowerShell).
#
#   pwsh -File scripts\build-in-docker.ps1
#   pwsh -File scripts\build-in-docker.ps1 -Offline
#
# Нужен Docker Desktop с бэкендом WSL2 и включённой поддержкой Linux-контейнеров.

param(
    [switch]$Offline,
    [switch]$KeepWork
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker не найден. Установите Docker Desktop (WSL2) или используйте GitHub Actions — см. BUILD.md"
}

$extra = @()
if ($Offline)  { $extra += '--offline' }
if ($KeepWork) { $extra += '--keep-work' }
$extraArgs = ($extra -join ' ')

# Путь монтируем в POSIX-виде, иначе Docker Desktop путает диск C:
$mount = $repoRoot -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'

Write-Host "==> профиль: $repoRoot"
Write-Host "==> собираю в контейнере archlinux:latest (первый запуск качает ~500 МБ)"

docker run --privileged --rm `
    -v "${mount}:/build" `
    -w /build `
    -e "EXTRA_ARGS=$extraArgs" `
    archlinux:latest `
    bash -c '
        set -euo pipefail
        pacman-key --init >/dev/null 2>&1 || true
        pacman-key --populate archlinux >/dev/null 2>&1 || true
        pacman -Sy --noconfirm archlinux-keyring >/dev/null 2>&1 || true
        # зависимости сборки (archiso, syslinux, grub, squashfs-tools...) ставит сам build-iso.sh
        bash scripts/build-iso.sh $EXTRA_ARGS
    '

Write-Host "==> ISO в: $repoRoot\out\"
Get-ChildItem -Path (Join-Path $repoRoot 'out') -Filter '*.iso' -ErrorAction SilentlyContinue |
    Format-Table Name, @{Name = 'Размер'; Expression = { '{0:N0} МБ' -f ($_.Length / 1MB) } }
