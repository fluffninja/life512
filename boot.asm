    bits 16
    org 0x7c00

    ; Key Memory Addresses:
    ;   0'0000:0'7BFF - Stack.
    ;   0'7C00:0'7DFF - This Code.
    ;   1'0000:1'FFFF - World State A.
    ;   2'0000:2'FFFF - World State B.
    ;   A'0000:A'FFFF - VGA VRAM.
    ;   F'0000:F'FFFF - BIOS ROM.

Start:
    cli

    ; Normalise CS:IP to 0:7C00.
    jmp     0:Start._NormaliseCSIP
._NormaliseCSIP:

    xor     ax, ax
    mov     ss, ax
    mov     sp, 0x7c00

    sti
    
    ; Set graphics mode to 320x200 VGA.
    mov     ax, 0x0013
    int     0x10


    ; Initialise world
    ; ================
    ; To provide some interesting initial state values, copy the raw content of
    ; the BIOS ROM (F'0000) into World State A (1'0000).

    mov     ax, 0xf000
    mov     ds, ax
    xor     si, si

    mov     ax, 0x1000
    mov     es, ax
    xor     di, di

    mov     cx, (256 * 256) / 2     ; Copy in word-sized units.

.InitLoop:
    lodsw
    and     ax, 0x0101              ; Only use the bottom list of each byte.
    stosw
    loop    .InitLoop


    ; Main loop
    ; =========
    ; cx = Segment containing world data for current step.
    ; dx = Segment containing world data for next step.
    mov     cx, 0x1000
    mov     dx, 0x2000

.MainLoop:
    mov     ds, cx
    mov     es, dx

    push    cx
    push    dx
    call    TickAndRender

    ; Pop in reverse order to swap the world data.
    pop     cx
    pop     dx

    ; Delay by waiting for the timer interrupt.
    hlt

    jmp     .MainLoop


TickAndRender:
    ; Params:
    ;   DS - World data for current step.
    ;   ES - World data for next step.
    ; Locals:
    ;   CL - World X coord.
    ;   CH - World Y coord.
    ;   DI - Cell index in next step world data.
    ;   BX - Memory access.
    ;   AX, DX, SI - Scratch.
    xor     cx, cx
    xor     di, di

.Body:
    ; AL - Live neighbour count.
    ; AH - Current cell state.
    xor     ax, ax

    ; BL and BH are current cell X and Y.
    ; Use INC and DEC to get neighbours.
    ; Rely on integer overflow to make world wrap at borders.
    mov     bx, cx

    ; Row above.
    dec     bh
    dec     bl
    add     al, [bx]
    inc     bl
    add     al, [bx]
    inc     bl
    add     al, [bx]

    ; Current row.
    inc     bh
    add     al, [bx]
    dec     bl
    mov     ah, [bx]
    dec     bl
    add     al, [bx]

    ; Row below.
    inc     bh
    add     al, [bx]
    inc     bl
    add     al, [bx]
    inc     bl
    add     al, [bx]

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
    mov     al, 0x01                ; Dead.
    test    ah, ah
    jz      .Dead
    mov     al, 0x0f                ; Live.
.Dead:

    ; Set pixel...

    ; Skip if Y is off-screen.
    cmp     ch, (256 - 200) / 2
    jb      .NoDraw
    cmp     ch, 256 - (256 - 200) / 2
    jae     .NoDraw

    ; Save AX.
    mov     bx, ax

    ; Calculate pixel offset.
    movzx   ax, ch
    add     ax, (200 - 256) / 2
    mov     dx, 320
    mul     dx
    movzx   dx, cl
    add     ax, dx
    add     ax, (320 - 256) / 2
    mov     bp, ax

    ; Save DS.
    mov     si, ds

    ; Put pixel.
    mov     dx, 0xa000
    mov     ds, dx
    mov     [ds:bp], bl

    ; Recall DS.
    mov     ds, si
.NoDraw:

    inc     cx
    test    cx, cx
    jnz     .Body

    ret


    times (512 - ($ - $$) - 2) db 0
    dw 0xaa55
