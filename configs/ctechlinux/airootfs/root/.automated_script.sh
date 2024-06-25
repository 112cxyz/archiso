#!/bin/bash

SCRIPT_NAME=$(basename "$0")

dhcpcd

sleep 20

# Function to update the install script
update_install_script() {
  wget -O /root/installer_web.sh "http://112c.co.uk/ctechtools/installer.sh"
  if [ $? -eq 0 ]; then
    chmod +x /root/installer_web.sh
    if [ "$SCRIPT_NAME" != "installer_web.sh" ]; then
      exec /root/installer_web.sh
    fi
  else
    echo "Failed to update the installer script. Continuing with the current script."
  fi
}

# Update the install script at the start
update_install_script

# Function to list available disks
list_disks() {
  lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac
}

# Display welcome message
dialog --title "Welcome" --msgbox "Welcome to CTECH Linux Installer" 10 60

# Prompt user to select block device
DEVICE=$(dialog --title "Select Block Device" --menu "Choose the block device to install CTECH Linux:" 20 60 10 $(list_disks) 3>&1 1>&2 2>&3)

# Validate if device is selected
if [ -z "$DEVICE" ]; then
  dialog --title "Error" --msgbox "No device selected. Exiting installation." 10 60
  exit 1
fi

# Partitioning the selected device
dialog --title "Partitioning" --yesno "Do you want to partition $DEVICE automatically?" 10 60
if [ $? -eq 0 ]; then
  (
    echo "Creating partitions..."
    parted $DEVICE --script mklabel gpt
    parted $DEVICE --script mkpart ESP fat32 1MiB 201MiB    # EFI partition
    parted $DEVICE --script set 1 boot on
    parted $DEVICE --script mkpart primary ext4 201MiB 100%  # Root partition
    mkfs.fat -F32 ${DEVICE}1
    mkfs.ext4 ${DEVICE}2
  ) > /dev/tty
fi

# Installation
dialog --title "Installation" --msgbox "Starting installation on $DEVICE..." 10 60
mount ${DEVICE}2 /mnt
mkdir -p /mnt/boot/efi
mount ${DEVICE}1 /mnt/boot/efi
pacstrap /mnt base linux linux-firmware grub networkmanager wget sudo efibootmgr dialog git openssh archlinux-keyring screen > /dev/tty
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
# install bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# copy grub efi to the /boot/efi/EFI/BOOT/BOOTX64.EFI
mkdir -p /boot/efi/EFI/BOOT
cp /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

# generate the fstab
genfstab -U /mnt >> /mnt/etc/fstab

# enable network manager
systemctl enable NetworkManager

# Set the timezone
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc

# Set the locale
sed -i 's/#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen

# Generate the locale
locale-gen

# Set the language
echo "LANG=en_GB.UTF-8" > /etc/locale.conf

# download first time boot script and make it executable
wget -O /root/first-boot.sh "http://112c.co.uk/ctechtools/first-boot.sh"
chmod +x /root/first-boot.sh

# edit the bashrc to run the first boot script on login
echo "chmod 777 /root/first-boot.sh && ./root/first-boot.sh" >> /root/.bashrc

# things like hostname and password will be set in the first boot script

# enable auto login for root user
mkdir -p /etc/systemd/system/getty@tty1.service.d
touch /etc/systemd/system/getty@tty1.service.d/autologin.conf
echo "[Service]" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
echo "ExecStart=-/usr/bin/agetty --autologin root --noclear %I $TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf


EOF

chmod +x /root/first-boot.sh
chmod +x /root/.bashrc
pacman -S --noconfirm dialog screen
# Add script to run on boot using screen
echo "exec /root/first-boot.sh" >> /root/.bashrc

# Inform user about the completion and next steps
dialog --title "Installation Complete" --msgbox "CTECH Linux installation is complete. Please reboot your system." 10 60

reboot