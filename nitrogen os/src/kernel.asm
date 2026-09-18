; ==========================================================
; Nitrogen OS - Kernel
; 32-bit protected mode
; NASM only
; ==========================================================

bits 32
org 0x10000

%include "graphics.inc"

start:

    ; ------------------------------------------------------
    ; Render the scene described in GRH.graphs, using the
    ; screen/clear/rect/pixel/cursor macros from graphics.inc.
    ; ------------------------------------------------------

    %include "GRH.graphs"

    ; ------------------------------------------------------
    ; Bring up a working PS/2 mouse: remap the PIC (mandatory
    ; in protected mode -- the default real-mode wiring maps
    ; IRQ0-7 onto INT 0x08-0x0F, which collides with CPU
    ; exceptions like the double fault), install a minimal
    ; IDT with a real handler for IRQ12, initialize the mouse
    ; over the 8042 controller, then idle with interrupts on
    ; so IRQ12 packets actually get serviced.
    ; ------------------------------------------------------

    call remap_pic
    call setup_idt
    call init_mouse

    sti

.idle:

    hlt
    jmp .idle


; ==========================================================
; PIC REMAP
;
; Master -> vectors 0x20-0x27, slave -> 0x28-0x2F. Only IRQ2
; (the cascade line) and IRQ12 (mouse, on the slave) are left
; unmasked.
; ==========================================================

remap_pic:

    push eax

    mov al, 0x11
    out 0x20, al
    call io_wait
    out 0xA0, al
    call io_wait

    mov al, 0x20            ; master vector offset
    out 0x21, al
    call io_wait
    mov al, 0x28            ; slave vector offset
    out 0xA1, al
    call io_wait

    mov al, 0x04            ; tell master: slave is on IRQ2
    out 0x21, al
    call io_wait
    mov al, 0x02            ; tell slave its cascade identity
    out 0xA1, al
    call io_wait

    mov al, 0x01            ; 8086 mode
    out 0x21, al
    call io_wait
    out 0xA1, al
    call io_wait

    mov al, 11111011b       ; master: unmask IRQ2 (cascade) only
    out 0x21, al
    mov al, 11101111b       ; slave: unmask IRQ12 (mouse) only
    out 0xA1, al

    pop eax
    ret

io_wait:
    out 0x80, al
    ret


; ==========================================================
; IDT SETUP
;
; Fill all 256 vectors with a harmless default handler so any
; stray interrupt doesn't crash the machine, then patch vector
; 0x2C (IRQ12, after the remap above) with the real handler.
; ==========================================================

setup_idt:

    push eax
    push ebx
    push ecx
    push edi

    mov edi, idt_start
    mov ecx, 256
    mov ebx, default_isr

.fill:
    mov ax, bx
    mov [edi], ax
    mov word [edi+2], 0x08
    mov byte [edi+4], 0
    mov byte [edi+5], 0x8E
    mov eax, ebx
    shr eax, 16
    mov [edi+6], ax
    add edi, 8
    loop .fill

    mov edi, idt_start + (0x2C * 8)
    mov ebx, mouse_isr
    mov ax, bx
    mov [edi], ax
    mov word [edi+2], 0x08
    mov byte [edi+4], 0
    mov byte [edi+5], 0x8E
    mov eax, ebx
    shr eax, 16
    mov [edi+6], ax

    lidt [idt_descriptor]

    pop edi
    pop ecx
    pop ebx
    pop eax
    ret


default_isr:
    iretd


; ==========================================================
; MOUSE INITIALIZATION (8042 / PS2 controller)
; ==========================================================

mouse_wait_write:
    push ecx
    mov ecx, 100000
.wait:
    in al, 0x64
    test al, 2
    jz .ready
    loop .wait
.ready:
    pop ecx
    ret

mouse_wait_read:
    push ecx
    mov ecx, 100000
.wait:
    in al, 0x64
    test al, 1
    jnz .ready
    loop .wait
.ready:
    pop ecx
    ret

mouse_write:                ; al = byte to send to the mouse
    push eax
    call mouse_wait_write
    mov al, 0xD4
    out 0x64, al
    call mouse_wait_write
    pop eax
    out 0x60, al
    ret

mouse_read:                 ; returns byte in al
    call mouse_wait_read
    in al, 0x60
    ret

init_mouse:

    push eax
    push ebx

    call mouse_wait_write
    mov al, 0xA8             ; enable auxiliary (mouse) device
    out 0x64, al

    call mouse_wait_write
    mov al, 0x20             ; read controller config byte
    out 0x64, al
    call mouse_read
    mov bl, al
    or bl, 0x02              ; enable IRQ12
    and bl, 0xDF             ; make sure mouse clock is enabled

    call mouse_wait_write
    mov al, 0x60
    out 0x64, al
    call mouse_wait_write
    mov al, bl
    out 0x60, al

    mov al, 0xF6             ; set defaults
    call mouse_write
    call mouse_read          ; discard ack

    mov al, 0xF4             ; enable data reporting
    call mouse_write
    call mouse_read          ; discard ack

    pop ebx
    pop eax
    ret


; ==========================================================
; MOUSE IRQ HANDLER (IRQ12 -> INT 0x2C after the remap)
;
; Standard PS/2 packets are 3 bytes: flags, dx, dy. dx/dy are
; signed 9-bit values -- an 8-bit magnitude plus a sign bit
; that lives in the flags byte, not in the magnitude byte's
; own top bit, hence the explicit sign tests below.
; ==========================================================

CURSOR_SIZE equ 4

mouse_isr:

    pushad

    in al, 0x60

    mov bl, [mouse_packet_index]
    cmp bl, 0
    jne .stage2byte

    mov [mouse_byte0], al
    mov byte [mouse_packet_index], 1
    jmp .eoi

.stage2byte:
    cmp bl, 1
    jne .stage3byte

    mov [mouse_byte1], al
    mov byte [mouse_packet_index], 2
    jmp .eoi

.stage3byte:

    mov [mouse_byte2], al
    mov byte [mouse_packet_index], 0

    call process_mouse_packet

.eoi:

    mov al, 0x20
    out 0xA0, al             ; EOI to slave PIC
    out 0x20, al             ; EOI to master PIC

    popad
    iretd


process_mouse_packet:

    pushad

    ; ---- dx ----
    movzx eax, byte [mouse_byte1]
    test byte [mouse_byte0], 0x10
    jz .xdone
    or eax, 0xFFFFFF00
.xdone:
    add [mouse_x], eax

    ; ---- dy (PS/2 "up" is positive; screen Y grows downward) ----
    movzx eax, byte [mouse_byte2]
    test byte [mouse_byte0], 0x20
    jz .ydone
    or eax, 0xFFFFFF00
.ydone:
    sub [mouse_y], eax

    ; ---- clamp to screen bounds ----
    cmp dword [mouse_x], 0
    jge .xmin_ok
    mov dword [mouse_x], 0
.xmin_ok:
    cmp dword [mouse_x], 320 - CURSOR_SIZE
    jle .xmax_ok
    mov dword [mouse_x], 320 - CURSOR_SIZE
.xmax_ok:

    cmp dword [mouse_y], 0
    jge .ymin_ok
    mov dword [mouse_y], 0
.ymin_ok:
    cmp dword [mouse_y], 200 - CURSOR_SIZE
    jle .ymax_ok
    mov dword [mouse_y], 200 - CURSOR_SIZE
.ymax_ok:

    ; ---- erase old cursor (if any), draw the new one ----
    cmp byte [have_cursor], 0
    je .skip_restore
    call restore_under_cursor
.skip_restore:

    mov eax, [mouse_x]
    mov [prev_x], eax
    mov eax, [mouse_y]
    mov [prev_y], eax

    call save_under_cursor
    call draw_cursor
    mov byte [have_cursor], 1

    popad
    ret


save_under_cursor:               ; framebuffer -> saved_pixels
    pushad
    mov eax, [prev_y]
    mov ebx, 320
    mul ebx
    add eax, [prev_x]
    add eax, 0xA0000
    mov esi, eax
    mov edi, saved_pixels

    mov ecx, CURSOR_SIZE
.row:
    push ecx
    push esi
    mov ecx, CURSOR_SIZE
    rep movsb
    pop esi
    add esi, 320
    pop ecx
    loop .row
    popad
    ret

restore_under_cursor:            ; saved_pixels -> framebuffer
    pushad
    mov eax, [prev_y]
    mov ebx, 320
    mul ebx
    add eax, [prev_x]
    add eax, 0xA0000
    mov edi, eax
    mov esi, saved_pixels

    mov ecx, CURSOR_SIZE
.row:
    push ecx
    push edi
    mov ecx, CURSOR_SIZE
    rep movsb
    pop edi
    add edi, 320
    pop ecx
    loop .row
    popad
    ret

draw_cursor:
    pushad
    mov eax, [mouse_y]
    mov ebx, 320
    mul ebx
    add eax, [mouse_x]
    add eax, 0xA0000
    mov edi, eax

    mov al, [cursor_color]
    mov edx, CURSOR_SIZE
.row:
    push edx
    mov ecx, CURSOR_SIZE
    rep stosb
    pop edx
    add edi, 320
    sub edi, CURSOR_SIZE
    dec edx
    jnz .row
    popad
    ret


; ==========================================================
; VARIABLES
; ==========================================================

cursor_color:
    db 0

mouse_packet_index:
    db 0

mouse_byte0:
    db 0

mouse_byte1:
    db 0

mouse_byte2:
    db 0

mouse_x:
    dd 160

mouse_y:
    dd 100

prev_x:
    dd 0

prev_y:
    dd 0

have_cursor:
    db 0

saved_pixels:
    times (CURSOR_SIZE * CURSOR_SIZE) db 0

idt_descriptor:
    dw (256 * 8) - 1
    dd idt_start

idt_start:
    times (256 * 8) db 0


; ==========================================================
; KERNEL = EXACTLY 20 SECTORS
;
; stage2.asm reads KERNEL_SECTORS (20) sectors starting at
; LBA 9 via INT 13h/AH=42h, regardless of how big the actual
; kernel code is. If kernel.bin is shorter than that, the
; final disk image is too short for that read and the BIOS/
; emulator reports a disk error when stage2 tries to load it.
; Padding here keeps the image exactly big enough.
; ==========================================================

times (512 * 20) - ($ - $$) db 0