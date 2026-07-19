@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

rem --- Color codes (ESC char obtained at runtime for ANSI support) ---
for /F "delims=" %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
set "RED=!ESC![31m" & set "YEL=!ESC![33m" & set "GRN=!ESC![92m" & set "CYAN=!ESC![36m" & set "RESET=!ESC![0m"

rem --- Constants ---
pushd "%~dp0" || call :die "Cannot cd to script directory"
set "SCRIPT_DIR=%CD%"
set "VENV_DIR=%SCRIPT_DIR%\venv"
set "VERSION_FILE=%SCRIPT_DIR%\scripts\util\version_check.py"
set "GFX_DETECT=%SCRIPT_DIR%\scripts\util\detect_amd_gfx.py"
set "ROCM_INDEX_URL=https://repo.amd.com/rocm/whl-multi-arch/"
set "BNB_WHEEL_URL=https://github.com/0xDELUXA/bitsandbytes_win_rocm/releases/download/0.50.0.dev0-py3-rocm7-win_amd64_all/bitsandbytes-0.50.0.dev0-cp312-cp312-win_amd64.whl"
set "MIN_PY=3.11" & set "MAX_PY=3.14"

goto :main

rem --- Helpers ---
:die
  echo.
  echo %RED%ERROR:%RESET% %~1
  echo.
  pause
  popd
  (echo %CMDCMDLINE% | find /I "%~nx0" >nul) && exit /b 1 || exit 1

:warn_store
  echo.
  echo %YEL% WARNING: Possible Windows Store Python detected %RESET%
  echo Windows Store Python has a known history of causing insidious issues with virtual environments due to how
  echo Microsoft sandboxes it.
  echo.
  echo We strongly recommend installing Python directly from %CYAN%https://www.python.org%RESET% instead.
  echo.
  echo Support for Windows Store Python is provided AS IS.
  set "ans="
  set /p "ans=Proceed anyway? (y/n): "
  if /i "!ans!"=="y" exit /b 0
  exit /b 1

:wrong_python_version_message
    echo.
    echo %RED%No suitable Python version found or selected.%RESET%
    echo Please install a supported Python version ^(%MIN_PY% - ^< %MAX_PY%^) from:
    echo %CYAN%https://www.python.org/downloads/windows/%RESET%
    echo.
    echo Reminder: Do not rely on installation videos; they are often out of date.
    exit /b 1

:run_or_die
  echo Executing: %~1
  cmd /c "%~1" || call :die "Command failed: %~2"
  exit /b 0

rem --- Main ---
:main
echo %CYAN%OneTrainer — Windows ROCm Installer%RESET%
echo.
echo %CYAN%Searching for a suitable Python installation...%RESET%
set "PYTHON="

if not exist "%VERSION_FILE%" (
    call :die """%VERSION_FILE%"" not found"
    goto :final_python_failure_handling
)

rem --- Python Detection ---
echo %CYAN%Step 1: Checking for Python in PATH (to support Conda installs)...%RESET%
where python >nul 2>&1
if not errorlevel 1 (
    for /f "delims=" %%P in ('where python') do (
        if not defined PYTHON (
            echo   Testing Python from PATH: "%%P"
            "%%P" "%VERSION_FILE%" %MIN_PY% %MAX_PY% >nul 2>&1
            if not errorlevel 1 (
                echo "%%P" | findstr /I /V /C:"%SystemRoot%\System32" >nul
                if not errorlevel 1 (
                    echo   %GRN%SELECTED Python from PATH: "%%P"%RESET%
                    set "PYTHON=%%P"
                ) else (
                    echo   %YEL%Skipping system-level Python stub: "%%P"%RESET%
                )
            ) else (
                echo   %YEL%Python from PATH during step one is not a suitable version.%RESET%
            )
        )
    )
) else (
    echo %YEL%No 'python' found in PATH. Proceeding with other checks.%RESET%
)

if defined PYTHON goto :py_ok

echo.
echo %CYAN%Step 2: Scanning Python installations reported by "py --list"...%RESET%

set "PYTHON_VERSION_FROM_PY_LIST="
for /f "tokens=2 delims=:" %%L in ('py --list 2^>nul ^| findstr /R /C:"-V:[0-9][.][0-9]"') do (
    for /f "tokens=1" %%V in ("%%L") do (
        set "CURRENT_PY_VER_TO_TEST=%%V"
        echo   Testing Python !CURRENT_PY_VER_TO_TEST! via py.exe ...
        py -!CURRENT_PY_VER_TO_TEST! "%VERSION_FILE%" %MIN_PY% %MAX_PY% >nul 2>&1
        if not errorlevel 1 (
            echo   %GRN%SELECTED Python !CURRENT_PY_VER_TO_TEST! via py.exe%RESET%
            set "PYTHON=py -!CURRENT_PY_VER_TO_TEST!"
            set "PYTHON_VERSION_FROM_PY_LIST=!CURRENT_PY_VER_TO_TEST!"
            goto :found_python_via_py_list
        ) else (
            echo   %YEL%Python !CURRENT_PY_VER_TO_TEST! via py.exe is not suitable or version_check.py failed.%RESET%
        )
    )
    if defined PYTHON_VERSION_FROM_PY_LIST goto :found_python_via_py_list
)

:found_python_via_py_list
if not defined PYTHON_VERSION_FROM_PY_LIST (
    echo %YEL%No suitable Python version found via "py --list" that satisfies %MIN_PY% ^>= v ^< %MAX_PY%.%RESET%
)

if defined PYTHON goto :py_ok

echo.
echo %CYAN%Step 3: Searching for Python in common installation directories...%RESET%
set "SEARCH_PATHS="%ProgramFiles%\Python" "%LOCALAPPDATA%\Programs\Python""
for %%D in (%SEARCH_PATHS%) do (
    if exist "%%~D" (
        for /d %%P in ("%%~D\Python*") do (
            if exist "%%P\python.exe" (
                if not defined PYTHON (
                    echo   Testing "%%P\python.exe"...
                    "%%P\python.exe" "%VERSION_FILE%" %MIN_PY% %MAX_PY% >nul 2>&1
                    if not errorlevel 1 (
                        echo   %GRN%SELECTED Python from "%%P"%RESET%
                        set "PYTHON=%%~P\python.exe"
                        goto :py_ok
                    ) else (
                        echo   %YEL%"%%P\python.exe" is not a suitable version.%RESET%
                    )
                )
            )
        )
    )
)
echo %YEL%No suitable Python found in common directories.%RESET%

if not defined PYTHON (
    echo.
    echo %CYAN%Step 4: Checking for Windows Store Python installations in PATH...%RESET%
    set "STORE_PYTHON_CHECKED="
    for /f "delims=" %%P in ('where python 2^>nul ^| findstr /i "WindowsApps"') do (
      if defined PYTHON ( goto :py_ok_check_step4 )
      set "STORE_PYTHON_CHECKED=true"
      echo Found potential Windows Store Python at "%%P".
      call :warn_store
      if errorlevel 1 (
        echo %YEL%  ^> Skipping Store Python "%%P" due to user choice or warning issue.%RESET%
      ) else (
        echo Testing agreed-upon Store Python at "%%P"...
        "%%P" "%VERSION_FILE%" %MIN_PY% %MAX_PY%
        set "LAST_ERRORLEVEL=!errorlevel!"
        if !LAST_ERRORLEVEL! == 0 (
          echo %GRN%  ^> Using selected Store Python: "%%P"%RESET%
          set "PYTHON=%%P"
          goto :py_ok_check_step4
        ) else (
          echo %RED%  ^> Version check failed for this agreed-upon Store Python "%%P" ^(Code: !LAST_ERRORLEVEL!^).%RESET%
          call :wrong_python_version_message
          echo %RED%ERROR: The selected Windows Store Python version is not supported.%RESET%
          pause
          popd
          exit /b 1
        )
      )
    )
    :py_ok_check_step4
    if defined PYTHON ( goto :py_ok )

    if not defined STORE_PYTHON_CHECKED (
        echo %YEL%No Windows Store Python installations found in PATH during step 4.%RESET%
    )
)

if not defined PYTHON (
  echo.
  call :wrong_python_version_message
  echo.
  echo %RED%ERROR: Failed to find a supported Python version after all checks.%RESET%
  echo Please ensure a Python version between %MIN_PY% and %MAX_PY% is available.
  pause
  popd
  exit /b 1
)

:final_python_failure_handling
exit /b 0

:py_ok
if not defined PYTHON (
    echo %RED%Internal error: Reached :py_ok without PYTHON being set. This should not happen.%RESET%
    call :die "Script logic error at :py_ok."
)
echo.
echo %GRN%Using Python: !PYTHON!%RESET%

rem --- Venv setup ---
echo.
echo %CYAN%Managing virtual environment...%RESET%
if not exist "%VENV_DIR%\Scripts\python.exe" (
  echo Creating venv at "%VENV_DIR%"...
  "!PYTHON!" -m venv "%VENV_DIR%" || call :die "venv creation failed using !PYTHON!"
) else (
  echo Virtual environment already exists at "%VENV_DIR%"
)
set "PYTHON_VENV=%VENV_DIR%\Scripts\python.exe"
if not exist "%PYTHON_VENV%" (
    call :die "Virtual environment Python executable not found at '%PYTHON_VENV%' after venv creation/check."
)
set "PYTHON=%PYTHON_VENV%"

echo Activating virtual environment...
call "%VENV_DIR%\Scripts\activate.bat"
echo Virtual environment activated.

rem --- Tkinter check ---
echo %CYAN%Checking for Tkinter availability...%RESET%
python -c "import tkinter,sys; sys.exit(0 if hasattr(tkinter,'TkVersion') else 1)" >nul 2>&1
if not errorlevel 1 goto :tk_ok

echo %RED%Tkinter not found%RESET%
call :die "Re-run the Python installer and enable 'tcl/tk and IDLE' (its enabled by default on fresh installations, re-enable/dont turn it off)"
goto :EOF

:tk_ok
echo %GRN%Tkinter is available, proceeding...%RESET%

rem --- AMD GPU detection ---
echo.
echo %CYAN%Detecting AMD GPU GFX architecture...%RESET%
if not exist "%GFX_DETECT%" (
    call :die "GPU detection script not found at '%GFX_DETECT%'"
)

set "GPU_LIST_FILE=%TEMP%\ot_amd_gpus.txt"
python "%GFX_DETECT%" --list > "!GPU_LIST_FILE!"
if errorlevel 1 (
    call :die "Could not detect a supported AMD GPU. See errors above."
)

rem Count how many supported GPUs were found
set "GPU_COUNT=0"
for /f "usebackq delims=" %%L in ("!GPU_LIST_FILE!") do set /a GPU_COUNT+=1

set "GFX_ARCH="
if !GPU_COUNT! == 1 (
    rem Single GPU — auto-select
    for /f "usebackq tokens=1 delims=|" %%A in ("!GPU_LIST_FILE!") do set "GFX_ARCH=%%A"
    for /f "usebackq tokens=2 delims=|" %%B in ("!GPU_LIST_FILE!") do echo %GRN%Detected GPU: %%B  [!GFX_ARCH!]%RESET%
) else (
    echo %CYAN%Multiple supported AMD GPUs detected. Select one to install for:%RESET%
    echo.
    set "IDX=0"
    for /f "usebackq tokens=1,2 delims=|" %%A in ("!GPU_LIST_FILE!") do (
        set /a IDX+=1
        echo   !IDX!^) %%B  [%%A]
    )
    echo.
    set "CHOICE="
    set /p "CHOICE=Enter number (1-!GPU_COUNT!): "
    if not defined CHOICE call :die "No GPU selected."
    for /f "delims=" %%G in ('python "%GFX_DETECT%" --pick !CHOICE! 2^>nul') do (
        if not defined GFX_ARCH set "GFX_ARCH=%%G"
    )
    if not defined GFX_ARCH (
        python "%GFX_DETECT%" --pick !CHOICE!
        call :die "Failed to resolve GPU selection !CHOICE!. See errors above."
    )
    echo %GRN%Selected GPU architecture: !GFX_ARCH!%RESET%
)
del "!GPU_LIST_FILE!" >nul 2>&1

rem --- pip upgrade ---
echo.
echo %CYAN%Upgrading pip...%RESET%
python -m pip install --upgrade pip || call :die "pip upgrade failed"

rem --- ROCm PyTorch install ---
echo.
echo %CYAN%Installing ROCm PyTorch for %GFX_ARCH% from AMD wheel index...%RESET%
echo Executing: pip install "torch[device-%GFX_ARCH%]" "torchvision[device-%GFX_ARCH%]" torchaudio --index-url %ROCM_INDEX_URL%
python -m pip install "torch[device-%GFX_ARCH%]" "torchvision[device-%GFX_ARCH%]" torchaudio --index-url %ROCM_INDEX_URL% || call :die "ROCm PyTorch install failed"

rem --- Base requirements ---
echo.
echo %CYAN%Installing base requirements from requirements-rocm-windows.txt...%RESET%
echo Executing: pip install -r requirements-rocm-windows.txt
python -m pip install -r "%SCRIPT_DIR%\requirements-rocm-windows.txt" || call :die "Base requirements install failed"

rem --- bitsandbytes (ROCm Windows, Python 3.12 only) ---
echo.
echo %CYAN%Checking Python version for ROCm bitsandbytes...%RESET%
set "PY_VER="
for /f "tokens=2 delims= " %%V in ('python --version 2^>^&1') do set "PY_VER=%%V"
set "PY_MINOR="
for /f "tokens=2 delims=." %%M in ("!PY_VER!") do set "PY_MINOR=%%M"
if "!PY_MINOR!"=="12" (
    echo %CYAN%Installing ROCm bitsandbytes wheel ^(Python 3.12^)...%RESET%
    python -m pip install "%BNB_WHEEL_URL%" || call :die "bitsandbytes ROCm install failed"
) else (
    echo %YEL%Skipping ROCm bitsandbytes: requires Python 3.12, detected !PY_VER!%RESET%
    echo %YEL%8-bit optimizers and weight quantization will not be available.%RESET%
)

rem --- Verify ROCm / HIP is accessible ---
echo.
echo %CYAN%Verifying ROCm (HIP) availability...%RESET%
python -c "import torch, sys; available = torch.cuda.is_available() or (hasattr(torch,'hip') and torch.hip.is_available()); sys.exit(0 if available else 1)" >nul 2>&1
if errorlevel 1 (
    echo %YEL%WARNING: ROCm/HIP device not detected by PyTorch at install time.%RESET%
    echo This may be normal if AMD drivers are not fully configured yet, or if running on a machine without the GPU.
    echo Re-run this check with: python -c "import torch; print(torch.cuda.is_available())"
) else (
    echo %GRN%ROCm/HIP device is accessible via PyTorch.%RESET%
)

echo.
echo %GRN%**** ROCm install successful! ****%RESET%
echo %GRN%GPU arch: %GFX_ARCH%%RESET%
echo.
pause
popd
exit /b 0
