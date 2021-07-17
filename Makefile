AS := nasm
ASFLAGS := -f bin

.PHONY: all
all: boot.img

%.bin: %.asm
	$(AS) $(ASFLAGS) -o $@ $<

boot.img: boot.bin
	dd of=$@ if=/dev/zero seek=0 bs=1474560 count=1
	dd of=$@ if=$< seek=0 bs=512 conv=notrunc status=noxfer
