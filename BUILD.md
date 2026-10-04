# Сборка ISO Rigel 1 «Orion»

Профиль лежит в `iso/`, установщик — в `installer/`. Скрипт `scripts/build-iso.sh`
копирует установщик внутрь профиля (единый источник правды, ничего не дублируется)
и запускает `mkarchiso`.

**Три способа собрать ISO — выберите тот, что подходит вашей ситуации.**

---

## Способ 1. GitHub Actions — вообще без своего Linux (рекомендую)

Сборка идёт на серверах GitHub бесплатно, у вас нужен только браузер.

1. Загрузите проект в репозиторий на GitHub (`git push`).
2. Вкладка **Actions** → workflow **«Сборка ISO Rigel»** → кнопка **Run workflow**.
3. Через ~20–30 минут в разделе **Artifacts** появится `rigel-iso` — скачайте и распакуйте.
   Если запустить сборку по тегу (`git tag v1.0 && git push --tags`), ISO дополнительно
   прикрепится к GitHub Release — оттуда скачивать удобнее (артефакты хранятся 90 дней,
   релизы — бессрочно).

Минус: сборка занимает время раннера, а скачивание ISO — это ~1.5 ГиБ трафика.

---

## Способ 2. Docker — на Windows или любом Linux

Нужен Docker Desktop (Windows/macOS, бэкенд WSL2) или docker на Linux.

```powershell
# Windows (PowerShell, из корня проекта)
pwsh -File scripts\build-in-docker.ps1

# с офлайн-репозиторием на ISO (установка без интернета)
pwsh -File scripts\build-in-docker.ps1 -Offline
```

```bash
# Linux / macOS
scripts/build-in-docker.sh
```

Контейнер `archlinux:latest` запускается с `--privileged` — иначе `mkarchiso`
не сможет создать loop-устройства. Первый запуск качает образ и пакеты (~500 МБ).

---

## Способ 3. Arch Linux (живая флешка Arch или установленная система)

```bash
sudo scripts/build-iso.sh                  # обычная сборка
sudo scripts/build-iso.sh --offline        # + локальный репозиторий на ISO
sudo scripts/build-iso.sh --keep-work      # оставить рабочую папку для отладки
sudo scripts/build-iso.sh --no-deps        # не ставить зависимости (в CI/контейнере)
```

Скрипт сам поставит `archiso`, `syslinux`, `grub`, `squashfs-tools`, `libisoburn`,
`mtools`, `libarchive` и проверит результат.

Если Arch «сломался» и загрузиться не с чего — соберите ISO из живой флешки
обычного Arch Linux: загрузитесь с неё, подключите интернет, скачайте проект,
выполните `sudo scripts/build-iso.sh`. Данные вашей сломанной системы при этом не трогаются.

---

## Что происходит при сборке

```
scripts/build-iso.sh
 ├── проверяет, что мы на Arch и есть root
 ├── ставит пакеты сборки
 ├── копирует installer/ → iso/airootfs/usr/local/lib/rigel-installer/
 ├── [--offline] складывает пакеты в iso/airootfs/usr/local/share/rigel/repo/
 ├── mkarchiso -v -w /tmp/rigel-work -o out/ iso/
 └── проверяет в готовом ISO: airootfs.sfs, vmlinuz-linux, initramfs-linux.img,
     EFI/BOOT/BOOTx64.EFI
```

Результат: `out/rigel-1.0-x86_64.iso` и `out/rigel-1.0-x86_64.iso.sha256`.

**Проверка профиля без сборки** (работает и в Windows, в Git Bash):

```bash
bash scripts/check-profile.sh
```

Скрипт ловит самые дорогие ошибки: пакеты в одну строку, отсутствие
`mkinitcpio-archiso`, расхождение ядер и записей загрузчика, мусорные подстановки
вроде `%boot_dir%`, CRLF-переводы строк, скрипты без прав на запуск.

**Проверка имён пакетов** (нужен Arch — например, контейнер или ваш Linux):

```bash
sudo scripts/check-packages.sh
```

Проверяет через `pacman --print` все списки проекта: `iso/packages.x86_64`, наборы
целевой системы (`system_packages`, все варианты `RIGEL_DESKTOP`, драйверы GPU, ucode)
и категории `installer/apps.d`. Одна опечатка в списке иначе стоит 10 минут сборки —
здесь выясняется за минуту. В GitHub Actions этот шаг выполняется автоматически.

---

## Запись на флешку

```bash
# Linux
sudo scripts/make-usb.sh /dev/sdX out/rigel-1.0-x86_64.iso
```

**Windows:** [Rufus](https://rufus.ie/) → выбрать ISO → схема **GPT**, целевая система
**UEFI** → при вопросе о режиме записи выбрать **«DD-образ»**. Либо balenaEtcher.
Не копируйте ISO как файл на флешку — она не загрузится.

Нужна флешка от 4 ГБ. Все данные на ней будут уничтожены.

---

## Первая загрузка

1. Вставьте флешку, при старте нажмите **F12/F8/F10/Esc** (у разных плат — по-разному),
   выберите флешку.
2. Если грузится не то: **Secure Boot → Disabled** в BIOS/UEFI.
   Rigel 1 не подписан ключами Microsoft.
3. Появится приветствие с меню:
   - **1** — установить Rigel на диск (TUI-установщик);
   - **2** — посмотреть дистрибутив, не устанавливая (Hyprland);
   - **3** — терминал.
4. Проверить, что всё на месте, можно до установки: `sudo installer/selftest.sh`
   (`installer/` внутри живой системы лежит в `/usr/local/lib/rigel-installer/`).

---

## Частые проблемы

| Симптом | Причина и что делать |
|---|---|
| ISO собирается, но не грузится | В BIOS включён Secure Boot — выключите. Или записали ISO как файл, а не DD-образом |
| `mkarchiso: command not found` | `sudo pacman -S archiso` (или запустите через `scripts/build-in-docker.sh`) |
| Сборка падает на «target not found» | Опечатка в имени пакета или пакет только из AUR (`paru`, `yay`). Проверьте: `bash scripts/check-profile.sh` (быстро, без сети) и `sudo scripts/check-packages.sh` (точно, нужен Arch) |
| Сборка падает через 10 минут на pacstrap | Почти всегда пакеты записаны в одну строку. Должно быть по одному в строке |
| `mkarchiso` ругается на loop device | Запускайте с `sudo` (или в Docker с `--privileged`) |
| На флешке `rigel-install: не найден установщик` | ISO собран без `scripts/build-iso.sh` — соберите правильно |
| Нет интернета при установке | Установка идёт из сети. Соберите с `--offline`, чтобы работал локальный набор |
| Чёрный экран после выбора «Живая среда Hyprland» | Вероятно, проприетарный драйвер NVIDIA: в live-режиме используйте пункт 1 (установка) — установщик сам поставит нужный драйвер |
| Хочу GNOME в живой среде | GNOME не влезает в ISO (~2+ ГиБ). Выберите при установке «GNOME» или «Оба» — установщик скачает его из сети. На флешке доступен Hyprland |

---

## Размеры и время (ориентир)

| Сборка | Время на 4-ядерной машине | Размер ISO |
|---|---|---|
| Обычная | 15–25 мин | ~1.2–1.6 ГиБ |
| С `--offline` | 30–50 мин | ~2.5–3.5 ГиБ |
| В GitHub Actions | 20–35 мин | то же |

Сжатие squashfs стоит на `xz` — это дольше, но ISO заметно меньше. Для быстрой
отладки замените в `iso/profiledef.sh` строку `airootfs_image_tool_options` на
`('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')`.
