bits 16
org 0x7C00

STAGE2_SEGMENT equ 0x0800
STAGE2_SECTORS equ 8

start:
    cli

    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov [boot_drive], dl

    ; Load stage2 to 0000:8000
    mov ax, STAGE2_SEGMENT
    mov es, ax
    xor bx, bx

    mov byte [current_sector], 2
    mov byte [sectors_left], STAGE2_SECTORS

load_stage2:

    xor ah, ah
    mov dl, [boot_drive]
    int 0x13

    mov ah, 0x02
    mov al, 1

    mov ch, 0
    mov cl, [current_sector]

    mov dh, 0
    mov dl, [boot_drive]

    int 0x13
    jc disk_error

    add bx, 512

    inc byte [current_sector]
    dec byte [sectors_left]

    jnz load_stage2

    ; Restore boot drive
    mov dl, [boot_drive]

    ; Jump to stage2
    jmp STAGE2_SEGMENT:0x0000


disk_error:

    mov si, error_message

.print:
    lodsb
    test al, al
    jz .hang

    mov ah, 0x0E
    mov bh, 0
    int 0x10

    jmp .print

.hang:
    cli
    hlt
    jmp .hang


boot_drive:
    db 0

current_sector:
    db 2

sectors_left:
    db STAGE2_SECTORS

error_message:
    db "Nitrogen OS: Stage2 disk error!", 13, 10, 0


times 510 - ($ - $$) db 0

dw 0xAA55