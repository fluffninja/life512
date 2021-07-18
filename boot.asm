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
    mov     cx, 256 * 128
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

    ; Current row:
    ; bl = X
    ; bh = Y
    mov     bx, cx

    dec     bl
    add     al, [bx]
    inc     bl
    mov     dl, [bx]   ; dl = Current
    inc     bl
    add     al, [bx]

    ; Previous row:
    ; bh = Y - 1
    ; bh already Y
    dec     bh
    and     bh, 0x7f

    add     al, [bx]
    dec     bl
    add     al, [bx]
    dec     bl
    add     al, [bx]

    ; Next row:
    ; bh = Y + 1
    inc     bh
    inc     bh
    and     bh, 0x7f

    add     al, [bx]
    inc     bl
    add     al, [bx]
    inc     bl
    add     al, [bx]

    test    dl, dl
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
    test    dl, dl
    mov     al, 0
    jz      .Dead
    mov     al, 0xf
.Dead:


    ; Set pixel
    push    ax
    movzx   ax, ch
    mov     dx, 320
    mul     dx
    movzx   dx, cl
    add     ax, dx
    mov     bx, ax
    pop     ax

    push    ds
    mov     dx, 0xa000
    mov     ds, dx
    mov     [bx], al
    pop     ds


    pop     cx
    inc     cl

.XCond:
    cmp     cl, 0xff
    jb      .Body

    mov     cl, cl
    inc     ch

.YCond:
    cmp     ch, 0x7f
    jb      .Body

    ret


times 512 - ($ - $$) - 2 db 0
dw 0xaa55
