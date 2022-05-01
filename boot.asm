    bits 16
    org 0x7c00

    ; Key Memory Addresses:
    ;   0'0000..0'7BFF - Stack.
    ;   0'7C00..0'7DFF - This Code.
    ;   1'0000..1'FFFF - World State A.
    ;   2'0000..2'FFFF - World State B.
    ;   A'0000..A'FFFF - VGA VRAM.
    ;   F'0000..F'FFFF - BIOS ROM.

    ; Configurable:

%define INITIAL_SP              0x7c00
%define STATE_A_SEGMENT         0x1000
%define STATE_B_SEGMENT         0x2000
%define DEAD_COLOUR             0x131418
%define LIVE_COLOUR             0xFFEE58
%define STEPS_PER_SECOND        20

    ; Non-configurable:

%define WORLD_WIDTH             256
%define WORLD_HEIGHT            256
%define VIDEO_WIDTH             640
%define VIDEO_HEIGHT            480
%define VRAM_SEGMENT            0xA000
%define BIOS_ROM_SEGMENT        0xF000

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
    ; For simplicity, our constants are defined as 8-bit RGB, so disgard the
    ; bottom 2 bits of each channel.

    ; Reprogram colour 1.
    mov     dx, 0x03c8
    mov     al, 0
    out     dx, al

    mov     dx, 0x03c9
    mov     al, 0x3f & (DEAD_COLOUR >> 18)
    out     dx, al
    mov     al, 0x3f & (DEAD_COLOUR >> 10)
    out     dx, al
    mov     al, 0x3f & (DEAD_COLOUR >> 2)
    out     dx, al

    ; Reprogram colour 2.
    mov     dx, 0x03c8
    mov     al, 63
    out     dx, al

    mov     dx, 0x03c9
    mov     al, 0x3f & (LIVE_COLOUR >> 18)
    out     dx, al
    mov     al, 0x3f & (LIVE_COLOUR >> 10)
    out     dx, al
    mov     al, 0x3f & (LIVE_COLOUR >> 2)
    out     dx, al

    ret


InitWorld:
    ; To provide some interesting initial state values, copy the raw content of
    ; the BIOS ROM into the current world state segment.
    mov     ax, BIOS_ROM_SEGMENT
    mov     ds, ax
    xor     si, si

    mov     ax, STATE_A_SEGMENT
    mov     es, ax
    xor     di, di

    mov     cx, (WORLD_WIDTH * WORLD_HEIGHT) / 2

    ; Ensure that each byte is only set to 0 or 1.
.Loop:
    lodsw
    and     ax, 0x0101
    stosw

    loop    .Loop

    ret


InitTimer:
    ; Configure the programmable interrupt timer:
    ;   Bit 0    (Use BCD) - No
    ;   Bit 1..3 (Mode)    - Rate generator
    ;   Bit 4..5 (Access)  - Low byte then high byte
    ;   Bit 6..7 (Channel) - Channel 0 (IRQ0)
    mov     al, 0b00110100
    out     0x43, al

    ; Set frequency divisor for channel 0.
    mov     al, 0xff & CLOCK_DIVISOR
    out     0x40, al
    mov     al, 0xff & (CLOCK_DIVISOR >> 8)
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

    ; Wait for 18 interrupt timer ticks.
    sti
    mov     al, 18
.TimerDivider:
    hlt
    dec     al
    jnz     .TimerDivider
    cli

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

    ; AL = Live neighbour count.
    ; AH = Current cell state.
    xor     ax, ax

    ; BL = Cell X.
    ; BH = Cell Y.
    mov     bx, cx

    ; Count live cells above.
    dec     bh
    add     al, [bx - 1]
    add     al, [bx]
    add     al, [bx + 1]

    ; Count live cells on current row.
    inc     bh
    add     al, [bx - 1]
    mov     ah, [bx]                ; Current cell.
    add     al, [bx + 1]

    ; Count live cells below.
    inc     bh
    add     al, [bx - 1]
    add     al, [bx]
    add     al, [bx + 1]

    ; AL = Next state.
    test    ah, ah
    jz      .CurrentlyDead

.CurrentlyLive:
    cmp     al, 2
    je      .RemainLive

    cmp     al, 3
    je      .RemainLive

    jmp     .BecomeDead

.CurrentlyDead:
    cmp     al, 3
    je      .BecomeLive

    jmp     .RemainDead

.RemainLive:
.BecomeLive:
    mov     al, 1
    jmp     .WriteNextState

.RemainDead:
.BecomeDead:
    mov     al, 0

.WriteNextState:

    ; Write next state to ES:DI and increment DI.
    stosb


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
