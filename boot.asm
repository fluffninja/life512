    bits 16
    org 0x7c00

    ; Key Memory Addresses:
    ;   0'0000..0'7BFF - Stack.
    ;   0'7C00..0'7DFF - This Code.
    ;   1'0000..1'FFFF - World State A.
    ;   2'0000..2'FFFF - World State B.
    ;   A'0000..A'FFFF - VGA VRAM.
    ;   F'0000..F'FFFF - BIOS ROM.

    ; Non-configurable:

%define WORLD_WIDTH             256
%define WORLD_HEIGHT            256
%define VIDEO_WIDTH             320
%define VIDEO_HEIGHT            200
%define VRAM_SEGMENT            0xA000
%define BIOS_SEGMENT            0xF000

    ; Configurable:

%define STATE_A_SEGMENT         0x1000
%define STATE_B_SEGMENT         0x2000
%define DEAD_COLOUR             0x01
%define LIVE_COLOUR             0x0f

Start:
    cli

    ; Normalise CS:IP to 0:7C00.
    jmp     0:Start._NormaliseCSIP
._NormaliseCSIP:

    xor     ax, ax
    mov     ss, ax
    mov     sp, 0x7c00

    ; Set graphics mode to 320x200 VGA.
    mov     ax, 0x0013
    int     0x10


    ; Initialise world
    ; ================
    ; To provide some interesting initial state values, copy the raw content of
    ; the BIOS ROM (F'0000) into World State A (1'0000).

    mov     ax, BIOS_SEGMENT
    mov     ds, ax
    xor     si, si

    mov     ax, STATE_A_SEGMENT
    mov     es, ax
    xor     di, di

    mov     cx, (WORLD_WIDTH * WORLD_HEIGHT) / 2

.InitLoop:
    lodsw
    and     ax, 0x0101              ; Only use the bottom list of each byte.
    stosw
    loop    .InitLoop


    ; Main loop
    ; =========
    ; cx = Segment containing world data for current step.
    ; dx = Segment containing world data for next step.
    mov     cx, STATE_A_SEGMENT
    mov     dx, STATE_B_SEGMENT

.MainLoop:
    mov     ds, cx
    mov     es, dx
    call    TickAndRender

    mov     cx, es
    mov     dx, ds

    ; Delay by waiting for the timer interrupt.
    sti
    hlt
    cli

    jmp     .MainLoop


TickAndRender:
    ; Params:
    ;   DS - World data for current step.
    ;   ES - World data for next step.
    ;   SS - VGA VRAM.
    ; Locals:
    ;   CL - World X coord.
    ;   CH - World Y coord.
    ;   DI - Cell index in next step world data.
    ;   BX, BP - Memory access.
    ;   AX, DX, SI - Scratch.

    ; This function doesn't use the stack, so use SS as a third data segment.
    mov     ax, VRAM_SEGMENT
    mov     ss, ax

    xor     cx, cx
    xor     di, di

.LoopCells:
    ; AL - Live neighbour count.
    ; AH - Current cell state.
    xor     ax, ax

    ; BL and BH are current cell X and Y.
    ; Rely on integer overflow to make world wrap at borders.
    mov     bx, cx

    ; Row above.
    dec     bh
    add     al, [bx - 1]
    add     al, [bx]
    add     al, [bx + 1]

    ; Current row.
    inc     bh
    add     al, [bx - 1]
    mov     ah, [bx]                ; Current cell.
    add     al, [bx + 1]

    ; Row below.
    inc     bh
    add     al, [bx - 1]
    add     al, [bx]
    add     al, [bx + 1]

    ; Evaluate next state.
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
    jmp     .Done
.RemainDead:
.BecomeDead:
    mov     al, 0
.Done:

    ; Write next state to ES:DI.
    stosb

    ; Choose pixel colour.
    mov     al, DEAD_COLOUR
    test    ah, ah
    jz      .Dead
    mov     al, LIVE_COLOUR
.Dead:

    ; Set pixel...

    ; Skip if Y is off-screen.
    cmp     ch, (WORLD_HEIGHT - VIDEO_HEIGHT) / 2
    jb      .NoDraw
    cmp     ch, WORLD_HEIGHT - (WORLD_HEIGHT - VIDEO_HEIGHT) / 2
    jae     .NoDraw

    ; Save AX.
    mov     bx, ax

    ; Calculate pixel offset.
    movzx   ax, ch
    add     ax, (VIDEO_HEIGHT - WORLD_HEIGHT) / 2
    mov     dx, VIDEO_WIDTH
    mul     dx
    movzx   dx, cl
    add     ax, dx
    add     ax, (VIDEO_WIDTH - WORLD_WIDTH) / 2
    mov     bp, ax

    ; Put pixel.
    mov     [ss:bp], bl
.NoDraw:

    inc     cx
    test    cx, cx
    jnz     .LoopCells

    ; Restore stack segment.
    xor     ax, ax
    mov     ss, ax

    ret


    times (512 - ($ - $$) - 2) db 0
    dw 0xaa55
