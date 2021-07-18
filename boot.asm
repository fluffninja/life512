    bits 16
    org 0x7c00
    global Main


Main:
    jmp     0:Main.Norm
.Norm:
    xor     ax, ax
    mov     ss, ax
    mov     sp, 0x7c00

    ; Set Video Mode
    mov     al, 0x13
    int     0x10


    ; Initialise board.
    mov     ax, 0x1000
    mov     es, ax

    xor     di, di
    mov     cx, 256 * 256
.Body:
    mov     ax, cx
    shr     ax, 1
    and     ax, 1
    stosb
    loop    .Body


MainLoop:
    mov     cx, 0x1000
    mov     dx, 0x2000
.Body:
    mov     ds, cx
    mov     es, dx
    push    cx
    push    dx
    call    TickAndRender
    pop     dx
    pop     cx
    xchg    cx, dx
    jmp     .Body


TickAndRender:
    ; cl = X
    ; ch = Y
    xor     cx, cx
    xor     bp, bp
    jmp     .YCond

.Body:
    push    cx

    ; al = neighbour count
    xor     ax, ax

    mov     bx, cx

    ; Previous row:
    ; bh = Y - 1
    dec     bh

    dec     bl
    add     al, [bx]

    inc     bl
    add     al, [bx]

    inc     bl
    add     al, [bx]

    ; Current row:
    ; bh = Y
    inc     bh

    add     al, [bx]

    dec     bl
    mov     ah, [bx]   ; ah = Current

    dec     bl
    add     al, [bx]

    ; Next row:
    ; bh = Y + 1
    inc     bh

    add     al, [bx]

    inc     bl
    add     al, [bx]

    inc     bl
    add     al, [bx]

    ; Calculate next state.
    test    ah, ah
    jz      .CurrentlyDead


.CurrentlyAlive:
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
    jmp     .After


.RemainDead:
.BecomeDead:
    mov     al, 0


.After:


    ; Set next state.
    mov     [es:bp], al
    inc     bp

    ; Set pixel colour.
    mov     al, 0
    test    ah, ah
    jz      .Dead
    mov     al, 0xf
.Dead:

    cmp     ch, 28
    jb      .Skip

    cmp     ch, 228
    jae     .Skip


    ; Set pixel
    push    ax

    movzx   ax, ch
    add     ax, (200 - 256) / 2

    mov     dx, 320
    mul     dx

    movzx   dx, cl
    add     ax, dx
    add     ax, (320 - 256) / 2
    mov     bx, ax

    pop     ax

    push    ds
    mov     dx, 0xa000
    mov     ds, dx
    mov     [bx], al
    pop     ds
.Skip:


    pop     cx
    inc     cl

.XCond:
    cmp     cl, 0xff
    jb      .Body

    mov     cl, cl
    inc     ch

.YCond:
    cmp     ch, 0xff
    jb      .Body

    ret


times 512 - ($ - $$) - 2 db 0
dw 0xaa55
