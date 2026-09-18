@echo off
cls

echo ==============================
echo      NITROGEN OS BUILD
echo ==============================
echo.

set NASM=C:\Users\artit\AppData\Local\bin\NASM\nasm.exe

if not exist build mkdir build

echo [1/4] Assembling bootloader...
"%NASM%" -f bin src\boot.asm -o build\boot.bin

if errorlevel 1 (
    echo.
    echo BOOTLOADER BUILD FAILED!
    pause
    exit /b 1
)

echo Bootloader OK.
echo.

echo [2/4] Assembling stage2...
"%NASM%" -f bin src\stage2.asm -o build\stage2.bin

if errorlevel 1 (
    echo.
    echo STAGE2 BUILD FAILED!
    pause
    exit /b 1
)

echo Stage2 OK.
echo.

echo [3/4] Assembling kernel...
"%NASM%" -f bin src\kernel.asm -o build\kernel.bin -i graphics\

if errorlevel 1 (
    echo.
    echo KERNEL BUILD FAILED!
    pause
    exit /b 1
)

echo Kernel OK.
echo.

echo [4/4] Creating disk image...

del /q NitrogenOS.img 2>nul

copy /b /y "build\boot.bin"+"build\stage2.bin"+"build\kernel.bin" "NitrogenOS.img" >nul

if errorlevel 1 (
    echo.
    echo IMAGE CREATION FAILED!
    pause
    exit /b 1
)

echo.
echo ==============================
echo       BUILD SUCCESSFUL
echo ==============================
echo.

pause