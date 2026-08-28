@echo off

setlocal

set "dir=%~dp0"

if not exist "%dir%\v8" (
  echo V8 not found
  exit /b 1
)

rem /clr was here and cannot be: it is mutually exclusive with /EHsc, which
rem MSVC 19.51 rejects outright (D8016). It was also meaningless — this sample
rem is native C++, not managed C++/CLI. Its presence failed the build after
rem ninja had already produced the library, and a failed test skips the archive
rem step, so a 1h39m build published nothing.
rem /Zc:__cplusplus is required, not optional: MSVC reports __cplusplus as
rem 199711L even under /std:c++20 without it, and v8config.h tests __cplusplus
rem directly ("C++20 or later required"). The /clr error above was hiding this.
call cl.exe /EHsc /std:c++20 /Zc:__cplusplus /I"%dir%\v8" /I"%dir%\v8\include" ^
  /Fe".\hello-world" "%dir%\v8\samples\hello-world.cc" ^
  /link "%dir%\v8\out\release\obj\v8_monolith.lib" ^
  /DEFAULTLIB:advapi32.lib /DEFAULTLIB:dbghelp.lib /DEFAULTLIB:winmm.lib

if errorlevel 1 (
  echo Compilation failed
  exit /b %errorlevel%
)

call .\hello-world.exe

endlocal
