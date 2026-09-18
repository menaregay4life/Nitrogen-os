; ==========================================================
; Nitrogen OS - Stage 2
; Loads kernel and enters 32-bit protected mode
; ==========================================================

bits 16
org 0

KERNEL_SEGMENT     equ 0x1000
KERNEL_SECTORS     equ 20
KERNEL_START_LBA   equ 9      ; CHS sector 10 (1-based) == LBA 9 (0-based)
SECTORS_PER_TRACK  equ 18     ; standard 1.44MB floppy geometry
HEADS_PER_CYLINDER equ 2

start:

    cli

    ; ------------------------------------------------------
    ; Setup segments
    ; ------------------------------------------------------

    push cs
    pop ds

    xor ax, ax
    mov ss, ax
    mov sp, 0x9000

    ; Save BIOS boot drive
    ; NOTE: this assumes stage1 still has the boot drive in DL
    ; when it jumps here. If stage1 clobbers DL (e.g. uses it as
    ; a scratch register) before the jump, this will be garbage
    ; and every read below will fail with a disk error.
    mov [boot_drive], dl

    mov si, stage2_message
    call print_string

    ; ---- DEBUG: show what drive number we actually got ----
    mov si, drive_msg
    call print_string
    mov al, [boot_drive]
    call print_hex_byte
    mov si, crlf
    call print_string
    ; ---------------------------------------------------------


; ==========================================================
; LOAD KERNEL (CHS, sector by sector)
;
; Disk:
;
; Sector 1       = boot
; Sectors 2-9    = stage2
; Sectors 10-29  = kernel
;
; NOTE: extended LBA reads (INT 13h, AH=42h) are NOT supported
; by most BIOSes for plain floppy drives -- that function is an
; EDD/hard-disk-era extension. Attempting it here returns
; AH=0x01 ("invalid command") and looks just like a disk error.
; So we convert each LBA to CHS ourselves and read one sector
; at a time with the classic AH=02h function, the same one
; boot.asm already uses successfully for stage2. Reading one
; sector at a time (rather than a whole track) sidesteps any
; assumptions about where track/head boundaries fall.
; ==========================================================

load_kernel:

    ; ------------------------------------------------------
    ; Reset disk system first
    ; ------------------------------------------------------

    mov ah, 0x00
    mov dl, [boot_drive]
    int 0x13

    jc reset_error

    mov ax, KERNEL_SEGMENT
    mov es, ax
    xor bx, bx

    mov word [current_lba], KERNEL_START_LBA
    mov word [kernel_sectors_left], KERNEL_SECTORS

.read_sector:

    ; ---- convert LBA in [current_lba] to CHS ----

    mov ax, [current_lba]
    xor dx, dx
    mov cx, SECTORS_PER_TRACK * HEADS_PER_CYLINDER
    div cx                      ; ax = cylinder, dx = 0..(SPT*HEADS-1)
    mov [tmp_cylinder], al

    mov ax, dx
    xor dx, dx
    mov cx, SECTORS_PER_TRACK
    div cx                      ; ax = head, dx = sector-1
    mov [tmp_head], al
    inc dl
    mov [tmp_sector], dl

    mov ch, [tmp_cylinder]
    mov dh, [tmp_head]
    mov cl, [tmp_sector]
    mov dl, [boot_drive]

    mov ah, 0x02
    mov al, 1
    int 0x13

    jc read_error

    add bx, 512

    inc word [current_lba]
    dec word [kernel_sectors_left]

    jnz .read_sector


; ==========================================================
; KERNEL LOADED
; ==========================================================

kernel_loaded:

    mov si, kernel_message
    call print_string


; ==========================================================
; SET VGA MODE 13h (320x200, 256 colors)
;
; Must happen here, in real mode, via BIOS INT 10h --
; the kernel runs in 32-bit protected mode and has no way
; to call BIOS anymore once we switch over.
; ==========================================================

    mov ah, 0x00
    mov al, 0x13
    int 0x10


; ==========================================================
; ENTER 32-BIT PROTECTED MODE
; ==========================================================

    cli

    ; ------------------------------------------------------
    ; Enable A20 line (fast A20 gate). Not strictly required
    ; for the addresses this loader itself touches (all under
    ; 1MB), but the kernel will need it the moment it uses
    ; memory above 1MB, and it costs nothing to do it here.
    ; ------------------------------------------------------

    in al, 0x92
    or al, 2
    out 0x92, al

    ; ------------------------------------------------------
    ; Compute the real linear address of `protected_mode`.
    ;
    ; This file is assembled with ORG 0, so `protected_mode`
    ; is only an offset relative to wherever CS actually points
    ; at runtime -- it is NOT a flat/absolute address. A plain
    ; `jmp 0x08:protected_mode` would jump to linear address
    ; (0 + offset), which is only correct if this code happens
    ; to be loaded with CS=0. Since that's not guaranteed, we
    ; compute CS*16 + offset ourselves and patch a far jump
    ; with a 32-bit offset before using it.
    ; ------------------------------------------------------

    ; ------------------------------------------------------
    ; Compute the real linear address of `gdt_start`, for the
    ; same ORG-0 reason as protected_mode above: `LGDT` needs
    ; the actual physical address of the table, not an offset
    ; relative to this file. Without this the CPU reads the
    ; GDT from the wrong place, faults on the segment reload
    ; after the jump below, and (with no protected-mode IDT
    ; set up) that escalates to a triple fault -- which looks
    ; like the whole machine silently rebooting.
    ; ------------------------------------------------------

    xor eax, eax
    mov ax, cs
    shl eax, 4
    add eax, gdt_start
    mov [gdt_base], eax

    xor eax, eax
    mov ax, cs
    shl eax, 4
    add eax, protected_mode
    mov [pm_target], eax

    lgdt [gdt_descriptor]

    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; Far jump, ptr16:32 form (0x66 operand-size override + 0xEA),
    ; offset/selector patched into pm_target above.
    db 0x66
    db 0xEA
pm_target:
    dd 0
    dw 0x08


; ==========================================================
; DISK ERRORS
; ==========================================================

reset_error:

    mov [last_error], ah
    mov si, reset_error_message
    call print_string
    mov si, err_code_msg
    call print_string
    mov al, [last_error]
    call print_hex_byte
    mov si, crlf
    call print_string
    jmp hang

read_error:

    mov [last_error], ah
    mov si, read_error_message
    call print_string
    mov si, err_code_msg
    call print_string
    mov al, [last_error]
    call print_hex_byte
    mov si, crlf
    call print_string
    jmp hang

hang:

    cli

.loop:

    hlt

    jmp .loop


; ==========================================================
; PRINT STRING
; ==========================================================

print_string:

.next:

    lodsb

    test al, al

    jz .done

    mov ah, 0x0E

    mov bh, 0

    int 0x10

    jmp .next

.done:

    ret


; ==========================================================
; PRINT HEX BYTE (AL -> two hex chars via teletype)
; ==========================================================

print_hex_byte:

    push ax
    push bx

    mov bl, al

    shr al, 4
    call .print_nibble

    mov al, bl
    and al, 0x0F
    call .print_nibble

    pop bx
    pop ax

    ret

.print_nibble:

    cmp al, 10
    jb .digit

    add al, 'A' - 10
    jmp .out

.digit:

    add al, '0'

.out:

    mov ah, 0x0E
    mov bh, 0
    int 0x10

    ret


; ==========================================================
; 32-BIT PROTECTED MODE
; ==========================================================

bits 32

protected_mode:

    mov ax, 0x10

    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    mov esp, 0x90000

    ; Kernel physical address = 0x10000
    ; (this jump target is already a flat physical address,
    ; so it's unaffected by the ORG issue fixed above)

    jmp 0x08:0x10000


; ==========================================================
; GDT
; ==========================================================

gdt_start:

    ; Null descriptor

    dq 0


    ; Code segment

    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 11001111b
    db 0x00


    ; Data segment

    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b
    db 11001111b
    db 0x00


gdt_end:


; ==========================================================
; GDT DESCRIPTOR
; ==========================================================

gdt_descriptor:

    dw gdt_end - gdt_start - 1

gdt_base:
    dd 0            ; patched at runtime, see below (was: dd gdt_start)


; ==========================================================
; VARIABLES
; ==========================================================

boot_drive:

    db 0


last_error:

    db 0


current_lba:

    dw 0


kernel_sectors_left:

    dw 0


tmp_cylinder:

    db 0


tmp_head:

    db 0


tmp_sector:

    db 0


; ==========================================================
; MESSAGES
; ==========================================================

stage2_message:

    db "Nitrogen Stage2 OK", 13, 10, 0


kernel_message:

    db "Kernel loaded!", 13, 10, 0


reset_error_message:

    db "Nitrogen OS: DISK RESET ERROR!", 13, 10, 0


read_error_message:

    db "Nitrogen OS: DISK READ ERROR!", 13, 10, 0


drive_msg:

    db "Boot drive: 0x", 0


err_code_msg:

    db "  AH error code: 0x", 0


crlf:

    db 13, 10, 0


; ==========================================================
; STAGE2 = EXACTLY 8 SECTORS
; ==========================================================

times (512 * 8) - ($ - $$) db 0