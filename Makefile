# 3.5-Inch High-Density
FLOPPY_SIZE := 1440

all: boot.img

%.bin: %.asm
	nasm -f bin -o $@ $<

boot.img: boot.bin
	dd of=$@ if=/dev/zero seek=0 bs=$(FLOPPY_SIZE)K count=1 status=noxfer
	dd of=$@ if=$< seek=0 bs=512 conv=notrunc status=noxfer

boot.dump: boot.bin
	objdump -D $< -b binary -m i8086 -M intel >$@

run: boot.img
	qemu-system-i386 -monitor stdio -m 1M -drive media=disk,format=raw,file=$<

dump: boot.dump
	cat $<

hex: boot.bin
	hexdump -Cv $<

clean:
	rm -fv boot.bin boot.img boot.dump

.PHONY: all run dump hex clean
