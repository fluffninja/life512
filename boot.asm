    bits 16
    org 0x7c00


Start:
    ; Normalise CS:IP to 0:7C00.
    jmp     0:Start.NormaliseCSIP
.NormaliseCSIP:

    ; Have stack grow downwards below the bootloader.
    xor     ax, ax
    mov     ss, ax
    mov     sp, 0x7c00


    ; Initialise world.
    ; Use the BIOS ROM bytes (at F'0000) as the intial world state.
    xor     ah, 0xf0
    mov     ds, ax
    xor     si, si

    mov     ah, 0x10
    mov     es, ax
    xor     di, di

    mov     cx, 256 * 256 / 2

.InitLoop:
    lodsw
    and     ax, 0x0101
    stosw

    loop    .InitLoop


    ; Set graphics mode to 320x200 VGA.
    mov     ax, 0x0013
    int     0x10


    ; Main loop.
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
    mov     al, 0x01
    test    ah, ah
    jz      .Dead
    mov     al, 0x0f
.Dead:

    ; Set pixel...

    ; Skip if Y is off-screen.
    cmp     ch, 28
    jb      .NoDraw
    cmp     ch, 228
    jae     .NoDraw

    ; Save AX.
    mov     si, ax

    ; Calculate pixel offset.
    movzx   ax, ch
    add     ax, (200 - 256) / 2
    mov     dx, 320
    mul     dx
    movzx   dx, cl
    add     ax, dx
    add     ax, (320 - 256) / 2
    mov     bx, ax

    ; Recall AX.
    mov     ax, si

    ; Save DS.
    mov     si, ds

    ; Put pixel.
    mov     dx, 0xa000
    mov     ds, dx
    mov     [bx], al

    ; Recall DS.
    mov     ds, si
.NoDraw:

    ; Increment X with carry.
    add     cl, 1
    jnc     .Body

    ; Increment Y with carry.
    add     ch, 1
    jnc     .Body

    ret


times 512 - ($ - $$) - 2 db 0
dw 0xaa55
