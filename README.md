# Conway's Game of Life in a Bootloader

This is an implementation of [Conway's Game of Life](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life) that fits within a 512-byte floppy bootloader. It's written in 16-bit x86 assembly, limited to instructions available on the [Intel 80186](https://en.wikipedia.org/wiki/X86_instruction_listings) \*.

The world is made up of 256x256 cells that are alive or dead (65,536 in total). To eliminate the additional instructions that would be required to perform bitwise operations, each cell's state is stored using one byte. Thus it takes 65,536 bytes to store the state of the world, which is an _entire_ 16-bit x86 segment. During each simulation step, `DS` points to the current world state and `ES` points to the next world state. `SS` is repurposed as a third data-segment for writing to VRAM. The main simulation loop therefore does not make use of the stack, instead performing a lot of register juggling in order to run the simulation and draw to the screen in a single pass.

Another advantage to storing each cell's state as a byte, although inefficient memory-wise, is that it allows `CX` to hold the cell's byte offset into the segment while `CL` and `CH` _automatically_ hold the cell's X and Y co-ordinates respectively. `CL` and `CH` can then be incremented and decremented separately, with the resulting lack of carry between the two halves creating the correct wraparound behaviour at the world's edges along the X-axis.

BIOS video mode `11h` (640x480 monochrome) is used for graphics, allowing the whole 256x256 world to be seen at once (though no scaling is performed, so it's unfortunately a tad small). The palette is customised via the VGA DAC. The interval timer (IRQ0) is used to control the speed of execution.

The initial state of the world is populated using a xorshift pseudorandom number generator ([based on an implementation by John Metcalf](http://www.retroprogramming.com/2017/07/xorshift-pseudorandom-numbers-in-z80.html)). The seed value for PRNG is a combination of the current clock second and minute values read from the CMOS.

\* The only 80186-specific 'instruction' used that's absent from the original 8086 is `SHL` and `SHR` with an immediate operand greater than `1`.

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
