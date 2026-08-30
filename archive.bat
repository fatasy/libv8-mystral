@echo off

setlocal

set "dir=%~dp0"

set "archiveName=%~1"
set "outputDir=%dir%\pack"

set "os=%RUNNER_OS%"
if "%os%"=="" (
  set "os=Windows"
)

if "%archiveName%"=="" (
  if "%RUNNER_ARCH%"=="X86" (
    set "arch=x86"
  ) else if "%RUNNER_ARCH%"=="X64" (
    set "arch=x64"
  ) else if "%RUNNER_ARCH%"=="ARM64" (
    set "arch=arm64"
  ) else if "%RUNNER_ARCH%"=="ARM" (
    set "arch=arm"
  ) else (
    if "%PROCESSOR_ARCHITECTURE%"=="x86" (
      set "arch=x86"
    ) else if "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
      set "arch=arm64"
    ) else (
      set "arch=x64"
    )
  )

  set "archive=v8_%os%_%arch%.7z"
) else (
  set "archive=%archiveName%.7z"
)

if not exist "%outputDir%" (
  mkdir "%outputDir%"
)

rem The monolith does not carry libc++. V8 is built against Chromium's libc++
rem (use_custom_libcxx=true, which recent V8 requires), but libc++ is a GN
rem source_set, so its objects land in out/ and never reach v8_monolith.lib --
rem linking the artifact then fails on hundreds of unresolved std::__Cr symbols.
rem
rem Fold those objects in, so the artifact is self-contained and consumers keep
rem linking exactly one library.
set "libcxxObjs=%dir%\v8\out\release\obj\buildtools\third_party\libc++\libc++"
if exist "%libcxxObjs%" (
  echo Folding libc++ into the monolith
  lib.exe /NOLOGO /OUT:"%dir%\v8\out\release\obj\v8_monolith_full.lib" ^
    "%dir%\v8\out\release\obj\v8_monolith.lib" "%libcxxObjs%\*.obj"
  if errorlevel 1 (
    echo Failed to fold libc++ into the monolith
    exit /b 1
  )
  copy /Y "%dir%\v8\out\release\obj\v8_monolith_full.lib" "%outputDir%\v8_monolith.lib"
) else (
  echo libc++ objects not found at %libcxxObjs%
  exit /b 1
)

xcopy /E /I /Q /Y "%dir%\v8\include" "%outputDir%"

rem libc++ headers. Consumers compile against these instead of the platform
rem standard library, which is the whole point: one std, shared with V8.
rem Chromium moved this path once already, so both layouts are accepted and a
rem miss is an error rather than a silently header-less artifact.
if exist "%dir%\v8\third_party\libc++\src\include" (
  xcopy /E /I /Q /Y "%dir%\v8\third_party\libc++\src\include" "%outputDir%\libcxx-include"
) else if exist "%dir%\v8\buildtools\third_party\libc++\trunk\include" (
  xcopy /E /I /Q /Y "%dir%\v8\buildtools\third_party\libc++\trunk\include" "%outputDir%\libcxx-include"
) else (
  echo libc++ headers not found
  exit /b 1
)

rem Chromium keeps its libc++ wrapper next to the sources: __config_site with
rem the ABI settings the library was actually built with, __assertion_handler,
rem and whatever else it layers on. Every libc++ header reaches these through
rem __config, so headers without them cannot be included at all.
rem
rem Ship the directory whole rather than picking files out of it. Picking meant
rem searching, and searching found Perfetto's bundled libcxx_config instead --
rem a decoy that compiled far enough to fail on a missing __assertion_handler.
rem Consumers put this directory on the include path ahead of libcxx-include.
set "libcxxCfg=%dir%\v8\buildtools\third_party\libc++"
if exist "%libcxxCfg%\__config_site" (
  xcopy /E /I /Q /Y "%libcxxCfg%" "%outputDir%\libcxx-config"
) else (
  echo Chromium libc++ wrapper not found at %libcxxCfg%
  exit /b 1
)

rem The _LIBCPP_* defines that libc++ needs are NOT in __config_site -- that file
rem says so itself: "Things that are set depending on GN args are not here."
rem They are passed on the command line by build/config/libc++, and libc++
rem refuses to compile without them (_LIBCPP_HARDENING_MODE_DEFAULT is not
rem defined). Guessing is not an option: the hardening mode changes container
rem layout, so a wrong value links and then misbehaves.
rem
rem Take them from the generated ninja files, which record the exact flags this
rem library was compiled with.
set "definesFile=%outputDir%\libcxx-defines.txt"
findstr /s /c:"_LIBCPP_HARDENING_MODE" "%dir%\v8\out\release\*.ninja" > "%dir%\libcxx-raw.txt" 2>nul
if not exist "%dir%\libcxx-raw.txt" (
  echo Could not read libc++ defines from the ninja files
  exit /b 1
)
powershell -NoProfile -Command ^
  "$m = Select-String -Path '%dir%\v8\out\release\*.ninja' -Pattern '-D(_LIBCPP_[A-Za-z0-9_]+(=[^ ]*)?)' -AllMatches;" ^
  "$d = $m.Matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique;" ^
  "if (-not $d) { exit 1 };" ^
  "$d | Set-Content -Encoding ascii '%definesFile%'"
if errorlevel 1 (
  echo No _LIBCPP defines found
  exit /b 1
)
echo libc++ defines:
type "%definesFile%"

where 7z >nul 2>nul
if errorlevel 1 (
  echo 7z not found
  exit /b %errorlevel%
)

pushd "%outputDir%"

call 7z a -r "%dir%\%archive%" .
if errorlevel 1 (
  echo Failed to archive.
  exit /b %errorlevel%
)

popd

dir "%dir%\%archive%"

endlocal
