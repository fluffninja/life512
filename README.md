# Conway's Game of Life in a Bootloader

This is an implementation of [Conway's Game of Life](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life) that fits within the 512-byte floppy bootloader use by the IBM PC. In fact, the program takes up roughly only half of that space.

As an additional fun challenge, the implementation has been limited to using only the instructions and addressing modes available on the original [Intel 8086](https://en.wikipedia.org/wiki/X86_instruction_listings) processor.

![Screenshot](screenshot.png)

## Implementation

### Limitations of the Original Intel 8086

Being limited to what was available on the original Intel 8086 presents some interesting challenges:

* Indirect memory accesses can only be performed using the `bx`, `bp`, `si`, and `di` registers.
* The `shl` and `shr` instructions cannot be used with an immediate operand other than than `1`. Other shift amounts can only be specified by the `cl` register.
* Register operands for numerous instructions are fixed and cannot be changed (for example, `mul` always operates on `ax`).
* There is no `movzx` instruction.
* There are no `fs` and `gs` segments.
* Registers are 16 bits wide at most.

One of the main consequences of these limitations is the need for more instructions than would otherwise be necessary, largely as a result of the need to perform a lot of register juggling.

### Memory Usage

The game 'world' is a 256x256 grid of cells - 65,536 cells in total. Each cell is stored as one byte, which is `1` for a live cell and `0` for a dead cell. While it seems slightly wasteful to use an entire byte for each cell, doing so reduces the number of instructions that would be required to operate on a more compact representation.

As each cell is one byte, the world state at any one timestep occupies 65,534 bytes (64 kB) of memory. This happens to exactly fill a single 16-bit 8086 segment.

During each simulation step, `ds` points to the current world state and `es` points to the next world state. The stack segment, `ss`, is repurposed as a third data-segment that is used to read and write VGA RAM. As a result, the main simulation routine cannot make use of the stack. Game state update and rendering is done in a single pass.

Another advantage of using one byte for each cell is that it plays well with how the 8086's general purpose registers are split into high and low halves. For example, while `ax` might hold the linear offset of a cell, `al` and `ah` automatically hold the cell's X and Y co-ordinates respectively. Furthermore, `al` and `ah` can be incremented and decremented separately to create wraparound at the world's edges, without carrying into one another.

### Using PRNG for Initial World State

The initial state of the world is populated using a xorshift pseudorandom number generator ([based on an implementation by John Metcalf](http://www.retroprogramming.com/2017/07/xorshift-pseudorandom-numbers-in-z80.html)).

The seed value for PRNG is derived from the current time, which is read from the CMOS.

### VGA Graphics

BIOS video mode `11h` (1-bit monochrome 640x480) is used for graphics, with one pixel used for each cell. This resolution allows for the whole 256x256 world to be seen on screen at once (admittedly slightly on the small side).

Unfortunately, the use of 1-bit monochrome graphics mean that multiple pixels are stored in each byte, and extra instructions are required to pack these bits.

The colour-palette is customised on boot via writes to the VGA DAC.

### Timing

The programmable interval timer (IRQ0) is used to control the speed of execution.

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
