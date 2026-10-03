# Rigel — приводим переводы строк к LF (Windows → Linux).
#
#   pwsh -File scripts\fix-line-endings.ps1
#
# Зачем: сборка ISO идёт на Linux, а там CRLF в shebang ломает запуск скриптов
# («bad interpreter: /usr/bin/env bash^M»). Редакторы Windows и некоторые
# инструменты добавляют CR автоматически.
# Бинарные файлы не трогаем (определяем по нулевому байту).

param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$skip = @('\out\', '\work\', '\.git\', '\node_modules\')
$changed = 0
$skipped = 0

Get-ChildItem -Path $root -Recurse -File | ForEach-Object {
    $full = $_.FullName
    foreach ($s in $skip) { if ($full -like "*$s*") { return } }

    $bytes = [System.IO.File]::ReadAllBytes($full)
    if ($bytes.Length -eq 0) { return }
    if ($bytes -contains 0) { $skipped++; return }   # бинарный файл

    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($text -notmatch "`r") { return }             # уже LF

    $fixed = $text -replace "`r`n", "`n" -replace "`r", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($full, $fixed, $utf8NoBom)
    $changed++
    if (-not $Quiet) { Write-Host ("  LF: " + $full.Replace($root + '\', '')) }
}

Write-Host ""
Write-Host ("Исправлено файлов: {0}, бинарных пропущено: {1}" -f $changed, $skipped)
if ($changed -eq 0) { Write-Host "Переводы строк уже в порядке (LF)." }
