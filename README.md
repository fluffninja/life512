# Conway's Game of Life in a Bootloader

This is an implementation of [Conway's Game of Life](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life) that fits within a 512-byte floppy bootloader. It's written in 16-bit x86 assembly, limited to instructions and addressing modes available on the original [Intel 8086](https://en.wikipedia.org/wiki/X86_instruction_listings) \*.

![Screenshot](screenshot.png)

## Implementation

### Memory Usage

The world is made up of 256x256 cells that are alive or dead (65,536 in total). To eliminate the additional instructions that would be required to perform bitwise operations, each cell's state is stored using one byte. Thus it takes 65,536 bytes to store the state of the world, which is an _entire_ 16-bit x86 segment. During each simulation step, `DS` points to the current world state and `ES` points to the next world state. `SS` is repurposed as a third data-segment for writing to VRAM. The main simulation loop therefore does not make use of the stack, instead performing a lot of register juggling in order to run the simulation and draw to the screen in a single pass.

Another advantage to storing each cell's state as a byte, although inefficient memory-wise, is that it allows `CX` to hold the cell's byte offset into the segment while `CL` and `CH` _automatically_ hold the cell's X and Y co-ordinates respectively. `CL` and `CH` can then be incremented and decremented separately, with the resulting lack of carry between the two halves creating the correct wraparound behaviour at the world's edges along the X-axis.

### Random Number Generator

The initial state of the world is populated using a xorshift pseudorandom number generator ([based on an implementation by John Metcalf](http://www.retroprogramming.com/2017/07/xorshift-pseudorandom-numbers-in-z80.html)).

The seed value for PRNG is derived from the current time, which is read from the CMOS.

### Graphics

BIOS video mode `11h` (1-bit 640x480) is used for graphics. This resolution allows the 256x256 world to be seen on screen at once. Unfortunately this requires additional instructions for reading and writing the individual bits for each cell.

The colour-palette is customised via the VGA DAC.

### Timing

The interval timer (IRQ0) is used to control the speed of execution.

### Limitations of the Original Intel 8086

As an additional challenge, the implementation is limited to using just the instructions and addressing modes available to the original [Intel 8086](https://en.wikipedia.org/wiki/X86_instruction_listings) (using NASM's `cpu 8086` directive).

This imposes some interesting limitations:

* Cannot use `shl` or `shr` with an immediate operand greater than `1` (must use `cl` instead).
* Can only perform indirect memory access using `bx`, `bp`, `si`, and `di`.
* No `movzx`.
* No `fs` or `gs` segments.

## Building

Install `nasm` (tested with version `2.15.05`), then build using:

```sh
make all
```

## Running

Install `qemu-system-i386` (tested with version `7.2.90`), then run using:

```sh
make run
```
