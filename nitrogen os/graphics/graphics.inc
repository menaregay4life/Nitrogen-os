; ==========================================================
; Nitrogen OS 32-bit Graphics
; ==========================================================


; ==========================================================
; VGA COLORS
; ==========================================================

%define black           0
%define blue            1
%define green           2
%define cyan            3
%define red             4
%define magenta         5
%define brown           6
%define lightgray       7
%define gray            8
%define lightblue       9
%define lightgreen      10
%define lightcyan       11
%define lightred        12
%define lightmagenta    13
%define yellow          14
%define white           15


; ==========================================================
; SCREEN
; ==========================================================

%macro screen 2

    %define SCREEN_WIDTH %1
    %define SCREEN_HEIGHT %2

%endmacro


; ==========================================================
; CLEAR
;
; clear black
; clear red
; clear white
; ==========================================================

%macro clear 1

    push eax
    push ecx
    push edi

    mov edi, 0xA0000

    mov al, %1

    mov ecx, 64000

    rep stosb

    pop edi
    pop ecx
    pop eax

%endmacro


; ==========================================================
; PIXEL
;
; pixel X, Y, COLOR
; ==========================================================

%macro pixel 3

    push eax
    push ebx
    push edi

    ; Y * 320
    mov eax, %2

    mov ebx, 320

    mul ebx

    ; + X
    add eax, %1

    mov edi, eax

    ; Color
    mov al, %3

    mov [0xA0000 + edi], al

    pop edi
    pop ebx
    pop eax

%endmacro


; ==========================================================
; RECTANGLE
;
; rect X, Y, WIDTH, HEIGHT, COLOR
; ==========================================================

%macro rect 5

    push eax
    push ebx
    push ecx
    push edx
    push edi

    ; ------------------------------------------
    ; Calculate start
    ; ------------------------------------------

    mov eax, %2

    mov ebx, 320

    mul ebx

    add eax, %1

    add eax, 0xA0000

    mov edi, eax


    ; ------------------------------------------
    ; Height
    ; ------------------------------------------

    mov edx, %4


%%row:

    push edx


    ; Width
    mov ecx, %3

    ; Color
    mov al, %5

    ; Draw row
    rep stosb


    pop edx


    ; Move to next row
    add edi, 320

    ; Undo width
    sub edi, %3


    dec edx

    jnz %%row


    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax

%endmacro


; ==========================================================
; CURSOR
;
; cursor white
; cursor green
; cursor cyan
; cursor yellow
; ==========================================================

%macro cursor 1

    mov byte [cursor_color], %1

%endmacro