#!/usr/bin/env bash
# setup-vm.sh — Install tools into a Windows VM via ISO
#
# Downloads installers (cached), builds ISO with batch script, mounts, runs, ejects.
#
# Usage: setup-vm.sh <host> <vm_name> <package>
#   package: sysinternals | pe-sieve | python-2.7 | python-3.4
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

HOST_ARG="${1:?usage: setup-vm.sh <host> <vm_name> <package>}"
VM_NAME="${2:?}"
PACKAGE="${3:?}"

setup_host "$HOST_ARG"

STAGING="/tmp/setup-vm-staging-$$"
ISO_PATH="/tmp/setup-vm-$$.iso"

# Get VM IP
vmip=$("$SCRIPT_DIR/vm-ip.sh" "$HOST" "$VM_NAME")

cleanup() {
    ssh "$HOST" "rm -rf '$STAGING'" 2>/dev/null || true
    # Only remove ISO on success; on failure the VM may reference it
    if [ "${SETUP_OK:-}" = "1" ]; then
        ssh "$HOST" "rm -f '$ISO_PATH'" 2>/dev/null || true
    else
        echo "Note: ISO kept at $ISO_PATH (referenced by VM config)" >&2
    fi
}
trap cleanup EXIT

case "$PACKAGE" in

sysinternals)
    echo "=== Installing Sysinternals Suite ==="

    SYSINTERNALS_URL="https://github.com/Alex313031/Windows-XP-Stuffz/raw/main/SysinternalsSuite.zip"
    CACHE_FILE="${TOOLS_CACHE}/SysinternalsSuite.zip"

    # Download if not cached
    echo "Downloading SysinternalsSuite.zip (if needed)..."
    ssh "$HOST" "mkdir -p '$TOOLS_CACHE'"
    ssh "$HOST" "[ -f '$CACHE_FILE' ] || wget -q '$SYSINTERNALS_URL' -O '$CACHE_FILE'"
    ssh "$HOST" "ls -lh '$CACHE_FILE'"

    # Build ISO
    echo "Building ISO..."
    ssh "$HOST" bash -s "$CACHE_FILE" "$STAGING" "$ISO_PATH" << 'REMOTE'
    cache="$1"; staging="$2"; iso="$3"
    set -euo pipefail
    rm -rf "$staging"
    mkdir -p "$staging"
    cp "$cache" "$staging/"

    cat > "$staging/install.bat" << 'BATEOF'
@echo off
echo === Installing Sysinternals Suite ===
echo.

set SRC=D:
set DST=C:\local

if not exist %DST% mkdir %DST%
if not exist %DST%\Sysinternals mkdir %DST%\Sysinternals

echo [1/3] Extracting SysinternalsSuite.zip...
if not exist %DST%\7-Zip\7z.exe (
    echo ERROR: 7-Zip not found at %DST%\7-Zip\7z.exe
    echo Install 7-Zip first, or extract manually.
    goto :eula
)
"%DST%\7-Zip\7z.exe" x %SRC%\SysinternalsSuite.zip -o%DST%\Sysinternals -y >nul 2>&1
if errorlevel 1 (
    echo ERROR: Extraction failed
    goto :eof
)
echo   Extracted to %DST%\Sysinternals\

:eula
echo [2/3] Accepting Sysinternals EULAs...
reg add "HKCU\Software\Sysinternals" /f >nul 2>&1
for %%t in (
    "Process Monitor" "Process Explorer" "Autoruns" "PsExec"
    "Sigcheck" "Strings" "Handle" "ListDLLs" "TCPView"
    "ProcDump" "AccessChk" "PsInfo" "PsKill" "PsList"
    "PsLoggedOn" "PsLogList" "PsService" "Whois"
) do (
    reg add "HKCU\Software\Sysinternals\%%~t" /v EulaAccepted /t REG_DWORD /d 1 /f >nul 2>&1
)
echo   EULAs accepted

echo [3/3] Adding to PATH...
echo %PATH% | findstr /i "Sysinternals" >nul 2>&1
if errorlevel 1 (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path /t REG_EXPAND_SZ /d "C:\WINDOWS\system32;C:\WINDOWS;C:\WINDOWS\System32\Wbem;%DST%\Sysinternals" /f >nul
    echo   Set system PATH (reboot for effect)
) else (
    echo   Sysinternals already in PATH
)

echo.
echo === Done ===
echo Reboot recommended for PATH changes.
BATEOF

    genisoimage -quiet -r -J -V "SYSINTERNALS" -o "$iso" "$staging/"
    rm -rf "$staging"
REMOTE

    # Mount ISO, run installer, eject
    echo "Attaching ISO..."
    "$SCRIPT_DIR/vm.sh" "$HOST_ARG" cdrom "$VM_NAME" "$ISO_PATH"

    echo "Running installer (waiting 5s for CD mount)..."
    sleep 5
    "$SCRIPT_DIR/vm-exec.exp" "$HOST" "$vmip" "$VM_USER" "$VM_PASS" "D:\\install.bat" 120

    echo "Ejecting ISO..."
    "$SCRIPT_DIR/vm.sh" "$HOST_ARG" cdrom "$VM_NAME" eject
    SETUP_OK=1

    echo ""
    echo "Sysinternals installed. Reboot the VM for PATH changes."
    echo "Verify: just exec $VM_NAME 'PsExec.exe -accepteula'"
    ;;

python-2.7|python-3.4)
    # Extract version from package name
    PYVER="${PACKAGE#python-}"
    case "$PYVER" in
        2.7) MSI="python-2.7.18.msi"; URL="https://www.python.org/ftp/python/2.7.18/python-2.7.18.msi" ;;
        3.4) MSI="python-3.4.4.msi"; URL="https://www.python.org/ftp/python/3.4.4/python-3.4.4.msi" ;;
        *)   echo "Unsupported Python version: $PYVER"; exit 1 ;;
    esac

    echo "=== Installing Python $PYVER ==="

    CACHE_FILE="${TOOLS_CACHE}/${MSI}"

    # Download if not cached
    echo "Downloading $MSI (if needed)..."
    ssh "$HOST" "mkdir -p '$TOOLS_CACHE'"
    ssh "$HOST" "[ -f '$CACHE_FILE' ] || wget -q '$URL' -O '$CACHE_FILE'"
    ssh "$HOST" "ls -lh '$CACHE_FILE'"

    # Build ISO
    echo "Building ISO..."
    ssh "$HOST" bash -s "$CACHE_FILE" "$MSI" "$PYVER" "$STAGING" "$ISO_PATH" << 'REMOTE'
    cache="$1"; msi="$2"; pyver="$3"; staging="$4"; iso="$5"
    set -euo pipefail
    rm -rf "$staging"
    mkdir -p "$staging"
    cp "$cache" "$staging/"

    cat > "$staging/install.bat" << BATEOF
@echo off
echo === Installing Python $pyver ===
echo.
set DST=C:\local\python-$pyver
msiexec /i D:\\$msi /qn TARGETDIR=%DST% ALLUSERS=1
if exist %DST%\python.exe (
    echo OK: %DST%\python.exe
) else (
    echo ERROR: Installation failed
)
BATEOF

    genisoimage -quiet -r -J -V "PYTHON" -o "$iso" "$staging/"
    rm -rf "$staging"
REMOTE

    # Mount ISO, run installer, eject
    echo "Attaching ISO..."
    "$SCRIPT_DIR/vm.sh" "$HOST_ARG" cdrom "$VM_NAME" "$ISO_PATH"

    echo "Running installer (waiting 5s for CD mount)..."
    sleep 5
    "$SCRIPT_DIR/vm-exec.exp" "$HOST" "$vmip" "$VM_USER" "$VM_PASS" "D:\\install.bat" 120

    echo "Ejecting ISO..."
    "$SCRIPT_DIR/vm.sh" "$HOST_ARG" cdrom "$VM_NAME" eject
    SETUP_OK=1

    echo ""
    echo "Python $PYVER installed to C:\\local\\python-${PYVER}"
    echo "Verify: just exec $VM_NAME 'C:\\local\\python-${PYVER}\\python.exe -V'"
    ;;

pe-sieve)
    echo "=== Installing pe-sieve + mal_unpack ==="

    PESIEVE_URL="https://github.com/hasherezade/pe-sieve/releases/download/v0.4.1.1/pe-sieve32.zip"
    MALUNPACK_URL="https://github.com/hasherezade/mal_unpack/releases/download/1.0/mal_unpack32.zip"
    PESIEVE_CACHE="${TOOLS_CACHE}/pe-sieve32.zip"
    MALUNPACK_CACHE="${TOOLS_CACHE}/mal_unpack32.zip"

    # Download if not cached
    echo "Downloading pe-sieve32.zip + mal_unpack32.zip (if needed)..."
    ssh "$HOST" "mkdir -p '$TOOLS_CACHE'"
    ssh "$HOST" "[ -f '$PESIEVE_CACHE' ] || wget -q '$PESIEVE_URL' -O '$PESIEVE_CACHE'"
    ssh "$HOST" "[ -f '$MALUNPACK_CACHE' ] || wget -q '$MALUNPACK_URL' -O '$MALUNPACK_CACHE'"
    ssh "$HOST" "ls -lh '$PESIEVE_CACHE' '$MALUNPACK_CACHE'"

    # Build ISO
    echo "Building ISO..."
    ssh "$HOST" bash -s "$PESIEVE_CACHE" "$MALUNPACK_CACHE" "$STAGING" "$ISO_PATH" << 'REMOTE'
    pesieve="$1"; malunpack="$2"; staging="$3"; iso="$4"
    set -euo pipefail
    rm -rf "$staging"
    mkdir -p "$staging"
    cp "$pesieve" "$staging/"
    cp "$malunpack" "$staging/"

    cat > "$staging/install.bat" << 'BATEOF'
@echo off
echo === Installing pe-sieve + mal_unpack ===
echo.

set SRC=D:
set DST=C:\local

if not exist %DST% mkdir %DST%
if not exist %DST%\pe-sieve mkdir %DST%\pe-sieve

echo [1/2] Extracting pe-sieve32.zip...
if not exist %DST%\7-Zip\7z.exe (
    echo ERROR: 7-Zip not found at %DST%\7-Zip\7z.exe
    echo Install 7-Zip first: just setup-tools
    goto :eof
)
"%DST%\7-Zip\7z.exe" x %SRC%\pe-sieve32.zip -o%DST%\pe-sieve -y >nul 2>&1
if errorlevel 1 (
    echo ERROR: pe-sieve extraction failed
    goto :eof
)
echo   Extracted to %DST%\pe-sieve\

echo [2/2] Extracting mal_unpack32.zip...
"%DST%\7-Zip\7z.exe" x %SRC%\mal_unpack32.zip -o%DST%\pe-sieve -y >nul 2>&1
if errorlevel 1 (
    echo ERROR: mal_unpack extraction failed
    goto :eof
)
echo   Extracted to %DST%\pe-sieve\

echo.
echo === Done ===
echo.
echo Usage:
echo   pe-sieve32.exe /pid ^<PID^> /imp A    Dump process with IAT reconstruction
echo   mal_unpack32.exe /exe ^<file^> /imp A  Auto-unpack and reconstruct imports
echo.
echo Tools installed to %DST%\pe-sieve\
BATEOF

    genisoimage -quiet -r -J -V "PE-SIEVE" -o "$iso" "$staging/"
    rm -rf "$staging"
REMOTE

    # Mount ISO, run installer, eject
    echo "Attaching ISO..."
    "$SCRIPT_DIR/vm.sh" "$HOST_ARG" cdrom "$VM_NAME" "$ISO_PATH"

    echo "Running installer (waiting 5s for CD mount)..."
    sleep 5
    "$SCRIPT_DIR/vm-exec.exp" "$HOST" "$vmip" "$VM_USER" "$VM_PASS" "D:\\install.bat" 120

    echo "Ejecting ISO..."
    "$SCRIPT_DIR/vm.sh" "$HOST_ARG" cdrom "$VM_NAME" eject
    SETUP_OK=1

    echo ""
    echo "pe-sieve + mal_unpack installed to C:\\local\\pe-sieve\\"
    echo "Verify: just exec $VM_NAME 'C:\\local\\pe-sieve\\pe-sieve32.exe /help'"
    ;;

*)
    echo "Unknown package: $PACKAGE"
    echo ""
    echo "Available packages:"
    echo "  sysinternals   Sysinternals Suite (PsExec, ProcMon, Autoruns, etc.)"
    echo "  pe-sieve       pe-sieve + mal_unpack (IAT reconstruction, auto-unpacking)"
    echo "  python-2.7     Python 2.7.18 (last XP-compatible 2.x)"
    echo "  python-3.4     Python 3.4.4 (last XP-compatible 3.x)"
    exit 1
    ;;
esac
