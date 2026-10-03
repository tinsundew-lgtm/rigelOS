# Rigel — план создания дистрибутива на базе Arch Linux

**Версия документа:** 2.2 (профиль ISO, сборка без своего Linux, выбор рабочего стола)
**Имя проекта:** **Rigel** (звезда в созвездии Ориона)
**Схема версий:** целые номера + кодовое имя созвездия — `Rigel 1 «Orion»`, `Rigel 2 «Lyra»`, `Rigel 3 «Cygnus»`
**Рабочая папка:** `C:\tinSundew\arch base distribution`

> **Статус.** `archinstall.sh` разобран ([installer/REVIEW.md](installer/REVIEW.md) — 20 проблем, 8 критических) и переписан в движок. Готово: движок (11 этапов), TUI, определение железа, разметка (ESP 1 ГиБ → `/boot`, btrfs `@`/`@snapshots`, отдельный ext4 `/home`), два ядра + ucode, systemd-boot/GRUB, snapper, локаль RU, **выбор рабочего стола (Hyprland / KDE Plasma / оба)**, 11 категорий приложений во вкладках «Базовые»/«Про». Профиль archiso в `iso/` написан заново по эталону archiso. Сборка без своего Linux: GitHub Actions и Docker ([BUILD.md](BUILD.md)). Проверки: `bash -n` по 20 скриптам, **57 логических тестов** и валидатор профиля (`scripts/verify-all.sh`) — всё зелёное. **Осталось:** собрать ISO и проверить установку в VM, затем dotfiles, свой репозиторий + GitHub Pages, GUI-обновлятор, документация.



---

## 0. Как читать этот план

Под конкретные решения: **один человек, начальный уровень Linux, бюджет 0, менее 5 часов в неделю**; цель — **личный дистрибутив Arch для себя и друзей** с собственным установщиком, преднастроенным Hyprland и понятным выбором приложений.

Четыре вещи принять до чтения:

1. **Установщик делаем свой**, а не Calamares: у вас есть рабочий скрипт, он становится движком, поверх него — TUI-интерфейс (v1), GUI — в Rigel 2.
2. **Первый живой ISO — 3–5 недель**, первая полноценная установка на диск — примерно через 3–4 месяца при 4–5 ч/неделю.
3. **Выбор приложений делится на две вкладки** — «Базовые» (понятно новичку) и «Про» (ядро, драйверы, разработка, серверное, ручная разметка).
4. **Сознательно отложено в Rigel 3 «Cygnus»**: LUKS, Secure Boot, подпись репозитория. Всё это в разделе 15 с готовыми шагами.

---

## 1. Согласованные решения

| Параметр | Решение | Следствие |
|---|---|---|
| Имя | **Rigel** | `iso_name="rigel"`, `[rigel]`, `rigel-*`, `ID=rigel` |
| Версии | **Целые + кодовое имя**: `1 «Orion»`, `2 «Lyra»`, `3 «Cygnus»` | Каждый релиз — заметная веха, без дробных версий |
| Цель | Личный дистрибутив для себя и друзей | Без сайта, SLA, службы поддержки |
| Форк | Ремастер `archiso` + свой слой | Arch не форкаем, свой репозиторий — только добавки |
| Рабочий стол | Hyprland + автологин в live | Главный источник рисков и «вау»-эффекта |
| Установщик | **Свой: TUI сейчас, GUI в Rigel 2** | Движок — ваш скрипт, интерфейс — `dialog`/`whiptail` |
| Выбор приложений | Вкладки **«Базовые»** и **«Про»** | Понятные категории для новичка + отдельная вкладка для опытных |
| Источник пакетов при установке | База — офлайн с ISO, «Про» — докачивается | ISO остаётся тонким, «Про» всегда актуально |
| Разметка | **ESP 1 ГБ → `/boot`**, btrfs `/`, отдельный ext4 `/home` | systemd-boot читает ядра прямо с ESP; данные живут отдельно |
| Ручная разметка | Да, всегда доступна (пункт во вкладке «Про») | Плюс экран выбора «весь диск / рядом с Windows / вручную» |
| Защита Windows | Да: предупреждения + проверка NTFS | `initialPartitioningChoice`-аналог: по умолчанию ничего не выбрано |
| Транспорт загрузки | systemd-boot (UEFI) + syslinux/GRUB для BIOS | Два ядра в меню |
| Ядро | `linux` + `linux-lts` по умолчанию, в «Про» — `linux-zen`, `linux-hardened` | ucode (intel/amd) ставится автоматически |
| Определение железа | **Автоподбор драйверов** по `lspci`/`lscpu`/`dmidecode` | Пользователь только подтверждает рекомендации |
| Обновлятор | **Свой GUI `rigel-update`** (GTK4/libadwaita) | Прогресс, список пакетов, подсказки про `.pacnew` и откат |
| Снапшоты | btrfs `@` + `@snapshots`, `snapper` + `snap-pac` | Откат после неудачного `pacman -Syu` |
| Репозиторий | Локально на ISO + **бесплатный GitHub Pages** | Друзья получают обновления `rigel-*` одной командой |
| Подпись репо | Пока нет (`TrustAll`) | Rigel 3, 0 ₽ и 2–4 ч |
| Шифрование | LUKS не делаем | Rigel 3 |
| Secure Boot | Отложен | Rigel 3; в докладе — «выключите SB перед установкой» |
| Локаль | Русский везде, включая `LC_MESSAGES`, Alt+Shift | Плюс `libreoffice-ru`, шрифты с кириллицей |
| Релизы | По необходимости, без графика | Всегда есть «последний рабочий ISO» + CHANGELOG |
| Публичность | Возможно через год | EN-документация, лицензии, дисклеймер — сразу |
| Инфраструктура | Локальный ПК, бюджет 0 | Сборка в виртуалке, CI бесплатный, хостинг бесплатный |

---

## 2. Крупные версии и честная оценка объёма

### 2.1 Что входит в какую версию

| Версия | Кодовое имя | Содержание | Когда |
|---|---|---|---|
| **Rigel 1** | **Orion** | Live-Hyprland, **TUI-установщик** на вашем скрипте, вкладки выбора приложений, автоподбор драйверов, btrfs+snapper, ESP 1 ГБ → `/boot`, два ядра, GUI-обновлятор, документация RU+EN, публикация тонкого ISO | ≈ 5–7 месяцев |
| **Rigel 2** | **Lyra** | **GUI-установщик** (GTK4/libadwaita) на том же движке, толстый ISO, темы и полировка, GUI-настройки | +3–5 месяцев |
| **Rigel 3** | **Cygnus** | Secure Boot (sbctl + UKI), подпись репозитория + `rigel-keyring`, LUKS, своё зеркало ISO | +2–4 месяца |
| Rigel 4 | Aquila | Вторая редакция (GNOME/XFCE), ARM-сборка, сайт с загрузками | по желанию |
| Rigel 5 | Perseus | — резерв под идеи — | — |

### 2.2 Оценка Rigel 1 «Orion» по фазам

| Фаза | Содержание | Часы | Календарь при 4–5 ч/нед |
|---|---|---|---|
| 0 | Виртуалка, Arch внутри, `archiso`, первый стоковый ISO | 8–12 | 2–3 нед |
| 1 | Профиль Rigel: бренд, live-Hyprland, автологин, русская локаль | 15–20 | 4 нед |
| 2 | Десктоп: dotfiles, waybar, хоткеи, `docs/hotkeys.md` | 15–25 | 4–5 нед |
| 3 | Репозиторий `[rigel]` + GitHub Pages + метапакеты | 12–18 | 3–4 нед |
| 4 | **Установщик, движок**: разметка (ESP→/boot, btrfs, ext4 /home), systemd-boot, два ядра, защита Windows — **код написан, осталось проверить на железе** | 6–10 | 2 нед |
| 5 | **Установщик, TUI**: экраны, вкладки «Базовые» и «Про», офлайн/онлайн, прогресс — **код написан, осталась полировка** | 6–10 | 2 нед |
| 6 | Железо: `rigel-hwdetect`, NVIDIA/медиа/периферия/игры | 14–20 | 4–5 нед |
| 7 | Снапшоты: subvolume-конвертер, `snapper`, `docs/recovery.md`, тест-ломание | 10–15 | 3 нед |
| 8 | GUI-обновлятор `rigel-update` | 6–10 | 2 нед |
| 9 | Документация RU+EN, CI, `release.sh` | 8–12 | 2–3 нед |
| 10 | Тесты на двух машинах, релиз **Rigel 1 «Orion»** | 10–15 | 3 нед |
| | **Итого** | **110–167 ч** | **≈ 5–7 месяцев** |

**Критический путь до «уже можно пользоваться»:** фазы 0 → 1 → 3 → 4 (≈ 50–70 ч, то есть 3–4 месяца) — это ISO с live-Hyprland, который ставит систему на диск своим установщиком.

**Что осознанно НЕ делаем в Rigel 1:** GUI-установщик, LUKS, Secure Boot, подпись репозитория, ARM, вторая редакция, свой сайт, телеметрия.

---

## 3. Ключевые технические решения

### 3.1 Установщик: свой, на базе вашего скрипта

Архитектура (детали — в 7.4):

```
installer/                  # установщик Rigel (bash + whiptail, работает из live-ISO)
├── rigel-install           # TUI: приветствие, железо, диск, ядро, вкладки приложений,
│                           # пользователь, подтверждение, прогресс
├── selftest.sh             # самопроверка в live-среде (синтаксис, зависимости, apps.d, разметка)
├── params.example.env      # контракт параметров (то же, что пишет TUI)
├── lib/
│   ├── common.sh           # лог, параметры, имена разделов NVMe/SATA, запуск этапов в chroot
│   ├── hwdetect.sh         # определение железа и рекомендации по драйверам
│   ├── disk.sh             # разметка: ESP 1 ГиБ → /boot, btrfs /, ext4 /home, subvolumes
│   ├── packages.sh         # наборы пакетов, офлайн-репозиторий с ISO, докачка из сети
│   ├── bootloader.sh       # systemd-boot и GRUB, два ядра, ucode, проверка ESP
│   └── post.sh             # локаль, время, пользователи, sudo, сервисы, snapper, автовход
├── engine/rigel-engine.sh  # ← ВАШ СКРИПТ, переписанный в неинтерактивный движок
└── apps.d/                 # 11 категорий приложений для вкладок «Базовые» и «Про»
```

Почему так: у вас уже есть рабочая установка — глупо писать её заново. Ваш скрипт стал **движком** (разметка, установка пакетов, загрузчик), а всё, что нужно дистрибутиву, вынесено в модули: **определение железа**, **выбор ядра**, **выбор приложений по вкладкам**, **локаль/пользователь**, **снапшоты**, **прогресс и лог**.

**План Б**, если на реальном железе движок окажется нерасширяемым: Calamares как каркас + вызов нашего движка шагом `shellprocess` (~15–20 ч, переключение почти бесплатно).

### 3.2 Разделы: ESP 1 ГБ → `/boot`, btrfs `/`, ext4 `/home`

```
/dev/nvme0n1
├── p1  EFI System Partition   1 ГБ   FAT32   → /boot        (systemd-boot + ядра + initramfs)
├── p2  корень                 45 ГБ  btrfs   → /            (@ и @snapshots внутри)
├── p3  домашний каталог       остаток ext4   → /home
└── p4  swap-файл 4 ГБ (внутри корня или отдельный раздел — на выбор)
```

Почему ESP именно 1 ГБ и именно в `/boot`:

- systemd-boot **требует**, чтобы ядра и initramfs лежали на ESP, иначе он их не найдёт;
- при 1 ГБ там спокойно живут **два ядра** (`linux` + `linux-lts`) с fallback-образами и запасом на обновления;
- отдельный `/boot` (ext4/XBOOTLDR) нужен только для GRUB, шифрования или нескольких дистрибутивов — в Rigel 1 это лишняя сложность, но пункт остаётся доступен в ручной разметке;
- Ваш прежний вариант `/boot/efi` 512 МБ тоже поддерживаем как опцию ручной разметки.

Отдельный ext4 `/home` (ваше решение) означает: переустановка системы не стирает данные, снапшоты корня не раздуваются, ФС максимально простая. Снапшоты делаем только для `/`.

### 3.3 Вкладки выбора приложений

**Вкладка «Базовые» — понятно новичку.** Каждая категория — одна галочка с человеческим описанием, что именно поставится:

| Категория | Что ставится | Откуда |
|---|---|---|
| База (всегда) | Firefox, kitty, Thunar, file-roller, unzip/p7zip, gvfs, mpv | ISO (офлайн) |
| Офисные документы | LibreOffice Fresh + русский языковой пакет, hunspell-ru | ISO (офлайн) |
| Общение | Telegram, Discord, Element | докачивается |
| Медиа и графика | VLC, GIMP, OBS Studio, Kdenlive, Inkscape, ffmpeg + кодеки | докачивается |
| Периферия | CUPS + драйверы, сканер, Bluetooth, exFAT/NTFS, принтеры | ISO (офлайн) |
| Игры | Steam, Lutris, MangoHud, GameMode, lib32-стек (multilib) | докачивается |

Плюс всегда доступен пункт **«Ничего лишнего»** — ставится только база.

**Вкладка «Про» — для опытных:**

| Категория | Что даёт |
|---|---|
| Ядро | выбор: `linux` (по умолчанию), `linux-lts`, `linux-zen`, `linux-hardened`; автоматически `intel-ucode` или `amd-ucode` |
| Драйверы и GPU-стек | NVIDIA (open/dkms) или AMD/Intel, Vulkan, VA-API, мультимедиа-кодеки |
| Разработка | git, редактор/IDE, podman, языки (Python/Node/Rust/Go), SDK |
| Серверные компоненты | SSH, nginx, файловый сервер, автозапуск сервисов |
| Загрузчик и разметка вручную | GRUB вместо systemd-boot, свой layout, второй диск, раздел `/boot` |
| Ничего из перечисленного | чистый минимум |

Механика «офлайн/онлайн» простая и предсказуемая:

- **На ISO (работает без сети):** база, офис, периферия, плееры и кодеки.
- **Докачивается при установке (нужна сеть):** общение, игры, тяжёлая графика, всё из «Про».
- В TUI у докачиваемых пунктов стоит пометка **[нужен интернет]**; если сети нет — пункт просто отключается с объяснением.
- Если после сборки ISO превысит 2 ГиБ (лимит GitHub Releases), публикуем через торрент/Internet Archive — это решается на фазе 9, а не переделкой установщика.

### 3.4 Определение железа — что именно автоматизируем

Скрипт `lib/hwdetect.sh` собирает отчёт и **выводит рекомендации**, которые установщик подставляет по умолчанию:

| Что определяем | Как | Что ставим/предлагаем |
|---|---|---|
| CPU | `lscpu`, `/proc/cpuinfo` | `intel-ucode` / `amd-ucode` — обязательно |
| GPU | `lspci -nn`, `nvidia-detect` | `nvidia-open-dkms` (Turing+), `nvidia-dkms` (старее), иначе `mesa` + `vulkan-radeon`/`vulkan-intel` |
| Видео-ускорение | `vainfo`, `vulkaninfo` | `libva-*`, `lib32-*` при играх |
| Wi-Fi/звук/тачпад | `lspci`, `lsusb`, `lsmod` | `linux-firmware`, `sof-firmware`, `alsa-ucm-conf` |
| Тип устройства | батарея в `/sys/class/power_supply` | `tlp` (ноутбук) или `power-profiles-daemon` (ПК/ВМ) |
| Виртуалка | `systemd-detect-virt` | гостевые пакеты, отключение лишних сервисов |
| Прошивка | `[ -d /sys/firmware/efi ]` | UEFI → systemd-boot; BIOS → syslinux/GRUB |
| Secure Boot | `bootctl status`, `mokutil --sb-state` | предупреждение в установщике, инструкция в докладе |
| Существующие ОС | NTFS/ESP-разделы | защита Windows, подсказка про «рядом с Windows» |
| Диск | `/sys/block/*/rotational` | `fstrim.timer` для SSD/NVMe |
| Датчики | `lm_sensors` | предложить `sensors-detect` после установки |

Отчёт показывается пользователю человеческим языком («Найдена видеокарта NVIDIA GeForce RTX 3060 — будет установлен драйвер `nvidia-open-dkms`») и дублируется в `/var/log/rigel-hwdetect.log` — это спасёт при разборе проблем у друзей.

### 3.5 GUI-обновлятор `rigel-update`

- Python + GTK4 + libadwaita (ставится `python-gobject`, `gtk4`, `libadwaita`, `pacman-contrib`).
- Проверка обновлений: `checkupdates` (безопасно, не трогает базу) → список пакетов → «Обновить».
- Само обновление: `pkexec pacman -Syu` с живым выводом и прогрессом в окне.
- Дополнительно: количество доступных снапшотов `snapper` и кнопка «Откатить последнее обновление» (открывает инструкцию/скрипт), предупреждение об `.pacnew` с подсказкой про `pacdiff`.
- Ничего автоматического без согласия пользователя: никаких «тихих» `-Sy` в фоне.

---

## 4. Архитектура проекта

### 4.1 Как всё связано

```
   Зеркала Arch (core / extra / multilib)
                 │
                 ▼
     ┌───────────────────────────┐     ┌──────────────────────────┐
     │  репозиторий [rigel]      │◄────┤  GitHub Pages (бесплатно)│
     │  metapackages + dotfiles  │     │  обновления для друзей   │
     └─────────────┬─────────────┘     └──────────────────────────┘
                   ▼
     ┌──────────────────────────────────────────────┐
     │  профиль archiso (iso/)                      │
     │  packages.x86_64 (+ .full) + airootfs/        │
     │  + rigel-installer/ + локальный репозиторий   │
     └─────────────┬────────────────────────────────┘
                   │ mkarchiso
                   ▼
     out/rigel-1-x86_64.iso ──► флешка/Ventoy ──► второй ПК / NVIDIA-машина
                   │                                         │
                   ▼                                         ▼
        GitHub Releases / торрент                     QEMU (быстрая проверка)
                   │
                   ▼
     rigel-install (TUI): железо → диск → ядро → приложения → пользователь
                   │
                   ▼
     btrfs / + ext4 /home, ESP 1 ГБ → /boot, systemd-boot, два ядра
                   │
                   ▼
     первый запуск: Hyprland, dotfiles из /etc/skel, ru_RU, Alt+Shift, rigel-update
```

### 4.2 Структура репозитория (монорепо)

```
rigel/
├── README.md / README.ru.md / LICENSE / NOTICE / CHANGELOG.md
├── .github/workflows/build-iso.yml
├── iso/
│   ├── profiledef.sh
│   ├── pacman.conf
│   ├── packages.x86_64            # тонкий ISO
│   ├── packages.full.x86_64       # + Steam/Lutris/lib32 (для себя)
│   ├── airootfs/
│   │   ├── etc/…                  # locale, os-release, skel, snapper
│   │   ├── root/.automated_script.sh
│   │   ├── usr/local/bin/rigel-*  # установщик и вспомогательные скрипты
│   │   └── usr/local/share/rigel/repo/x86_64/   # локальный репозиторий на ISO
│   ├── efiboot/ grub/ syslinux/
├── installer/                     # наш установщик (см. 7.4)
│   ├── rigel-install  selftest.sh  params.example.env  REVIEW.md
│   ├── lib/                       # common, hwdetect, disk, packages, bootloader, post
│   ├── engine/rigel-engine.sh     # ← ваш скрипт после адаптации
│   └── apps.d/                    # 11 категорий приложений
├── packages/                      # PKGBUILD-ы
│   ├── rigel-meta/ rigel-hyprland/ rigel-dotfiles/ rigel-branding/
│   ├── rigel-gaming/ rigel-dev/ rigel-extras/
├── updater/                       # rigel-update (GTK4/libadwaita)
├── branding/
├── scripts/
│   ├── build-repo.sh  build.sh  test-qemu.sh  make-usb.sh
│   ├── publish-pages.sh  release.sh
├── docs/
│   ├── install.md hotkeys.md recovery.md gaming.md build.md faq.md test-log.md
└── PLAN.md                        # этот документ
```

### 4.3 Инструменты

| Задача | Инструмент |
|---|---|
| Сборка ISO | `archiso`, профиль `releng` |
| Пакеты | `makepkg`, `namcap`, `repo-add` |
| Установщик | свой: `bash` + `dialog`/`whiptail`, движок — ваш скрипт |
| Разметка | `sgdisk`/`parted`, `mkfs.btrfs`, `mkfs.ext4`, `mkfs.fat` |
| Диски и снапшоты | `btrfs-progs`, `snapper`, `snap-pac` |
| Загрузчик | `systemd-boot` (+ `syslinux`/`grub` для BIOS) |
| Обновлятор | Python + GTK4 + libadwaita, `pkexec`, `pacman-contrib` |
| Брендинг | `plymouth`, `/etc/os-release`, `fastfetch` |
| CI | GitHub Actions, контейнер `archlinux:latest` |
| Тесты | QEMU + OVMF, второй ПК, NVIDIA-машина |

---

## 5. Версии и кодовые имена

| Версия | Кодовое имя | Ядро релиза |
|---|---|---|
| Rigel 1 | Orion | TUI-установщик, Hyprland, выбор приложений, автоопределение железа, снапшоты, обновлятор |
| Rigel 2 | Lyra | GUI-установщик и GUI-настройки, толстый ISO, полировка |
| Rigel 3 | Cygnus | Secure Boot, подпись репозитория, LUKS, зеркало |
| Rigel 4 | Aquila | Вторая редакция, ARM, сайт |
| Rigel 5 | Perseus | резерв |

Правила:

- номер меняется только при **крупных** изменениях (смена установщика, базы, состава поставки), косметика и обновления пакетов — без нового номера;
- имя релиза видно в `/etc/os-release` (`VERSION="1 (Orion)"`) и в `fastfetch`;
- «последний рабочий ISO» хранится всегда, плюс предыдущий релиз.

---

## 6. Дорожная карта Rigel 1 «Orion»

Спринт = 2 недели, максимум 3 задачи.

### Фаза 0. Фундамент (8–12 ч, 2–3 недели)

1. Виртуалка 8 ГБ RAM / 60 ГБ, включённая вложенная виртуализация.
2. Arch внутри через `archinstall` (btrfs + systemd-boot).
3. `sudo pacman -Syu archiso git base-devel namcap qemu-desktop edk2-ovmf dialog`.
4. Собрать стоковый ISO: `cp -r /usr/share/archiso/configs/releng ~/releng-test` → `sudo mkarchiso -v -w ~/work -o ~/out ~/releng-test`.
5. Проверить его в виртуалке и с флешки на втором ПК.
6. Создать монорепозиторий по 4.2 и залить на GitHub.

**DoD:** `scripts/build.sh` собирает ISO; вы объясняете своими словами `airootfs`, `squashfs`, `profiledef.sh`.

### Фаза 1. Профиль Rigel и live-Hyprland (15–20 ч, 4 недели)

1. `releng` → `iso/`; переименование: `iso_name="rigel"`, `iso_label`, `iso_publisher`, `iso_application`, `install_dir="rigel"`.
2. `packages.x86_64` — базовый набор (7.2).
3. Автозапуск Hyprland в live + **автологин без пароля**.
4. Локаль: `locale.gen`, `locale.conf` (RU везде, включая `LC_MESSAGES`), `vconsole.conf` (`KEYMAP=ru`), шрифты с кириллицей.
5. Раскладка us,ru с `grp:alt_shift_toggle`.
6. Бренд: `os-release` (`VERSION="1 (Orion)"`), `/etc/issue`, `/etc/motd`, `fastfetch`, обои.
7. Сборка, проверка в VM и на втором ПК, коммит.

**DoD:** ISO грузится в UEFI и BIOS; live-Hyprland с автологином; Wi-Fi, звук, русская раскладка, бренд.

### Фаза 2. Десктоп «как у опытных» (15–25 ч, 4–5 недель)

1. Dotfiles: `hyprland.conf` + `conf.d/`, `waybar`, `fuzzel`, `hyprpaper`, `hyprlock`/`hypridle`, `mako`/`swaync`, `cliphist`, `grim`/`slurp`, `wlogout`.
2. Тема и шрифты: `nwg-look`, `papirus-icon-theme`, `ttf-jetbrains-mono-nerd`, `noto-fonts(-cjk/-emoji)`, `ttf-dejavu`.
3. Хоткеи: `SUPER+Enter/Q/D/1..9/стрелки/L`, `Print`, `XF86Audio*`.
4. `docs/hotkeys.md` — таблица всех хоткеев.

**DoD:** друг за 10 минут сам открывает браузер, терминал, файлы, делает скриншот, переключает раскладку.

### Фаза 3. Репозиторий и метапакеты (12–18 ч, 3–4 недели)

1. PKGBUILD-ы: `rigel-meta`, `rigel-hyprland`, `rigel-dotfiles`, `rigel-branding`, `rigel-gaming`, `rigel-dev`, `rigel-extras`.
2. `scripts/build-repo.sh`: `makepkg -sf` → `repo-add` → копия в `iso/airootfs/usr/local/share/rigel/repo/x86_64/`.
3. `pacman.conf`: `[rigel]` с `file://` на ISO и `SigLevel = Optional TrustAll`.
4. GitHub Pages: `scripts/publish-pages.sh` выкладывает репозиторий (обязательно кладёт `rigel.db.tar.zst` ещё и как `rigel.db` — Pages не умеет симлинки).

**DoD:** `pacman -Ss rigel` в live находит пакеты; `rigel-meta` ставится офлайн; друг получает обновление `rigel-dotfiles` с Pages.

### Фаза 4. Установщик: движок (6–10 ч, 2 недели) — код написан

**Сделано:** `installer/engine/rigel-engine.sh` (11 этапов, `--dry-run`, `--step`, `--yes`), `lib/common.sh` (лог, параметры, имена разделов NVMe/SATA, запуск этапов в chroot через файл параметров), `lib/disk.sh` (разметка, btrfs-subvolumes до `pacstrap`, монтирование, swap-файл, защита Windows и live-носителя), `lib/bootloader.sh` (systemd-boot и GRUB, два ядра, ucode, `rootflags=subvol=@`, проверка ESP), `lib/post.sh` (локаль, время, `/etc/hosts`, пользователи, sudo через `sudoers.d`, сервисы, snapper, автовход в Hyprland), `installer/params.example.env`. Тесты логики: `installer/tests/logic-test.sh` — 42 проверки, все проходят.

**Осталось:**
1. Прогнать установку в VM (QEMU + OVMF) и посмотреть, где реально ломается: `sgdisk`, `btrfs`, `pacstrap`, `bootctl`.
2. Проверить сценарий BIOS (GRUB + `i386-pc`) и ручную разметку.
3. Проверить «рядом с Windows» (пока это делается ручной разметкой; авто-«alongside» — отдельная задача).
4. Дописать `scripts/make-usb.sh` и `scripts/build.sh` (в плане — фаза 0–1).

**DoD:** установка на диск по умолчанию проходит из live без ручных команд, система грузится с systemd-boot, `/home` отдельный, `linux-lts` есть в меню.

### Фаза 5. Установщик: TUI-интерфейс (6–10 ч, 2 недели) — код написан

**Сделано:** `installer/rigel-install` — 10 экранов (приветствие с дисклеймером → железо и рекомендации → диск → режим разметки → ядро → загрузчик → GPU → вкладка «Базовые» → вкладка «Про» → пользователь/пароль/часовой пояс/автовход → подтверждение → прогресс → итог), работа через `whiptail`, `--text` для отладки, пароли только в файл параметров с правами 0600 и удаление после установки.

**Осталось:**
1. Прогресс в процентах вместо `whiptail --tailbox` (сейчас показывается живой лог — уже работоспособно).
2. Экран «рядом с Windows» как отдельный пункт (сейчас — ручная разметка).
3. Проверка сложности пароля и защита от слишком коротких.
4. Скриншоты экранов для документации.

**DoD:** новичок (друг) проходит установку, ни разу не открыв терминал, и получает систему со своей локалью и выбранными приложениями.

### Фаза 6. Железо: автоопределение и драйверы (14–20 ч, 4–5 недель)

1. `lib/hwdetect.sh` — таблица из 3.4, человекочитаемый отчёт + `/var/log/rigel-hwdetect.log`.
2. Автовыбор драйвера: NVIDIA (open/dkms), AMD/Intel, `intel-ucode`/`amd-ucode`, `linux-firmware`, `sof-firmware`.
3. NVIDIA на реальной машине: `nvidia_drm.modeset=1`, переменные окружения Hyprland, внешний монитор, сон.
4. Медиа/периферия: `ffmpeg`, `gst-plugins-*`, `libva`, `vulkan-*`, `flatpak`+Flathub, CUPS, сканер, Bluetooth, VPN, `exfatprogs`, `ntfs-3g`.
5. Игры: `rigel-gaming` (Steam, Lutris, MangoHud, GameMode, lib32) + толстый ISO для себя.
6. `paru` + предупреждение про AUR в README.

**DoD:** на NVIDIA-машине установка и первый вход проходят без ручных правок; отчёт о железе понятен; игры ставятся одной командой.

### Фаза 7. Снапшоты и восстановление (10–15 ч, 3 недели)

1. Конвертер корня в `@` / `@snapshots` (7.5.2) — вызывается установщиком после распаковки.
2. `snapper` + `snap-pac`, ограничение `TIMELINE_LIMIT_*`.
3. `docs/recovery.md`: `snapper rollback`, chroot из live-ISO, восстановление systemd-boot.
4. **Тест-ломание:** намеренно испортить систему и восстановить по своей инструкции.

**DoD:** система восстанавливается за < 15 минут по документу, который писал не вы (проверка на друге).

### Фаза 8. GUI-обновлятор `rigel-update` (6–10 ч, 2 недели)

1. GTK4/libadwaita окно: список обновлений (`checkupdates`), кнопка «Обновить» (`pkexec pacman -Syu`), прогресс и вывод.
2. Показ предупреждений pacman, подсказка про `.pacnew` (`pacdiff`), кнопка «Откатить» → инструкция + `snapper`.
3. Автозапуск иконки в waybar (модуль custom) + `.desktop`-файл.

**DoD:** обновление системы делается мышкой, при ошибке пользователю понятно, что делать дальше.

### Фаза 9. Документация, CI, релиз-инженерия (8–12 ч, 2–3 недели)

1. `README.md` (EN) + `README.ru.md` (RU), дисклеймер про Arch.
2. `docs/`: `install.md` (со шагом «выключите Secure Boot»), `hotkeys.md`, `recovery.md`, `gaming.md`, `build.md`, `faq.md`, `test-log.md`.
3. `CHANGELOG.md` от первого релиза, включая известные проблемы.
4. GitHub Actions: сборка ISO в контейнере `archlinux:latest` по тегу.
5. `scripts/release.sh`: версия + имя, git-тег, `sha256sum`, проверка размера ISO (< 2 ГиБ — в Releases, иначе торрент).

**DoD:** друг скачивает ISO по ссылке из README и ставит систему без вашего участия.

### Фаза 10. Тесты и релиз Rigel 1 «Orion» (10–15 ч, 3 недели)

- [ ] UEFI-загрузка на реальном железе; BIOS-загрузка
- [ ] live: Wi-Fi, звук, яркость, Bluetooth, внешний монитор
- [ ] live на NVIDIA; установка на NVIDIA-машине
- [ ] Установка: весь диск / рядом с Windows / ручная разметка
- [ ] ESP 1 ГБ в `/boot`; ядра и initramfs на месте
- [ ] `/` btrfs с `@` и `@snapshots`; `/home` отдельный ext4
- [ ] Оба ядра грузятся; откат снапшота восстанавливает систему
- [ ] Вкладки приложений: офлайн-пункты работают без сети, онлайн-пункты корректно отключаются
- [ ] Автоопределение железа: правильный драйвер на NVIDIA и на AMD/Intel
- [ ] Первый вход: Hyprland, раскладка Alt+Shift, `ru_RU.UTF-8`, часовой пояс
- [ ] `rigel-update`: проверка и установка обновлений мышкой
- [ ] AUR-хелпер и предупреждение в README

**DoD релиза:** всё выше пройдено минимум на двух машинах, ISO опубликован с `sha256sum` и CHANGELOG.

---

## 7. Технические детали

### 7.1 Профиль archiso

Профиль лежит в `iso/` и написан по эталону текущего `configs/releng` проекта archiso
(сверялся с `profiledef.sh`, `efiboot`, `syslinux`, `grub` и `docs/README.profile.rst`).

```
iso/
├── profiledef.sh                 # имя, метка, режимы загрузки, права файлов
├── pacman.conf                   # для сборки: core/extra/multilib
├── packages.x86_64               # ПО ОДНОМУ ПАКЕТУ В СТРОКЕ
├── efiboot/loader/               # systemd-boot (UEFI): loader.conf + записи ядер
├── syslinux/syslinux.cfg         # BIOS (isolinux): синтаксис без menu.c32
├── grub/grub.cfg                 # UEFI, запасной загрузчик
└── airootfs/                     # то, что станет корнем живой системы
    ├── etc/{locale.gen,locale.conf,vconsole.conf,hostname,hosts,motd}
    ├── etc/mkinitcpio.conf.d/archiso.conf      # хуки archiso — без них ISO не грузится
    ├── etc/pacman.d/hooks/10-rigel-live.hook   # настройка живой системы во время сборки
    ├── etc/systemd/system/getty@tty1.service.d/autologin.conf
    ├── root/.bash_profile                      # показывает приветствие на tty1
    └── usr/local/bin/{rigel-welcome,rigel-live-setup,rigel-install}
```

Что важно и чего легко не заметить:

- `bootmodes=('bios.syslinux' 'uefi.systemd-boot' 'uefi.grub')`: BIOS грузится через syslinux
  (в archiso для BIOS других вариантов нет), UEFI — systemd-boot, GRUB как запасной;
- **`packages.x86_64` — по одному пакету в строке**: несколько пакетов в строке pacman понимает
  как одно длинное имя, и сборка падает через 10 минут;
- обязательны `mkinitcpio` и `mkinitcpio-archiso` — без них не собирается initramfs с хуками
  archiso и ISO не грузится;
- `customize_airootfs.sh` в текущем archiso больше нет: живая система настраивается
  **pacman-хуком** `airootfs/etc/pacman.d/hooks/10-rigel-live.hook`, который вызывает
  `rigel-live-setup` (локали, ключи pacman, `pacman.conf` с multilib и `[rigel-iso]`, сервисы, initramfs);
- установщик **не дублируется** в профиле: `scripts/build-iso.sh` копирует `installer/`
  в `iso/airootfs/usr/local/lib/rigel-installer/` перед сборкой (единый источник правды);
- NVIDIA в live-ISO нет специально: `nvidia-open-dkms` пришлось бы собирать во время сборки ISO,
  а в живой среде хватает nouveau/modesetting — драйвер ставит установщик в целевую систему;
- `file_permissions` в `profiledef.sh` обязателен для наших скриптов: файлы из `airootfs`
  копируются с правами 644/755 и без этого `rigel-install` не запустится.

### 7.2 Пакетные списки

Живой ISO собирается из **`iso/packages.x86_64`** — по одному пакету в строке
(это не стилистика: несколько пакетов в строке pacman понимает как одно имя, и сборка падает).

Что входит в тонкий ISO:

- **обязательное для archiso:** `base`, `mkinitcpio`, `mkinitcpio-archiso`, `archlinux-keyring`,
  `linux`, `linux-lts`, `linux-firmware`, `intel-ucode`, `amd-ucode`;
- **установщик:** `arch-install-scripts` (pacstrap, arch-chroot, genfstab), `gptfdisk`, `parted`,
  `dosfstools`, `e2fsprogs`, `btrfs-progs`, `exfatprogs`, `ntfs-3g`, `snapper`, `snap-pac`,
  `libnewt` (это и есть whiptail), `dialog`, `sudo`;
- **живой стол Hyprland:** `hyprland`, порталы, `waybar`, `fuzzel`, `mako`, `kitty`, `thunar`,
  `firefox`, шрифты с кириллицей, `mesa`, `vulkan-*`;
- **железо и сервисы:** `networkmanager`, `bluez` + `blueman`, `pipewire` + `wireplumber`,
  `polkit`, `cups`, `udisks2`, `alsa-utils`, `sof-firmware`;
- **загрузчики:** `grub`, `efibootmgr`, `os-prober`;
- **для будущего `rigel-update`:** `python-gobject`, `gtk4`, `libadwaita`, `pacman-contrib`.

Чего в ISO нет — и почему:

- **KDE Plasma** (`plasma-meta` + `sddm`): весит больше всего остального ISO. Ставится установщиком
  из сети (вариант `RIGEL_DESKTOP=plasma|both`);
- **NVIDIA** (`nvidia-open-dkms`): DKMS собирался бы во время сборки ISO, а в live-режиме он не нужен;
- **AUR-пакеты** (`paru`, `yay`): официальные репозитории их не знают — сборка упала бы на «target not found»
  (это отдельно проверяет `scripts/check-profile.sh`).

`iso/packages.full.x86_64` — дополнение для личного «толстого» ISO: `steam lutris mangohud gamemode`
и 32-битные библиотеки (`lib32-mesa`, `lib32-vulkan-radeon`, `lib32-libpulse`, `lib32-libglvnd`).

Гигиена: у каждого спорного пакета — комментарий «почему он тут»; `namcap` по своим PKGBUILD; раз в месяц смотреть `pacman -Qe`.

**Как работает «база офлайн».** `scripts/build-iso.sh --offline` скачивает пакеты из
`packages.x86_64`, кладёт их в `iso/airootfs/usr/local/share/rigel/repo/x86_64/` и делает `repo-add`.
В живой системе этот репозиторий подключён как `[rigel-iso]` (`file://`), поэтому при `RIGEL_ONLINE=0`
установка идёт без сети. Если репозитория нет, движок собирает его на лету из кэша pacman внутри
squashfs (`build_offline_repo_from_cache`). Цена: ISO вырастает примерно вдвое, сборка — дольше.


### 7.3 Рабочие столы и брендинг

Компоненты и конфиги Hyprland — как в фазе 2; доставка — пакетом `rigel-dotfiles` в `/etc/skel/.config/…` и `/usr/share/rigel/dotfiles/` (существующие конфиги не перезаписываются — иначе обновления затрут правки друзей).

**Рабочий стол выбирается на экране установщика** (вариант `RIGEL_DESKTOP`):

| `RIGEL_DESKTOP` | Что ставится | Нужен интернет |
|---|---|---|
| `hyprland` (по умолчанию) | Hyprland + waybar/fuzzel/kitty/thunar, автовход на tty1 | нет — всё есть на флешке |
| `plasma` | `plasma-meta` + `sddm` + приложения KDE, вход через SDDM | да |
| `both` | Plasma по умолчанию, Hyprland в меню сеансов SDDM | да |
| `minimal` | браузер, файлы, терминал | нет |
| `none` | чистая консоль (сервер, отладка) | нет |

Если выбран `plasma`/`both`, а сети нет, установщик **останавливается и объясняет**, что делать
(подключить сеть или выбрать Hyprland), вместо падения на середине установки: `plasma-meta` не
влезает в тонкий ISO. Автовход для Plasma настраивается в `/etc/sddm.conf.d/10-rigel-autologin.conf`,
для Hyprland — через `getty@tty1` и `~/.bash_profile`.

Брендинг:

- `/etc/os-release`: `NAME="Rigel"`, `PRETTY_NAME="Rigel Linux"`, `ID=rigel`, `ID_LIKE=arch`, `VERSION="1 (Orion)"`, `HOME_URL`, `LOGO=rigel`;
- `/etc/issue`, `/etc/motd`, `fastfetch` с ASCII-логотипом, обои в `/usr/share/backgrounds/rigel/`;
- `plymouth` (заставка) и тема syslinux/GRUB для BIOS-ветки;
- экран приветствия установщика — ваш логотип и дисклеймер.

### 7.4 Установщик Rigel — что уже реализовано

```
installer/
├── rigel-install                 # TUI-фронтенд (whiptail; --text = текстовый режим)
├── selftest.sh                   # самопроверка: синтаксис, зависимости, apps.d, логика разметки
├── tests/logic-test.sh           # 57 тестов чистой логики (работают и вне Arch)
├── params.example.env            # все параметры установки с комментариями
├── apps.d/                       # 11 категорий приложений
│   ├── 10-base.conf 20-office.conf 30-chat.conf 40-media.conf
│   ├── 50-peripherals.conf 60-games.conf                       # вкладка «Базовые»
│   └── 70-kernel.conf 80-drivers.conf 90-dev.conf 95-server.conf 99-manual-boot.conf   # вкладка «Про»
├── lib/
│   ├── common.sh                 # лог, параметры, имена разделов (NVMe/eMMC), запуск этапов в chroot
│   ├── hwdetect.sh               # железо: CPU/GPU/ноутбук/ВМ/SSD/Secure Boot + рекомендации
│   ├── disk.sh                   # разметка, btrfs-subvolumes, монтирование, swap-файл, защита Windows
│   ├── packages.sh               # наборы пакетов, офлайн-репозиторий, докачка из сети, apps.d
│   ├── bootloader.sh             # systemd-boot и GRUB, два ядра, ucode, проверка ESP
│   └── post.sh                   # локаль, время, хостнейм, пользователи, sudo, сервисы, snapper, автовход
└── engine/rigel-engine.sh        # движок: 11 этапов, --dry-run, --step, лог, откат монтирования
```

Разбор исходного `archinstall.sh`: **20 проблем, 8 критических** — таблица с номерами строк в [installer/REVIEW.md](installer/REVIEW.md). Главная: quoted heredoc `<< 'EOF'` при неработающих `export $username` — все переменные внутри chroot были пустыми, поэтому имя компьютера писалось пустым, а `useradd`/`chpasswd` фактически не срабатывали.

Ключевые отличия от исходного скрипта:

| Было в `archinstall.sh` | Стало в `rigel-install` |
|---|---|
| `read -p` по ходу, вопросы нельзя пропустить/повторить | TUI: экраны, возврат, подтверждение, `--text` для отладки |
| переменные в chroot через heredoc (пустые) | файл `/root/rigel-target.env` (0600), удаляется после установки |
| `/dev/sda1` жёстко | `disk_part()`: NVMe/eMMC (`/dev/nvme0n1p2`) и SATA |
| ESP 511 МиБ, `/boot/efi`, GRUB | ESP 1 ГиБ → `/boot`, systemd-boot (UEFI) или GRUB (BIOS) |
| всё в один ext4, `/home` = 60 ГиБ | btrfs `/` с `@`/`@snapshots` + отдельный ext4 `/home` |
| одно ядро, без microcode | `linux` + `linux-lts` (или zen/hardened), `intel-ucode`/`amd-ucode` в записи загрузчика |
| `echo` вместо `locale.gen` | корректные `locale.gen`, `locale.conf`, `vconsole.conf` (RU + Alt+Shift) |
| нет снапшотов | `snapper` + `snap-pac`, ограничения по времени хранения |
| нет проверок | проверка диска, live-носителя, NTFS/Windows, выключенного Secure Boot, полноты ESP |
| ошибки без контекста | лог всех команд, `--step N` для продолжения с места сбоя, отчёт при ошибке |
| нет выбора софта | вкладки «Базовые» и «Про», 11 категорий, пометка «[нужен интернет]» |

Контракт между интерфейсом и движком — файл параметров (см. `installer/params.example.env`):

```bash
RIGEL_DISK=/dev/nvme0n1
RIGEL_PART_MODE=auto            # auto | manual
RIGEL_ROOT_FS=btrfs             # btrfs | ext4
RIGEL_HOME_MODE=separate        # separate | none
RIGEL_HOME_FS=ext4
RIGEL_ESP_MIB=1024              # ESP 1 ГиБ → /boot
RIGEL_ROOT_SIZE=45G             # пусто = авто
RIGEL_SWAP=file:4G
RIGEL_KERNELS="linux linux-lts"
RIGEL_UCODE=auto
RIGEL_GPU=auto                  # auto | nvidia-open | nvidia | mesa
RIGEL_BOOTLOADER=auto           # auto | systemd-boot | grub
RIGEL_DESKTOP=hyprland          # hyprland | plasma | both | minimal | none
RIGEL_APPS_BASE="office peripherals"
RIGEL_APPS_PRO="drivers dev"
RIGEL_USERNAME=user
RIGEL_HOSTNAME=rigel-pc
RIGEL_TIMEZONE=Europe/Moscow
RIGEL_LANG=ru_RU.UTF-8
RIGEL_KEYMAP=ru
RIGEL_AUTOLOGIN=0
RIGEL_ONLINE=auto               # auto | 1 | 0
```

Запуск и отладка:

```bash
sudo installer/rigel-install                       # TUI
sudo installer/rigel-install --text                # то же, но текстовыми вопросами
sudo installer/selftest.sh                         # самопроверка в live-среде
bash installer/tests/logic-test.sh                 # 42 теста логики (работают и вне Arch)
sudo installer/engine/rigel-engine.sh --config installer/params.example.env --dry-run
sudo installer/engine/rigel-engine.sh --config /run/rigel/params.env --yes
sudo installer/engine/rigel-engine.sh --config /run/rigel/params.env --yes --step pacstrap   # продолжить с этапа
```

Что осталось по установщику: проверить реальную установку в VM и на втором ПК (фаза 4–5), встроить его в профиль archiso (`airootfs/usr/local/bin/rigel-install`), добавить экран прогресса в процентах (сейчас `whiptail --tailbox` показывает лог) и GUI-версию в Rigel 2.

Ожидаемый результат достигнут: `rigel-engine.sh --config FILE --yes` выполняет установку полностью неинтерактивно — это же будет использоваться для автотестов в QEMU.

### 7.5 Разметка и снапшоты

#### 7.5.1 Схема по умолчанию

```
p1  ESP      1 ГБ    FAT32   → /boot
p2  root     45 ГБ   btrfs   → /            (@ = корень, @snapshots = /.snapshots)
p3  home     остаток ext4    → /home
    swap     4 ГБ    файл    → /swapfile (hibernation не поддерживаем в Rigel 1)
```

Правила:
- ESP **обязательно** ≥ 512 МБ (у нас 1 ГБ) и всегда монтируется в `/boot`, потому что systemd-boot ищет ядра там;
- если пользователь выбирает «рядом с Windows»: не трогаем существующий ESP, добавляем свои разделы, пишем загрузчик в существующий ESP, предупреждаем про размер и про флаг `boot`;
- если ESP меньше нужного — предупреждение и предложение увеличить;
- ручная разметка: `cfdisk`/`parted`, затем проверка точек монтирования перед продолжением;
- BIOS/legacy: дополнительный раздел 1 МБ без ФС под `bios_grub` (для GRUB) либо `syslinux` на MBR.

#### 7.5.2 Subvolumes для снапшотов

`btrfs` создаётся `mkfs.btrfs`, но subvolumes создаём сами (это делает движок установщика или пост-шаг):

```
1. mkfs.btrfs -L root /dev/nvme0n1p2
2. mount -o noatime,compress=zstd:3 /dev/nvme0n1p2 /mnt
3. btrfs subvolume create /mnt/@ /mnt/@snapshots
4. umount; mount -o subvol=@,noatime,compress=zstd:3 /dev/nvme0n1p2 /mnt
5. mkdir /mnt/.snapshots; mount -o subvol=@snapshots /dev/nvme0n1p2 /mnt/.snapshots
6. genfstab -U /mnt >> /mnt/etc/fstab
```

Раз `mkfs` и монтирование полностью наши, костыль с конвертом (как при Calamares) **не нужен** — subvolumes создаются сразу, до `pacstrap`. Это заметно снижает риск фазы 7: остаётся только настроить `snapper` и проверить откат.

#### 7.5.3 Загрузчик и два ядра

- UEFI: `bootctl --path=/boot install`, записи в `/boot/loader/entries/`: `rigel-linux.conf` и `rigel-linux-lts.conf`, `default rigel-linux` в `loader.conf`.
- `cmdline`: `root=UUID=… rootflags=subvol=@ rw quiet` + `nvidia_drm.modeset=1` при NVIDIA.
- BIOS: `syslinux` (как в `releng`) или `grub` — выбирается на экране «Ядро и загрузчик».
- `mkinitcpio -P` запускается для всех выбранных ядер.

### 7.6 `pacman.conf` и репозиторий

```ini
[options]
HoldPkg = pacman glibc
Architecture = auto
Color
ILoveCandy
ParallelDownloads = 5
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist

# на ISO (офлайн-установка)
[rigel]
SigLevel = Optional TrustAll
Server = file:///usr/local/share/rigel/repo/$arch
```

В установленной системе дополнительно появляется drop-in с GitHub Pages:

```ini
# /etc/pacman.d/rigel.conf  (подключён через Include)
[rigel]
SigLevel = Optional TrustAll
Server = https://<логин>.github.io/rigel-repo/$arch
```

Устройство репозитория и варианты хостинга — как в разделе 3.1 предыдущей версии плана: это статические файлы (`rigel.db` + пакеты), серверная логика не нужна, GitHub Pages бесплатен (лимиты ≈1 ГБ на репозиторий, 100 МБ на файл). Ключевое: **ваш репозиторий не должен догонять Arch** — в нём только метапакеты и dotfiles.

### 7.7 Локаль, раскладка, время

```bash
# /etc/locale.gen
en_US.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
# /etc/locale.conf — русский везде, включая сообщения программ
LANG=ru_RU.UTF-8
LC_MESSAGES=ru_RU.UTF-8
LC_TIME=ru_RU.UTF-8
LC_COLLATE=ru_RU.UTF-8
# /etc/vconsole.conf
KEYMAP=ru
FONT=cyr-sun16
```

Hyprland (`~/.config/hypr/conf.d/input.conf`):

```ini
input {
    kb_layout = us,ru
    kb_options = grp:alt_shift_toggle
    follow_mouse = 1
    touchpad { natural_scroll = true }
}
```

Часовой пояс выбирается на экране «Пользователь» (по умолчанию — `Europe/Moscow`, пользователь может выбрать любой). Шрифты с кириллицей обязательны, иначе в waybar будут квадраты.

### 7.8 Сборка, тесты, флешка

Все проверки одной командой (работает и в Windows, в Git Bash):

```bash
bash scripts/verify-all.sh        # синтаксис 20 скриптов + валидатор профиля + 57 тестов логики
```

Сборка — три пути, подробности в [BUILD.md](BUILD.md):

```bash
# 1) вообще без своего Linux: GitHub → Actions → «Сборка ISO Rigel» → Run workflow → скачать артефакт
#    (по тегу v1.0 ISO прикрепляется к GitHub Release)

# 2) Docker (в том числе из Windows)
pwsh -File scripts\build-in-docker.ps1          # или scripts/build-in-docker.sh в Linux/macOS

# 3) Arch Linux — живая флешка или установленная система
sudo scripts/build-iso.sh                       # + --offline для установки без интернета
```

`scripts/build-iso.sh` сам: проверяет окружение → ставит зависимости → приводит переводы строк к LF →
копирует `installer/` внутрь профиля → (по желанию) собирает офлайн-репозиторий → запускает `mkarchiso` →
**проверяет, что в ISO реально лежат** `airootfs.sfs`, `vmlinuz-linux`, `initramfs-linux.img`,
`EFI/BOOT/BOOTx64.EFI` и `loader/loader.conf`. Если чего-то нет — сборка честно падает, а не отдаёт
нерабочий ISO.

Быстрая проверка без записи на флешку (QEMU, UEFI):

```bash
qemu-system-x86_64 -m 4096 -smp 2 -enable-kvm \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
  -drive file=./out/rigel-1.0-x86_64.iso,media=cdrom -boot d
```

Внутри живой системы (до установки) полезно прогнать `sudo installer/selftest.sh` —
он лежит в `/usr/local/lib/rigel-installer/`.

Флешка — только после проверки списка дисков:

```bash
lsblk
sudo scripts/make-usb.sh /dev/sdX out/rigel-1.0-x86_64.iso     # спросит подтверждение
```

Из Windows — Rufus в режиме **«DD-образ»** (GPT, UEFI) или balenaEtcher.

Правила: проверять `dd`-устройство трижды; основной тест — реальный второй ПК; результат каждого
прогона — в `docs/test-log.md`; в `out/` всегда «последний рабочий ISO».

---

## 8. Риски

| Риск | Вероятность | Влияние | Что делаем |
|---|---|---|---|
| Ваш скрипт окажется трудно расширяемым | Средняя | Среднее | План Б: Calamares как каркас + скрипт шагом; решаем в первые часы фазы 4 |
| Ошибка в разметке стирает диск (свой `sgdisk`) | Средняя | Очень высокое | Двойное подтверждение, показ итогового плана разделов до записи, отказ при обнаружении Windows без явного согласия, `--yes` только для автотестов в VM |
| ESP меньше нужного / ядра не влезают | Средняя | Высокое | ESP 1 ГБ, проверка свободного места перед установкой ядер, предупреждение в TUI |
| systemd-boot не видит ядро | Средняя | Высокое | Ядра строго на ESP в `/boot`, проверка после установки (`bootctl status`), второй прогон теста |
| NVIDIA не заводится в Hyprland | Средняя (машина для тестов есть) | Высокое | `nvidia_drm.modeset=1`, переменные окружения, `linux-lts` как страховка |
| Тонкий ISO не влезет в 2 ГиБ | Средняя | Среднее | Офлайн только база/офис/периферия; тяжёлое — онлайн; проверка размера в `release.sh`, при превышении — торрент |
| Установка без интернета при выбранных онлайн-пунктах | Средняя | Среднее | Пометка «[нужен интернет]», автоотключение без сети, проверка связи до начала установки |
| < 5 ч/неделю, выгорание | Высокая | Высокое | Спринты 2 недели × 3 задачи; веха «ставится» после фазы 4; правило «сначала работает — потом красиво» |
| Начальный уровень | Высокая | Среднее | Обучающий трек (раздел 11), всё скриптами, git для откатов |
| Обновление Arch ломает систему | Высокая (rolling) | Среднее | `snapper` + `snap-pac`, `linux-lts`, `docs/recovery.md` |
| Метапакеты рассинхронизируются с Arch | Средняя | Среднее | Пересборка репозитория перед релизом, `namcap` |
| Нет подписи репозитория | Низкая | Среднее | 2FA на GitHub, только метапакеты в репо; Rigel 3 закроет |

---

## 9. Юридическая часть

1. **Название:** «Arch» не используем, логотип Arch не используем (политика торговых марок Arch требует разрешения на любую марку, начинающуюся с ARCH). Формулировка «based on Arch Linux» разрешена.
2. **Статус:** свои пакеты + свой установщик = производный продукт, а не Remix → дисклеймер обязателен.
3. **Дисклеймер:** «Rigel is an independent project based on Arch Linux. It is not affiliated with, sponsored by, or endorsed by the Arch Linux project.»
4. **Проприетарное:** NVIDIA и Steam перераспределять в неизменном виде можно; `libdvdcss` и подобное — нет.
5. **Лицензии:** ваши скрипты — MIT/GPL; `LICENSE` + `NOTICE` со ссылками.

---

## 10. Документация

| Файл | Язык | Содержание |
|---|---|---|
| `README.md` | EN | Что это, где скачать, как поставить, дисклеймер |
| `README.ru.md` | RU | То же подробно + FAQ |
| `docs/install.md` | RU | Установка по экранам, «выключите Secure Boot», заметка про Windows 11 |
| `docs/hotkeys.md` | RU | Все горячие клавиши Hyprland |
| `docs/recovery.md` | RU | Снапшоты, `snapper rollback`, chroot, восстановление systemd-boot |
| `docs/gaming.md` | RU | Steam/Lutris, NVIDIA, `rigel-gaming` |
| `docs/build.md` | RU | Как собрать ISO самому |
| `docs/apps.md` | RU | Что входит в каждую категорию вкладок «Базовые» и «Про» |
| `docs/faq.md` | RU | Частые вопросы, включая «почему без шифрования» |
| `CHANGELOG.md` | RU | По релизам + известные проблемы |
| `docs/test-log.md` | RU | Результаты тестов по машинам и датам |

Правило: функция без строчки в документации считается недоделанной.

---

## 11. Обучающий трек

| Когда | Что | Где | Время |
|---|---|---|---|
| До фазы 0 | Загрузчик, ядро, initramfs, разделы, ESP | Arch Wiki: *Arch boot process*, *Partitioning*, *EFI system partition* | 1.5–2 ч |
| Фаза 0 | Пакетный менеджер, `pacstrap` | Arch Wiki: *pacman*, *Install Arch Linux with accessibility options* | 1–1.5 ч |
| Фаза 0–1 | Сборка ISO | Arch Wiki: *Archiso* | 2 ч |
| Фаза 1–2 | Wayland/Hyprland | Hyprland Wiki | 2–3 ч |
| Фаза 3 | Свои пакеты | Arch Wiki: *PKGBUILD*, *makepkg* | 2–3 ч |
| Фаза 4–5 | TUI на bash | `man dialog`, примеры whiptail | 1.5–2 ч |
| Фаза 6 | Железо и драйверы | Arch Wiki: *NVIDIA*, *Microcode*, *Hardware video acceleration* | 2 ч |
| Фаза 7 | btrfs и снапшоты | Arch Wiki: *Btrfs*, *Snapper* | 2 ч |
| Фаза 8 | GTK4/libadwaita на Python | GNOME Developer Docs: *Getting started* | 3–4 ч |
| Фаза 9 | Git, Actions, Pages | GitHub Docs | 1–2 ч |

Привычка: `docs/notes.md` — «что не понял и как разобрался».

---

## 12. Дисциплина при < 5 ч/неделю

1. Спринты 2 недели, максимум 3 задачи; раз в 2 недели — 20 минут ревизии.
2. Одна задача = один коммит (`installer: add hwdetect screen`).
3. Всё воспроизводимо скриптом сразу, а не «потом».
4. Один эксперимент за раз: меняете установщик — не трогаете dotfiles.
5. В `out/` всегда последний рабочий ISO.
6. Бэкапы: репозиторий на GitHub; ваш исходный скрипт — отдельная копия (у вас уже есть); GPG-ключ (в Rigel 3) — в менеджере паролей + офлайн.
7. Недельный ритм: вт 1 ч — обучение; чт 2 ч — сборка и тесты; сб 1–2 ч — код и коммит.

---

## 13. Критерии готовности

**Rigel 1 «Orion»** готов, когда:

- ISO грузится в UEFI и BIOS, live-Hyprland с автологином, русская локаль и раскладка;
- установщик-«движок» ставит систему на диск: ESP 1 ГБ → `/boot`, btrfs `/` с `@`/`@snapshots`, отдельный ext4 `/home`, systemd-boot, два ядра;
- установщик-TUI: 10 экранов, вкладки приложений, автоподбор драйверов, защита Windows;
- `rigel-update` обновляет систему мышкой;
- снапшоты и откат проверены намеренной поломкой;
- документация RU+EN, CHANGELOG, ISO опубликован с `sha256sum`;
- всё проверено минимум на двух машинах (AMD/Intel и NVIDIA).

**Rigel 2 «Lyra»** добавит: GUI-установщик (GTK4/libadwaita) на том же движке, толстый ISO, полировку и GUI-настройки.

**Rigel 3 «Cygnus»** добавит: Secure Boot (sbctl + UKI), подпись репозитория + `rigel-keyring`, LUKS, своё зеркало ISO.

---

## 14. Первые шаги (сжато)

1. **Сейчас:** положите ваш скрипт установки в рабочую папку — я его разберу и впишу как движок (фаза 4).
2. **День 1–2:** виртуалка + Arch внутри через `archinstall`.
3. **День 3:** `archiso`, сборка стокового ISO, проверка в VM.
4. **День 4:** тот же ISO с флешки на втором ПК.
5. **День 5:** монорепозиторий + `scripts/build.sh`.
6. **День 6–7:** профиль Rigel, live-Hyprland, русская локаль, автологин → ISO с вашим именем.

---

## 15. Бэклог Rigel 3 «Cygnus» (отложено сознательно)

| Пункт | Зачем | Цена |
|---|---|---|
| Подпись репозитория + `rigel-keyring` | Защита от подмены пакетов | 0 ₽, 2–4 ч |
| Secure Boot (sbctl + UKI) | Машины с обязательным SB, анти-читы | 25–40 ч |
| LUKS в установщике | Ноутбук, который может потеряться | 5–8 ч + сложность восстановления |
| Своё зеркало ISO | Раздача толстого ISO без торрента | ~€5/мес |
| Свой домен и страница загрузки | Красивые ссылки и changelog | ~€10/год + 4–6 ч |
| Вторая редакция (GNOME/XFCE) | Друзьям без тайлового WM | 15–25 ч |
| ARM | Raspberry Pi и подобное | 20–40 ч |

---

## 16. Открытые вопросы

1. ✅ **Скрипт установки** — получен, разобран ([installer/REVIEW.md](installer/REVIEW.md)) и переписан в движок. Копия исходника сохранена рядом.
2. **Инструмент GUI-обновлятора** — GTK4/libadwaita (рекомендую, легче и роднее Wayland) или Qt?
3. **Порог публикации** — если тонкий ISO перевалит 2 ГиБ, публикуем через торрент/Internet Archive или урезаем офлайн-набор?
4. **Логотип и обои** — ваши, готовые (астрофото с открытой лицензией) или минималистичный текстовый вариант от меня?
5. **Swap** — 4 ГБ файлом и без hibernation в Rigel 1 — согласны?
6. **Часовой пояс по умолчанию** — `Europe/Moscow` предвыбранным или всегда пустое поле?
7. **«Рядом с Windows»** — делать полноценный автоматический режим (сжатие NTFS-раздела) или оставить ручную разметку с подсказками? Автоматический режим — это +6–10 ч и риск для чужих данных.
8. **Рабочий стол по умолчанию** — в установщике предвыбран Hyprland (он ставится без интернета), Plasma — вторым пунктом. Сделать Plasma предвыбранной?
9. **Что делаем следующим шагом** — собрать ISO (GitHub Actions или Docker) и проверить установку в VM, или сначала dotfiles для Hyprland и свои метапакеты?


---

## 17. Приложение: шпаргалка и ссылки

```bash
# окружение и сборка
sudo pacman -S archiso git base-devel namcap qemu-desktop edk2-ovmf dialog
./scripts/build-repo.sh
sudo mkarchiso -v -w ./work -o ./out ./iso

# свои пакеты
cd packages/rigel-meta && makepkg -sf
repo-add ../../repo/x86_64/rigel.db.tar.zst *.pkg.tar.zst
cp ../../repo/x86_64/rigel.db.tar.zst ../../repo/x86_64/rigel.db   # для GitHub Pages

# неинтерактивная установка (для автотестов)
sudo installer/engine/rigel-engine.sh --config /run/rigel/params.env --yes
sudo installer/selftest.sh

# разметка «руками» по нашей схеме
sgdisk -n1:0:+1G   -t1:ef00 -c1:EFI  /dev/nvme0n1
sgdisk -n2:0:+45G  -t2:8300 -c2:root /dev/nvme0n1
sgdisk -n3:0:0     -t3:8300 -c3:home /dev/nvme0n1
mkfs.fat -F32 /dev/nvme0n1p1 && mkfs.btrfs -L root /dev/nvme0n1p2 && mkfs.ext4 -L home /dev/nvme0n1p3
mount /dev/nvme0n1p2 /mnt && btrfs subvolume create /mnt/@ /mnt/@snapshots && umount /mnt
mount -o subvol=@,noatime,compress=zstd:3 /dev/nvme0n1p2 /mnt
mkdir -p /mnt/boot /mnt/home && mount /dev/nvme0n1p1 /mnt/boot && mount /dev/nvme0n1p3 /mnt/home

# тест в QEMU (UEFI)
qemu-system-x86_64 -m 4096 -smp 2 -enable-kvm \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
  -drive file=./out/rigel-1-x86_64.iso,media=cdrom -boot d

# флешка (сначала lsblk!)
lsblk && sudo dd if=./out/rigel-1-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync

# откат
sudo snapper -c root list && sudo snapper -c root rollback <N>
```

- [Arch Wiki: Archiso](https://wiki.archlinux.org/title/Archiso)
- [Arch Wiki: EFI system partition](https://wiki.archlinux.org/title/EFI_system_partition)
- [Arch Wiki: systemd-boot](https://wiki.archlinux.org/title/Systemd-boot)
- [Arch Wiki: Btrfs](https://wiki.archlinux.org/title/Btrfs) · [Snapper](https://wiki.archlinux.org/title/Snapper)
- [Arch Wiki: NVIDIA](https://wiki.archlinux.org/title/NVIDIA) · [Microcode](https://wiki.archlinux.org/title/Microcode)
- [Arch Wiki: PKGBUILD](https://wiki.archlinux.org/title/PKGBUILD)
- [Hyprland Wiki](https://wiki.hyprland.org/)
- [GNOME: libadwaita для Python](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/index.html)
- [Arch Linux Trademark Policy](https://terms.archlinux.org/docs/trademark-policy/)

---

*План 2.0: версии целыми числами с кодовыми именами, свой установщик (TUI в Rigel 1, GUI в Rigel 2) на базе вашего скрипта, вкладки «Базовые»/«Про», ESP 1 ГБ → `/boot`, автоопределение железа, свой GUI-обновлятор. Жду скрипт в рабочей папке.*
