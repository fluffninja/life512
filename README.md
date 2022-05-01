# Conway's Game of Life in a Bootloader

This is an implementation of [Conway's Game of Life](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life) written in 16-bit x86 assembly that fits inside a 512-byte floppy bootloader (with room to spare).

The world is comprised of 256 cells horizontally and vertically (65535 in total). During each simulation step, DS points to the current world state, ES points to the next world state, and SS is repurposed as a third data-segment for writing to VRAM.

Each cell's state is stored as one byte. Although somewhat inefficient memory-wise, this simplifies the code by allowing a 16-bit X register to hold the cell's byte offset into the segment while the corresponding L and H registers automatically hold the cell's X and Y co-ordinates respectively. The L and H registers can then be acted on separately, with overflow creating the wraparound at the world's edges.

BIOS video mode 11h (640x480 monochrome) is used for graphics, allowing the whole 256x256 world to be seen at once. The palette is customised via the VGA DAC. The interrupt timer is used to control the speed of execution.

The initial state of the world is populated by copying in the content of the BIOS ROM.

![Screenshot](screenshot.png)

## Building

Install `nasm`, then build using:

```sh
make all
```

## Running

Install `qemu-system-x86`, then run using:

```sh
make run
```
