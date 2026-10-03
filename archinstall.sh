#!/bin/bash

set -e
if ping -c 1 archlinux.org &> /dev/null; then
        echo -e "\033[32mInternet connection: OK\033[0m"
    else
        echo "no internet connection"
        exit 1
    fi
read -p "какое имя пользователя вы хотите?" username
name=${username:-user}
read -p "хотите ли вы одинаковый пароль пользователя и root? [yes/No]" rup
if [[ "$rup" == "y" || "$rup" == "yes" ]]; then
        read -p  "укажите пароль пользователя и root:" password
        userpass="$password"
        rootpass="$password"
    else
        read -p "root password:" rp
        read -p "user password:" up
        userpass="$up" 
        rootpass="$rp"
fi
read -p "pc name:" hostname
lsblk
read -p "какой диск будем использовать? пример [sda]" disk
disk="$disk"
echo "ваши данные:"
echo "username: $username"
echo "user password: $userpass"
echo "root password: $rootpass"
echo "PC name: $hostname"
echo "disk:" $disk
read -p "хотите продолжить? все данные с диска будут удалены. [yes/No]" p
if [[ "$p" == "y" || "$p" == "yes" ]]; then
    echo "продолжаем . . . "
    else 
        exit 1
fi
echo "1 разметка диска"
wipefs -a /dev/$disk
parted -s /dev/$disk mklabel gpt
parted -s /dev/$disk mkpart ESP fat32 1Mib 512Mib
parted -s /dev/$disk set 1 boot on
parted -s /dev/$disk mkpart primary ext4 513mib 61953Mib
parted -s /dev/$disk mkpart primary ext4 61954Mib 100%
echo "2 форматирование разделов"
mkfs.fat -F 32 /dev/${disk}1
mkfs.ext4 /dev/${disk}3
mkfs.ext4 /dev/${disk}2
echo "3 монтирование разделов"
mount /dev/${disk}3 /mnt
mount --mkdir /dev/${disk}1 /mnt/boot
mount --mkdir /dev/${disk}2 /mnt/home
echo "4 pacstrap"

if ping -c 1 archlinux.org &> /dev/null; then
        echo -e "\033[32mInternet connection: OK\033[0m"
    else
        exit 1
    fi
pacstrap -K /mnt linux linux-firmware base base-devel efibootmgr networkmanager vim micro dhcpcd iwd
genfstab -U /mnt >> /mnt/etc/fstab
		export $username	
		export $rootpass
		export $userpass
		export $hostname
		echo "5 chroot"
		arch-chroot /mnt /bin/bash << 'EOF'
set -e

ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8"
locale-gen

echo "$hostname" >/etc/hostname

echo "root:$rootpass" | chpasswd
useradd -m -G wheel,users,video -s /bin/bash $username
echo "$username:$userpass" | chpasswd
#systemctl enable dhcpcd
#systemctl enable iwd.service
sed -i 's/^#%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
sudo pacman -S grub	
grub-install --target=x86_64-efi --efi-directory=esp --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager
EOF
echo "6 reboot"
	echo -e "reboot..."
	umount -R /mnt
	

