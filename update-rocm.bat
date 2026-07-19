@echo off
setlocal EnableDelayedExpansion

rem --- Color codes (ESC char obtained at runtime for ANSI support) ---
for /F "delims=" %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
set "RED=!ESC![31m" & set "YEL=!ESC![33m" & set "GRN=!ESC![92m" & set "CYAN=!ESC![36m" & set "RESET=!ESC![0m"

REM Avoid footgun by explicitly navigating to the directory containing the batch file
cd /d "%~dp0"
set "SCRIPT_DIR=%CD%"
set "GFX_DETECT=%SCRIPT_DIR%\scripts\util\detect_amd_gfx.py"
set "ROCM_INDEX_URL=https://repo.amd.com/rocm/whl-multi-arch/"

REM Verify that OneTrainer is our current working directory
if not exist "scripts\train_ui.py" (
    echo Error: train_ui.py does not exist, you have done something very wrong. Reclone the repository.
    goto :end_error
)

if not defined GIT    ( set "GIT=git" )
if not defined PYTHON ( set "PYTHON=python" )
if not defined VENV_DIR ( set "VENV_DIR=%~dp0venv" )

echo %CYAN%OneTrainer — Windows ROCm Updater%RESET%
echo.

:git_pull
echo Checking repository and branch information...

FOR /F "tokens=* USEBACKQ" %%F IN (`"%GIT%" rev-parse --abbrev-ref HEAD`) DO (
    set "current_branch=%%F"
)
echo Current branch: !current_branch!

rem --- Prefer 'upstream' remote (fork workflow) if it exists ---
set "UPSTREAM_URL="
FOR /F "tokens=* USEBACKQ" %%F IN (`"%GIT%" remote get-url upstream 2^>NUL`) DO set "UPSTREAM_URL=%%F"
if defined UPSTREAM_URL (
    echo %CYAN%Upstream remote found: !UPSTREAM_URL!%RESET%
    echo Fetching from upstream...
    "%GIT%" fetch upstream
    if errorlevel 1 (
        echo Error: Could not fetch from upstream
        goto :end_error
    )
    FOR /F "tokens=* USEBACKQ" %%F IN (`"%GIT%" rev-parse HEAD`) DO set "local_commit=%%F"
    FOR /F "tokens=* USEBACKQ" %%F IN (`"%GIT%" rev-parse upstream/master`) DO set "remote_commit=%%F"
    echo Local commit:    !local_commit:~0,8!...
    echo Upstream commit: !remote_commit:~0,8!...
    if "!local_commit!"=="!remote_commit!" (
        echo Repository is already up to date with upstream.
    ) else (
        echo Merging upstream/master...
        "%GIT%" merge upstream/master
        if errorlevel 1 (
            echo Error: Merge from upstream/master failed.
            goto :end_error
        )
    )
    goto :check_venv
)

set "tracking_info="
FOR /F "tokens=* USEBACKQ" %%F IN (`"%GIT%" rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2^>NUL`) DO (
    set "tracking_info=%%F"
)

if not defined tracking_info (
    echo INFO: Current branch has no tracking remote configured.
    echo      This is normal for local-only branches.
    echo      Updates cannot be pulled automatically. Configure tracking with:
    echo      git branch --set-upstream-to=origin/master %current_branch%
) else (
    for /F "tokens=1,2 delims=/" %%a in ("!tracking_info!") do (
        set "tracking_remote=%%a"
        set "tracking_branch=%%b"
    )
    echo Tracking: !tracking_info!

    FOR /F "tokens=* USEBACKQ" %%F IN (`"!GIT!" config --get remote.!tracking_remote!.url 2^>NUL`) DO (
        set "remote_url=%%F"
    )
    echo Remote !tracking_remote!: !remote_url!

    set "is_official_repo="
    echo !remote_url! | findstr /i "Nerogar/OneTrainer" >nul && set "is_official_repo=1"

    set "is_master_branch="
    if /I "!tracking_branch!"=="master" (set "is_master_branch=1")

    if not defined is_official_repo (set "non_standard_setup=1")
    if not defined is_master_branch (set "non_standard_setup=1")

    if defined non_standard_setup (
        echo INFO: Non-standard repository setup detected:
        if not defined is_official_repo echo        - Using non-official repository: !remote_url!
        if not defined is_master_branch echo        - On branch !tracking_branch! instead of master
        echo      This is normal if you're using a fork or working on a specific branch.
    )

    FOR /F "tokens=* USEBACKQ" %%F IN (`"%GIT%" rev-parse HEAD`) DO (
        set "local_commit=%%F"
    )
    echo Local commit: !local_commit:~0,8!...

    echo Fetching updates...
    "%GIT%" fetch !tracking_remote!
    if errorlevel 1 (
        echo Error: Could not fetch updates
        goto :end_error
    )

    FOR /F "tokens=* USEBACKQ" %%F IN (`"%GIT%" rev-parse !tracking_remote!/!tracking_branch!`) DO (
        set "remote_commit=%%F"
    )
    echo Remote commit: !remote_commit:~0,8!...

    if "!local_commit!"=="!remote_commit!" (
        echo Repository is already up to date, skipping pull.
    ) else (
        echo Updates available, pulling changes...
        "%GIT%" pull
        if errorlevel 1 (
            echo Error: Git pull failed.
            goto :end_error
        )
    )
)

goto :check_venv

:check_venv
if not exist "%VENV_DIR%\Scripts\python.exe" (
    echo Error: Virtual environment not found, please run install-rocm.bat first
    goto :end_error
)

:activate_venv
echo Activating virtual environment: %VENV_DIR%
set "PYTHON=%VENV_DIR%\Scripts\python.exe"
call "%VENV_DIR%\Scripts\activate.bat"

:check_python_version
echo Checking Python version...
"%PYTHON%" --version
if errorlevel 1 (
    echo Error: Failed to get Python version
    goto :end_error
)
echo.
"%PYTHON%" "%~dp0scripts\util\version_check.py" 3.10 3.14 2>&1
if errorlevel 1 goto :wrong_python_version

goto :detect_gpu

:detect_gpu
echo.
echo %CYAN%Detecting AMD GPU GFX architecture...%RESET%

if not exist "%GFX_DETECT%" (
    echo %RED%ERROR: GPU detection script not found at "%GFX_DETECT%"%RESET%
    goto :end_error
)

set "GPU_LIST_FILE=%TEMP%\ot_amd_gpus.txt"
"%PYTHON%" "%GFX_DETECT%" --list > "!GPU_LIST_FILE!"
if errorlevel 1 (
    echo %RED%Error: Could not detect a supported AMD GPU. See errors above.%RESET%
    goto :end_error
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
    echo %CYAN%Multiple supported AMD GPUs detected. Select one to update for:%RESET%
    echo.
    set "IDX=0"
    for /f "usebackq tokens=1,2 delims=|" %%A in ("!GPU_LIST_FILE!") do (
        set /a IDX+=1
        echo   !IDX!^) %%B  [%%A]
    )
    echo.
    set "CHOICE="
    set /p "CHOICE=Enter number (1-!GPU_COUNT!): "
    if not defined CHOICE (
        echo %RED%Error: No GPU selected.%RESET%
        goto :end_error
    )
    set "GFX_ARCH="
    for /f "delims=" %%G in ('"%PYTHON%" "%GFX_DETECT%" --pick !CHOICE! 2^>nul') do (
        if not defined GFX_ARCH set "GFX_ARCH=%%G"
    )
    if not defined GFX_ARCH (
        "%PYTHON%" "%GFX_DETECT%" --pick !CHOICE!
        echo %RED%Error: Failed to resolve GPU selection !CHOICE!. See errors above.%RESET%
        goto :end_error
    )
    echo %GRN%Selected GPU architecture: !GFX_ARCH!%RESET%
)
del "!GPU_LIST_FILE!" >nul 2>&1
goto :install_dependencies

:install_dependencies
echo.
echo %CYAN%Upgrading pip and setuptools...%RESET%
"%PYTHON%" -m pip install --upgrade --upgrade-strategy eager pip setuptools==81.0.0
if errorlevel 1 (
    echo Error: pip upgrade failed.
    goto :end_error
)

echo.
echo %CYAN%Updating ROCm PyTorch for %GFX_ARCH% from AMD wheel index...%RESET%
echo Executing: pip install "torch[device-%GFX_ARCH%]" "torchvision[device-%GFX_ARCH%]" torchaudio --index-url %ROCM_INDEX_URL%
"%PYTHON%" -m pip install --upgrade --upgrade-strategy eager "torch[device-%GFX_ARCH%]" "torchvision[device-%GFX_ARCH%]" torchaudio --index-url %ROCM_INDEX_URL%
if errorlevel 1 (
    echo Error: ROCm PyTorch update failed.
    goto :end_error
)

echo.
echo %CYAN%Updating base requirements from requirements-rocm-windows.txt...%RESET%
"%PYTHON%" -m pip install --upgrade --upgrade-strategy eager -r "%SCRIPT_DIR%\requirements-rocm-windows.txt"
if errorlevel 1 (
    echo Error: Base requirements update failed.
    goto :end_error
)

rem --- bitsandbytes (ROCm Windows, Python 3.12 only) ---
echo.
echo %CYAN%Checking Python version for ROCm bitsandbytes...%RESET%
set "PY_VER="
for /f "tokens=2 delims= " %%V in ('"%PYTHON%" --version 2^>^&1') do set "PY_VER=%%V"
set "PY_MINOR="
for /f "tokens=2 delims=." %%M in ("!PY_VER!") do set "PY_MINOR=%%M"
if "!PY_MINOR!"=="12" (
    echo %CYAN%Updating ROCm bitsandbytes wheel ^(Python 3.12^)...%RESET%
    "%PYTHON%" -m pip install https://github.com/0xDELUXA/bitsandbytes_win_rocm/releases/download/0.50.0.dev0-py3-rocm7-win_amd64_all/bitsandbytes-0.50.0.dev0-cp312-cp312-win_amd64.whl
    if errorlevel 1 (
        echo Error: bitsandbytes ROCm update failed.
        goto :end_error
    )
) else (
    echo %YEL%Skipping ROCm bitsandbytes: requires Python 3.12, detected !PY_VER!%RESET%
    echo %YEL%8-bit optimizers and weight quantization will not be available.%RESET%
)

:end_success
echo.
echo **********************
echo ROCm update done
echo GPU arch: %GFX_ARCH%
echo **********************
goto :end

:wrong_python_version
echo.
echo Please install a supported Python version from:
echo https://www.python.org/downloads/windows/
echo.
echo Reminder: Do not rely on installation videos; they are often out of date.
goto :end_error

:end_error
echo.
echo *****************************
echo Error during ROCm update
echo *****************************
goto :end

:end
pause
exit /b %errorlevel%
