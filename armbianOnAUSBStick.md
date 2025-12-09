# How to load an Armbian image flashed to a USB stick for testing purposes.

After you have dissassembled the housing and plugged in a serial adapter to the debug serial port and opened a serial terminal at 1500000 baud, hold down Ctrl-C and then press the power button on the NAS. After the boot interrupt you will enter the uboot shell.

note: distro_bootcmd will fail to boot unless you have boot an extlinux.conf file in /boot/extlinux.conf on your USB drive configured to boot the image properly.
However, it is still necessary to run this command before manually booting, because the USB controller defaults to client mode and distro_bootcmd puts it in host mode.

# manual boot process with odroid m1s armbian image:

run distro_bootcmd
load usb 0:1 0x00280000 /boot/vmlinuz
load usb 0:1 0x0a200000 /boot/uInitrd
load usb 0:1 0x08300000 /boot/dtb/rockchip/rk3568-odroid-m1.dtb
setenv bootargs "root=/dev/sda1 rootdelay=10 rw console=tty1 console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xfe660000 cma=256M"
booti 0x00280000 0x0a200000 0x08300000

# if you're brave, here's how to load the stock OS with an (extremely) minimal root shell:

setenv bootargs ${bootargs} init=/bin/sh selinux=0
boot
