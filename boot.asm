    bits 16
    org 0x7c00
    global Main


Main:
    jmp     long 0:Main.Norm
.Norm:
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0x7c00

    ; Set Video Mode
    mov     ax, 0x05
    int     0x10

    call    TickAndRender

    cli
    hlt


TickAndRender:
    xor     bh, bh
    mov     ah, 0xc

    xor     cx, cx
    jmp     .YCond

.Body:

    mov     bl, cl
    xor     bl, ch
    mov     al, 0
    and     bl, 1
    jz      short .Skip
    dec     al
.Skip:

    push    cx
    movzx   dx, ch
    movzx   cx, cl
    int     0x10
    pop     cx

    inc     cl

.XCond:
    cmp     cl, 0xff
    jb      short .Body

    xor     cl, cl
    inc     ch

.YCond:
    cmp     ch, 0x7f
    jb      short .Body
    ret


times 512 - ($ - $$) - 2 db 0
dw 0xaa55
