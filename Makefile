.PHONY: all
all: boot.img

%.bin: %.asm
	nasm -f bin -o $@ $<

boot.img: boot.bin
	dd of=$@ if=/dev/zero seek=0 bs=1474560 count=1
	dd of=$@ if=$< seek=0 bs=512 conv=notrunc status=noxfer

.PHONY: run
run: boot.img
	qemu-system-i386 -monitor stdio -m 1M -drive media=disk,format=raw,file=$<

.PHONY: dump
dump: boot.bin
	objdump -D $< -b binary -m i8086 -M intel

.PHONY: clean
clean:
	rm -fv boot.bin boot.img
