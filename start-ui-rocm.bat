@echo off

REM Avoid footgun by explicitly navigating to the directory containing the batch file
cd /d "%~dp0"

REM Verify that OneTrainer is our current working directory
if not exist "scripts\train_ui.py" (
    echo Error: train_ui.py does not exist, you have done something very wrong. Reclone the repository.
    goto :end
)

if not defined VENV_DIR (set "VENV_DIR=%~dp0venv")

:check_venv
if not exist "%VENV_DIR%\Scripts\python.exe" (
    echo Error: Virtual environment not found, please run install-rocm.bat first
    goto :end
)

rem ── Windows ROCm path setup ────────────────────────────────────────────────
rem Point HIP_PATH / ROCM_PATH to the ROCm SDK that ships inside the venv wheel
rem (_rocm_sdk_core). This ensures tools like hipinfo.exe (used by bitsandbytes
rem for GPU arch detection) and the HIP compiler are discoverable at runtime.
rem Also prepend venv\Scripts to PATH so hipInfo.exe is found by name.

set "ROCM_SDK_DIR=%VENV_DIR%\Lib\site-packages\_rocm_sdk_core"

if exist "%ROCM_SDK_DIR%" (
    rem Unconditionally override any system-level HIP_PATH / ROCM_PATH to ensure
    rem the venv-local ROCm SDK is used, not a conflicting system install.
    set "HIP_PATH=%ROCM_SDK_DIR%"
    set "ROCM_PATH=%ROCM_SDK_DIR%"
    set "PATH=%VENV_DIR%\Scripts;%ROCM_SDK_DIR%\bin;%PATH%"
) else (
    echo WARNING: _rocm_sdk_core not found in venv. ROCm tool paths not set.
    echo          Expected: %ROCM_SDK_DIR%
    echo          Re-run install-rocm.bat if this is unexpected.
)

rem ── Hand off to start-ui.bat ───────────────────────────────────────────────
rem All other launch logic (Python detection, version check, UI start) lives
rem in start-ui.bat — call it so ROCm users stay in sync with upstream changes.
call "%~dp0start-ui.bat"

:end
