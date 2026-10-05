#!/usr/bin/env bash
# Rigel 1 «Orion» — профиль archiso.
#
# Сборка:  sudo scripts/build-iso.sh          (стейджит установщик и запускает mkarchiso)
# Проверка: bash scripts/check-profile.sh
#
# Эталон, по которому писался файл: configs/releng/profiledef.sh из проекта archiso.

iso_name="rigel"
iso_label="RIGEL_1_ORION"
iso_publisher="Rigel Linux <https://github.com/tinSundew/rigel>"
iso_application="Rigel Live/Install"
iso_version="1.0"
install_dir="rigel"
buildmodes=('iso')

# BIOS — syslinux; UEFI — GRUB.
bootmodes=('bios.syslinux'
           'uefi.grub')

arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"

# Сжатие squashfs: xz с BCJ-фильтром для x86 — медленнее, но ISO заметно меньше.
# Если сборка идёт на слабой машине, замените на: ('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')

bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

# Без этих параметров mkarchiso падает на подстановке %KERNEL_PARAMS%.
# Пустое значение = не добавлять ничего: в live-системе видно сообщения загрузки,
# что важно при первом запуске на новом железе.
kernel_params_x86_64="copytoram=n"

file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/local/bin/rigel-welcome"]="0:0:755"
  ["/usr/local/bin/rigel-live-setup"]="0:0:755"
  ["/usr/local/bin/rigel-install"]="0:0:755"
  ["/usr/local/share/rigel"]="0:0:755"
)
