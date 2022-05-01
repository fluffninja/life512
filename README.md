# Conway's Game of Life in a Bootloader

This is an implementation of [Conway's Game of Life](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life) written in 16-bit x86 assembly that fits inside a 512-byte floppy bootloader.

The world is comprised of 256 cells horizontally and vertically (65535 total). During each simulation step, DS points to the current world state, ES points to the next world state, and SS is repurposed as a third data-segment for writing to VRAM.

Each cell's state is stored as one byte. Although somewhat inefficient memory-wise, it simplifies the code by allowing a 16-bit X register to hold the cell's byte offset into the segment while the corresponding L and H registers automatically hold the cell's X and Y co-ordinates respectively. The L an H registers can be incremented and decremented separately to easily create wraparound at the world's edges.

BIOS video mode 11h (640x480 monochrome) is used for graphics. The palette is customised via the VGA DAC. The interrupt timer is used to control the speed of execution.

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
