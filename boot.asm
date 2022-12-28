    bits 16
    org 0x7c00

    ; Key Memory Addresses:
    ;   0'0000..0'7BFF - Stack.
    ;   0'7C00..0'7DFF - This Code.
    ;   1'0000..1'FFFF - World State A.
    ;   2'0000..2'FFFF - World State B.
    ;   A'0000..A'FFFF - VGA VRAM.

    ; Configurable:

%define INITIAL_SP              0x7c00
%define STATE_A_SEGMENT         0x1000
%define STATE_B_SEGMENT         0x2000
%define DEAD_COLOUR             0x131418
%define LIVE_COLOUR             0xFFEE58
%define STEPS_PER_SECOND        20

    ; Set bits indicate the quantity of live neighbours that cause a live cell
    ; to remain live (otherwise it becomes dead) or for a dead cell to become
    ; live (otherwise is remains dead).
%define LIVE_TO_DEAD            0b00001100
%define DEAD_TO_LIVE            0b00001000

    ; Non-configurable:

%define WORLD_WIDTH             256
%define WORLD_HEIGHT            256
%define VIDEO_WIDTH             640
%define VIDEO_HEIGHT            480
%define VRAM_SEGMENT            0xA000

    ; The hardware interrupt timer has a frequency of 1193180 Hz. The maximum
    ; frequency divisor value we can set is 65535, which produces a timer
    ; frequency of approximately 18 Hz. By waiting for 18 timer interrupts in
    ; between each frame, we can act as if the timer actually has a frequency
    ; of around 65535 instead, which makes the calculation much simpler:
%define CLOCK_DIVISOR           0xffff / STEPS_PER_SECOND


%macro LOAD_STANDARD_SS 0
    xor     ax, ax
    mov     ss, ax
%endmacro


Start:
    cli
    jmp     0:Main


InitVGA:
    ; Use graphics mode 0x11: 640x480 monochrome (2-colour).
    mov     ax, 0x11
    int     0x10

    ; Reprogram the colour palette in the VGA DAC. Each RGB channel is 6-bit.
    ; Write the palette index byte to 0x3c8, then write the R, G, then B bytes
    ; of that colour to 0x3c9.
    ; For simplicity, our colour constants are defined with 8-bit channels; the
    ; bottom 2 bits of each channel will be thrown away.

    ; Reprogram colour 1 (palette index 0).
    mov     dx, 0x3c8
    mov     al, 0
    out     dx, al

    inc     dx          ; 0x3c9
    mov     al, 0x3f & (DEAD_COLOUR >> 18)
    out     dx, al
    mov     al, 0x3f & (DEAD_COLOUR >> 10)
    out     dx, al
    mov     al, 0x3f & (DEAD_COLOUR >> 2)
    out     dx, al

    ; Reprogram colour 2 (palette index 63).
    dec     dx          ; 0x3c8
    mov     al, 63
    out     dx, al

    inc     dx          ; 0x3c9
    mov     al, 0x3f & (LIVE_COLOUR >> 18)
    out     dx, al
    mov     al, 0x3f & (LIVE_COLOUR >> 10)
    out     dx, al
    mov     al, 0x3f & (LIVE_COLOUR >> 2)
    out     dx, al

    ret


InitWorld:
    ; Generate random numbers using a 16-bit Xorshift PRNG.
    ; Adapted from: http://www.retroprogramming.com/2017/07/xorshift-pseudorandom-numbers-in-z80.html
    ; Read and combine the current clock second and minute values from the CMOS
    ; to use as the initial seed value.

    ; Use clock seconds as lower 8 bits.
    mov     al, 0
    out     0x70, al
    in      al, 0x71
    movzx   dx, al

    ; Use clock minutes as upper 8 bits.
    mov     al, 2
    out     0x70, al
    in      al, 0x71
    shl     ax, 8
    or      dx, ax

    mov     ax, STATE_A_SEGMENT
    mov     es, ax
    xor     di, di

    ; Start at 256 * 256.
    xor     cx, cx

.Loop:
    ; Xorshift algorithm.
    mov     ax, dx
    shl     ax, 7
    xor     dx, ax

    mov     ax, dx
    shr     ax, 9
    xor     dx, ax

    mov     ax, dx
    shl     ax, 8
    xor     dx, ax

    ; Use bottommost bit as cell value.
    mov     al, dl
    and     al, 1
    stosb

    loop    .Loop

    ret


InitTimer:
    ; Configure the programmable interrupt timer:
    ;   Bit 0    (BCD or binary) -   0 - Binary.
    ;   Bit 1..3 (Mode)          - 010 - Rate generator.
    ;   Bit 4..5 (Access)        -  11 - Low byte then high byte.
    ;   Bit 6..7 (Channel)       -  00 - Channel 0 (IRQ0).
    mov     al, 0b00_11_010_0
    out     0x43, al

    ; Set frequency divisor for channel 0.
    mov     ax, CLOCK_DIVISOR
    out     0x40, al
    mov     al, ah
    out     0x40, al

    ret


Main:
    ; Set up stack.
    LOAD_STANDARD_SS
    mov     sp, INITIAL_SP

    call    InitVGA
    call    InitTimer
    call    InitWorld

    ; CX = Segment containing world state for current time-step.
    ; DX = Segment containing world state the next time-step.

    mov     cx, STATE_A_SEGMENT
    mov     dx, STATE_B_SEGMENT

.MainLoop:
    mov     ds, cx
    mov     es, dx

    call    TickAndRender

    ; Swap segments.
    mov     cx, es
    mov     dx, ds

    ; Wait for 18 interrupt timer ticks (see note by `CLOCK_DIVISOR`).
    mov     al, 18

.TimerDivider:
    sti
    hlt
    cli

    dec     al
    jnz     .TimerDivider

    jmp     .MainLoop


TickAndRender:
    ; Parameters:
    ;   DS - World state for current time-step (read from).
    ;   ES - World state for next time-step (written to).
    ;
    ; Register Usage:
    ;   SS - VGA RAM.
    ;   BP - Memory access for SS.
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
    ; Notes:
    ;   This function does not make use of the stack, so the stack segment is
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

    mov     ax, VRAM_SEGMENT
    mov     ss, ax

    xor     cx, cx
    xor     di, di

.LoopCells:
    ; BL = Cell X.
    ; BH = Cell Y.
    mov     bx, cx

    ; AH = Current cell state.
    mov     ah, [bx]

    ; AL = Number of live neighbours.
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

    mov     cl, al
    mov     al, DEAD_TO_LIVE

    test    ah, ah
    jz      .CurrentlyDead

    mov     al, LIVE_TO_DEAD
.CurrentlyDead:

    ; Get next state.
    shr     al, cl
    and     al, 1

    ; Write next state to ES:DI and increment DI.
    stosb

    ; Restore cell X.
    mov     cl, bl

    ; BL = State to draw (current cell state).
    mov     bl, ah

    ; BP = Pixel byte offset.
    movzx   ax, ch
    add     ax, (VIDEO_HEIGHT - WORLD_HEIGHT) / 2
    mov     dx, VIDEO_WIDTH / 8
    mul     dx

    movzx   dx, cl
    add     dx, (VIDEO_WIDTH - WORLD_WIDTH) / 2
    shr     dx, 3
    add     ax, dx

    mov     bp, ax

    ; Save CX.
    mov     dx, cx

    ; AL = Bitmask.
    mov     al, 0x80
    and     cl, 7
    shr     al, cl

    ; AH = Current pixel value.
    mov     ah, [ss:bp]

    ; Set or unset bit in AH.
    test    bl, bl
    jnz     .SetLive

    not     al
    and     ah, al
    jmp     .WritePixel

.SetLive:
    or      ah, al

.WritePixel:
    ; Write back AH.
    mov     [ss:bp], ah

    ; Restore CX.
    mov     cx, dx

    ; Next cell.
    inc     cx
    test    cx, cx
    jnz     .LoopCells

    ; Restore stack segment.
    LOAD_STANDARD_SS

    ret


    ; Pad up to 510 bytes, then write the 2-byte floppy boot signature.
    times (510 - ($ - $$)) db 0
    dw 0xaa55
