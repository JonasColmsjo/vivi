#!/usr/bin/env bash
# build-tools-iso.sh — Build an ISO with tools for Windows XP VM setup
#
# Usage: build-tools-iso.sh <host> <output_iso> [tools_source]
#
# Assembles tools from a directory on the host (default: $TOOLS_SOURCE from config),
# adds a setup.bat installer script, and creates an ISO image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

HOST_ARG="${1:?usage: build-tools-iso.sh <host> <output_iso> [tools_source]}"
ISO_PATH="${2:?}"
TOOLS_SRC="${3:-${TOOLS_SOURCE:-/mnt/ext/Installation_files/Windows-XP-Stuffz}}"

setup_host "$HOST_ARG"

STAGING="/tmp/tools-iso-staging-$$"

echo "Building tools ISO on $HOST..."

ssh "$HOST" bash -s "$TOOLS_SRC" "$STAGING" "$ISO_PATH" << 'REMOTE_SCRIPT'
STUFFZ="$1"
STAGING="$2"
ISO_PATH="$3"

set -euo pipefail

rm -rf "$STAGING"
mkdir -p "$STAGING"

echo "Copying tools to staging..."

# Sysinternals Suite (PsExec, autorunsc, sigcheck, strings, etc.)
cp "$STUFFZ/SysinternalsSuite.zip" "$STAGING/"

# 7-Zip installer (in case not already installed)
cp "$STUFFZ/PROGS/7z1900.exe" "$STAGING/"

# Notepad++ (x32 for XP)
cp "$STUFFZ/PROGS/NotepadPlusPlus7.9.2_Installer_x32.exe" "$STAGING/"

# VC++ runtimes (needed by many tools)
cp "$STUFFZ/MSVC/VC_2005_x86.exe" "$STAGING/"
cp "$STUFFZ/MSVC/VC_2008_x86.exe" "$STAGING/"

# Resource Hacker
cp "$STUFFZ/PROGS/reshacker_4.7.34_setup.exe" "$STAGING/"

# Registry tweaks
mkdir -p "$STAGING/reg"
cp "$STUFFZ/reg/"*.reg "$STAGING/reg/" 2>/dev/null || true

# WannaCry patch (useful for lab VMs)
cp "$STUFFZ/WANNACRY_PATCH.exe" "$STAGING/"

# Resource Kit Tools
cp "$STUFFZ/rktools.exe" "$STAGING/"

# Create setup.bat — the installer script that runs inside the VM
cat > "$STAGING/setup.bat" << 'BATEOF'
@echo off
echo === XP VM Tools Setup ===
echo.

set SRC=D:
set DST=C:\local

:: Create directories
if not exist %DST% mkdir %DST%
if not exist %DST%\Sysinternals mkdir %DST%\Sysinternals
if not exist %DST%\reg mkdir %DST%\reg

:: Extract Sysinternals Suite
echo [1/6] Extracting Sysinternals Suite...
if exist %SRC%\SysinternalsSuite.zip (
    "%DST%\7-Zip\7z.exe" x %SRC%\SysinternalsSuite.zip -o%TEMP%\sysinternals-tmp -y >nul 2>&1
    if errorlevel 1 (
        echo   ERROR: 7-Zip not found or extraction failed.
        echo   Install 7-Zip first: %SRC%\7z1900.exe
    ) else (
        :: The zip contains a SysinternalsSuite\ subdirectory — move it up
        if exist %TEMP%\sysinternals-tmp\SysinternalsSuite (
            move %TEMP%\sysinternals-tmp\SysinternalsSuite %DST%\Sysinternals >nul
        ) else (
            ren %TEMP%\sysinternals-tmp Sysinternals
            move %TEMP%\Sysinternals %DST%\Sysinternals >nul
        )
        rd /s /q %TEMP%\sysinternals-tmp >nul 2>&1
        echo   Extracted to %DST%\Sysinternals\
    )
)

:: Add Sysinternals to PATH
echo [2/6] Adding Sysinternals to PATH...
echo %PATH% | findstr /i "Sysinternals" >nul 2>&1
if errorlevel 1 (
    :: Use literal paths — %%SystemRoot%% escaping breaks in batch heredocs
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path /t REG_EXPAND_SZ /d "C:\WINDOWS\system32;C:\WINDOWS;C:\WINDOWS\System32\Wbem;%DST%\Sysinternals" /f >nul
    echo   Set system PATH with %DST%\Sysinternals
    echo   NOTE: Reboot or re-login for PATH to take effect
) else (
    echo   Sysinternals already in PATH
)

:: Accept Sysinternals EULAs (critical — GUI tools hang on EULA dialog)
echo [3/6] Accepting Sysinternals EULAs...
reg add "HKCU\Software\Sysinternals" /f >nul 2>&1
for %%t in (
    "Process Monitor" "Process Explorer" "Autoruns" "PsExec"
    "Sigcheck" "Strings" "Handle" "ListDLLs" "TCPView"
    "ProcDump" "AccessChk" "PsInfo" "PsKill" "PsList"
    "PsLoggedOn" "PsLogList" "PsService" "Whois"
) do (
    reg add "HKCU\Software\Sysinternals\%%~t" /v EulaAccepted /t REG_DWORD /d 1 /f >nul 2>&1
)
echo   EULAs accepted for all Sysinternals tools

:: Copy VC++ runtimes
echo [4/6] Copying VC++ runtimes...
if exist %SRC%\VC_2005_x86.exe copy %SRC%\VC_2005_x86.exe %DST%\ >nul
if exist %SRC%\VC_2008_x86.exe copy %SRC%\VC_2008_x86.exe %DST%\ >nul
echo   Copied to %DST%\ (run manually if needed)

:: Copy registry tweaks
echo [5/6] Copying registry tweaks...
if exist %SRC%\reg\*.reg copy %SRC%\reg\*.reg %DST%\reg\ >nul
echo   Copied to %DST%\reg\

:: Copy remaining tools
echo [6/6] Copying additional tools...
if exist %SRC%\WANNACRY_PATCH.exe copy %SRC%\WANNACRY_PATCH.exe %DST%\ >nul
if exist %SRC%\rktools.exe copy %SRC%\rktools.exe %DST%\ >nul
if exist %SRC%\reshacker_4.7.34_setup.exe copy %SRC%\reshacker_4.7.34_setup.exe %DST%\ >nul
echo   Done

:: Create helper batch files
echo.
echo Creating helper scripts in C:\...

:: FTP upload helper
(
echo @echo off
echo if "%%1"=="" ^(echo Usage: upload.bat ^<file^>^& exit /b 1^)
echo ^(echo open 192.168.100.1^&echo user anonymous x^&echo binary^&echo put %%1^&echo quit^)^> C:\ftp-cmd.txt
echo ftp -n -s:C:\ftp-cmd.txt
echo del C:\ftp-cmd.txt
) > C:\upload.bat

echo   Created C:\upload.bat

echo.
echo === Setup complete! ===
echo Reboot recommended for PATH changes to take effect.
BATEOF

# Create the ISO
echo "Creating ISO image..."
genisoimage -quiet -r -J -V "XP_TOOLS" -o "$ISO_PATH" "$STAGING/"

echo "ISO created: $ISO_PATH ($(du -h "$ISO_PATH" | cut -f1))"

# Cleanup staging
rm -rf "$STAGING"
REMOTE_SCRIPT
