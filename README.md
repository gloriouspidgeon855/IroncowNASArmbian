# IroncowNASArmbian
Armbian config files for Ironcow AI NAS 1

rk3568-nas.dtb, armbianEnv.txt, and extlinux.conf are the two files necessary to add to an Armbian Linux v6.12 Odroid M1S image to make it hardware compatible for the Ironcow AI NAS 1.

rk3568-nas.dtb should be placed:

/boot/dtb/rockchip/rk3568-nas.dtb

extlinux.conf should be placed:

/boot/extlinux/extlinux.conf

armbianEnv.txt should be placed:

/boot/armbianEnv.txt

#IMPORTANT!

You ABSOLUTELY MUST edit the UUID in BOTH armbianEnv.txt AND extlinux.conf to match the UUID of the bootable partition on the image YOU flash!!! Otherwise your device will NOT boot, and you WILL be dropped to an emergency shell to figure it out on your own!

The rk3568-nas.dts file was compiled with the linux 6.12 kernel files based on information from the stock .dtb file and comparison with the very hardware similar QNAP TS433 existing .dts file in the mainline kernel.
