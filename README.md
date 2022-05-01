# Conway's Game of Life in a Bootloader

This is an implementation of [Conway's Game of Life](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life) that fits in a 512-byte floppy bootloader, written in 16-bit real-mode x86 assembly.

The world is comprised 256x256 cells that wrap around vertically and horizontally at the edges. Each cell is represented by one byte (inefficient memorywise, but it makes things simpler).

BIOS video mode 0x11 (monochrome 640x480) is used for graphics, with the world positioned in the middle of the screen. The 2-colour palette is customised by reprogramming the VGA DAC.

![Screenshot](screenshot.png)
