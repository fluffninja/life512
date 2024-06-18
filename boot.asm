    ; life512
    ; =======
    ; Conway's Game of Life in 512 Bytes (of 8086 Assembly).
    ;

    bits 16
    cpu 8086
    org 0x7c00

    ; Key Memory Addresses
    ; ====================
    ;   0'0000..0'7BFF - Program Stack (directly beneath this code).
    ;   0'7C00..0'7DFF - This Code (unchangeable; loaded by the BIOS).
    ;   1'0000..1'FFFF - World State A.
    ;   2'0000..2'FFFF - World State B.
    ;   A'0000..A'FFFF - VGA RAM (unchangeable).
    ;

    ; Configurable Constants
    ; ======================

%define INITIAL_SP              0x7c00
%define SEGMENT_WORLD_STATE_A   0x1000
%define SEGMENT_WORLD_STATE_B   0x2000
%define COLOR_DEAD_CELL         0x281f1f
%define COLOR_LIVE_CELL         0x17d7d7
%define STEPS_PER_SECOND        20

    ; The set bits indicate the number of live neighboring cells that allow for
    ; a live cell to remain live (otherwise it becomes dead), or that allow for
    ; a dead cell to become live (otherwise it remains dead).
    ;
%define LIVE_CELL_TO_LIVE_CELL  0b00001100
%define DEAD_CELL_TO_LIVE_CELL  0b00001000

    ; Non-Configurable Constants
    ; ==========================

%define WORLD_WIDTH             256
%define WORLD_HEIGHT            256
%define VIDEO_WIDTH             640
%define VIDEO_HEIGHT            480
%define SEGMENT_VGA_RAM         0xA000

    ; The hardware interval timer has a frequency of 1193180 Hz. The maximum
    ; frequency divisor value we can set is 65535 (which produces a timer
    ; frequency of 18 Hz). By waiting for 18 timer interrupts between each
    ; frame, we can act as if the timer actually has a frequency of 65535,
    ; which makes calculating all of this much simpler.
    ;
%define CLOCK_FREQUENCY_HZ      1193180
%define MAX_FREQUENCY_DIVISOR   65535

%define MAKEWORD(HI, LO) (((HI) & 0xff) << 8 | ((LO) & 0xff))


%macro LOAD_STANDARD_SS 0
    xor     ax, ax
    mov     ss, ax
%endmacro


%macro INITIALIZE_VIDEO 0
    ; Set the VGA graphics mode (AH := 0) to monochrome 640x480 (AL := 0x11).
    mov     ax, MAKEWORD(0, 0x11)
    int     0x10

    ; Reprogram the color palette used by the VGA DAC.
    ; The DAC specifies each channel as a 6-bit value. For ease, we allow our
    ; cell color constants to be defined as familiar 8-bit RGB values, and then
    ; throw away the bottom 2 bits of each channel.
    ; The palette is programmed by first writing the palette index to 0x3c8,
    ; then writing the R, G, and B channel values in turn to 0x3c9.
    ; Monochrome VGA graphics use palette entries 0 and 63.

    ; Set color 1.
    mov     dx, 0x3c8
    mov     al, 0
    out     dx, al

    inc     dx          ; DX := 0x3c9
    mov     al, 0x3f & (COLOR_DEAD_CELL >> 18)
    out     dx, al
    mov     al, 0x3f & (COLOR_DEAD_CELL >> 10)
    out     dx, al
    mov     al, 0x3f & (COLOR_DEAD_CELL >> 2)
    out     dx, al

    ; Set color 2.
    dec     dx          ; DX := 0x3c8
    mov     al, 63
    out     dx, al

    inc     dx          ; DX := 0x3c9
    mov     al, 0x3f & (COLOR_LIVE_CELL >> 18)
    out     dx, al
    mov     al, 0x3f & (COLOR_LIVE_CELL >> 10)
    out     dx, al
    mov     al, 0x3f & (COLOR_LIVE_CELL >> 2)
    out     dx, al
%endmacro


%macro INITIALIZE_WORLD 0
    ; Generate random numbers using a 16-bit Xorshift PRNG.
    ; Adapted from: http://www.retroprogramming.com/2017/07/xorshift-pseudorandom-numbers-in-z80.html
    ; Read and combine the current clock second and minute values from the CMOS
    ; to use as the initial seed value.
    ; To ensure that NMIs remain disabled, bit 8 must remain set for all writes
    ; to port 0x70 (CMOS address select).

    ; Use clock seconds as lower 8 bits.
    mov     al, 0x80
    out     0x70, al
    in      al, 0x71
    mov     dl, al

    ; Use clock minutes as upper 8 bits.
    mov     al, 0x82
    out     0x70, al
    in      al, 0x71
    mov     dh, al

    mov     ax, SEGMENT_WORLD_STATE_A
    mov     es, ax
    xor     di, di

    ; Start at zero to loop 256*256 times.
    xor     cx, cx

%%Loop:
    ; Borrow CL for shift.
    mov     bl, cl

    ; Xorshift algorithm.
    mov     ax, dx
    mov     cl, 7
    shl     ax, cl
    xor     dx, ax

    mov     ax, dx
    mov     cl, 9
    shr     ax, cl
    xor     dx, ax

    mov     ax, dx
    dec     cx          ; CL := 8
    shl     ax, cl
    xor     dx, ax

    ; Use bottommost bit as cell value.
    mov     al, dl
    and     al, 1
    stosb

    ; Restore CL.
    mov     cl, bl

    loop    %%Loop
%endmacro


%macro INITIALIZE_TIMER 0
    ; Configure the programmable interval timer:
    ;   Bits | Field Name    | Configured Value
    ;   0    | BCD or Binary |   0 - Binary
    ;   1..3 | Mode          | 010 - Rate generator
    ;   4..5 | Access        |  11 - Low byte then high byte
    ;   6..7 | Channel       |  00 - Channel 0 (IRQ0)
    mov     al, 0b00_11_010_0
    out     0x43, al

    ; Set frequency divisor for channel 0.
    mov     ax, MAX_FREQUENCY_DIVISOR / STEPS_PER_SECOND
    out     0x40, al
    mov     al, ah
    out     0x40, al
%endmacro


%macro TICK_AND_RENDER 0
    ; Parameters:
    ;   DS - World state for current time-step (read from).
    ;   ES - World state for next time-step (written to).
    ;
    ; Register Usage:
    ;   SS - VGA RAM.
    ;   SI - Memory access for SS *.
    ;   BX - Memory access for DS.
    ;       BL - Cell X co-ordinate.
    ;       BH - Cell Y co-ordinate.
    ;   CX - Current cell location.
    ;       CL - Cell X co-ordinate.
    ;       CH - Cell Y co-ordinate.
    ;   DI - Memory access for ES.
    ;   AX - Arithmetic/scratch.
    ;   DX - Arithmetic/scratch.
    ;
    ;   * SI is used because it's our only spare register besides BP (SP needs
    ;     to remain unchanged so that the stack remains in the correct location
    ;     after restoring SS), but indirect accesses with BP require a larger
    ;     encoding due to the mandatory displacement field (even if zero).
    ;
    ; Notes:
    ;   This routine does not make use of the stack, since the stack segment is
    ;   repurposed as a third data segment to provide VRAM access.
    ;
    ;   The world is 256 by 256, with each cell represented as a single byte.
    ;   While not necessarily the most efficient in terms of space, it allows
    ;   us to use some tricks to speed up execution: if a cell's index in the
    ;   world state (0..256^2-1) is stored in the combined X register, then
    ;   the L and H subregisters _automatically_ contain that cell's X and Y
    ;   co-ordinates respectively. A correct raster scan is achieved just by
    ;   incrementing the X register. Performing arithmetic on the L and H
    ;   registers separately provides wrap-around at the edges of the world.
    ;

    mov     ax, SEGMENT_VGA_RAM
    mov     ss, ax

    xor     cx, cx
    xor     di, di

%%LoopCells:
    ; While CX is our cell counter, only BX and BP can be used for indexed
    ; addressing. Of those, only BX has upper and lower halves, which we can
    ; use to access the rows of cells above and below (with wrap-around at the
    ; edges of the world).
    ; BL = Cell X, BH = Cell Y.
    mov     bx, cx

    ; AH = Current cell state.
    mov     ah, [bx]

    ; AL = Number of live neighboring cells.
    mov     al, 0
    add     al, [bx - 1]
    add     al, [bx + 1]

    dec     bh
    add     al, [bx - 1]
    add     al, [bx]
    add     al, [bx + 1]

    add     bh, 2
    add     al, [bx - 1]
    add     al, [bx]
    add     al, [bx + 1]

    ; CL is now needed as the operand for shift operations, so save CX in BX
    ; until the end of the loop.
    ; BL = Cell X, BH = Cell Y.
    mov     bx, cx

    ; Get ready to shift by the calculated number of live neighbors.
    mov     cl, al

    ; AL = State-transition ruleset for current state.
    mov     al, DEAD_CELL_TO_LIVE_CELL

    test    ah, ah
    jz      %%CellCurrentlyDead

    mov     al, LIVE_CELL_TO_LIVE_CELL
%%CellCurrentlyDead:

    ; AL = Next state.
    shr     al, cl
    and     al, 1

    ; Write next state to ES:DI and increment DI.
    stosb

    ;
    ; Draw the current cell state. Calculate pixel's byte offset into VGA RAM
    ; and set the cell's bit as appropriate.
    ;

    ; CH = State to draw (current cell state).
    mov     ch, ah

    ; SI = (Y + OffsetTop) * (VideoWidth / 8)
    mov     al, bh
    mov     ah, 0
    add     ax, (VIDEO_HEIGHT - WORLD_HEIGHT) / 2
    mov     dx, VIDEO_WIDTH / 8
    mul     dx

    mov     si, ax

    ; SI += (X + OffsetLeft) / 8
    mov     al, bl
    mov     ah, 0
    add     ax, (VIDEO_WIDTH - WORLD_WIDTH) / 2
    mov     cl, 3
    shr     ax, cl

    add     si, ax

    ; AL = Mask for cell bit inside pixel byte.
    mov     al, 0x80
    mov     cl, bl
    and     cl, 7
    shr     al, cl

    ; AH = Current pixel byte value.
    mov     ah, [ss:si]

    ; Set or unset the cell bit.
    test    ch, ch
    jnz     %%SetCellLive

    not     al
    and     ah, al

    jmp     %%WritePixel

%%SetCellLive:
    or      ah, al

%%WritePixel:
    ; Write back pixel byte.
    mov     [ss:si], ah

    ; Restore CX.
    mov     cx, bx

    ; Next cell.
    inc     cx
    jnz     %%LoopCells

    ; Restore stack segment.
    LOAD_STANDARD_SS
%endmacro


    ; Program entrypoint.
Start:
    cli
    cld

    ; Set up stack.
    LOAD_STANDARD_SS
    mov     sp, INITIAL_SP

    INITIALIZE_VIDEO
    INITIALIZE_TIMER
    INITIALIZE_WORLD

    ; CX = Segment containing world state for current time-step.
    ; DX = Segment containing world state the next time-step.

    mov     cx, SEGMENT_WORLD_STATE_A
    mov     dx, SEGMENT_WORLD_STATE_B

.MainLoop:
    mov     ds, cx
    mov     es, dx

    TICK_AND_RENDER

    ; Swap segments.
    mov     cx, es
    mov     dx, ds

    ; Wait for N timer ticks (see note by `CLOCK_FREQUENCY_HZ`).
    mov     al, CLOCK_FREQUENCY_HZ / MAX_FREQUENCY_DIVISOR

.TimerDivider:
    sti
    hlt
    cli

    dec     ax
    jnz     .TimerDivider

    jmp     .MainLoop


    ; Pad up to 510 bytes, then write the 2-byte floppy boot signature.
    times (510 - ($ - $$)) db 0
    dw 0xaa55
