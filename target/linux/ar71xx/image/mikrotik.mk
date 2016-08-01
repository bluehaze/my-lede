define Device/rb-common
  LOADER_TYPE := elf
  DEVICE_PACKAGES := kmod-ath5k kmod-ath9k
  DEVICE_PROFILE := Default
  KERNEL_INITRAMFS :=
  KERNEL_INSTALL :=
  KERNEL = kernel-bin | lzma | loader-kernel | kernel2minor $$(KERNEL2MINOR_ARGS)
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin = append-rootfs | pad-rootfs | combined-image | check-size $$$$(IMAGE_SIZE)
endef

define Device/NOR-1024b
$(Device/rb-common)
  DEVICE_TITLE := Mikrotik devices with NOR-1024b flash
  BLOCKSIZE := 64k
  IMAGE_SIZE := 16000k
  KERNEL2MINOR_ARGS := -s 1024 -i 0 -p NOR01024 -e
endef
TARGET_DEVICES += NOR-1024b

define Device/NAND-2048b
$(Device/rb-common)
  DEVICE_TITLE := Mikrotik devices with NAND-2048b ecc flash
  BLOCKSIZE := 128k
  IMAGE_SIZE := 32000k
  KERNEL2MINOR_ARGS := -s 2048 -i 65536 -p NND02048 -e -c
endef
TARGET_DEVICES += NAND-2048b

define Device/NAND-512b
$(Device/rb-common)
  DEVICE_TITLE := Mikrotik(RB4xx) devices with NAND-512b ecc flash
  BLOCKSIZE := 16k
  IMAGE_SIZE := 32000k
  KERNEL2MINOR_ARGS := -s 512 -i 65536 -p NND00512 -e -c
endef
TARGET_DEVICES += NAND-512b
