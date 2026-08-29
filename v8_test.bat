@echo off

setlocal

set "dir=%~dp0"

if not exist "%dir%\v8" (
  echo V8 not found
  exit /b 1
)

rem Compile the way a consumer now has to: Chromium's clang, against the libc++
rem headers the archive ships, with the platform standard library shut out.
rem
rem That is the contract this artifact carries. V8 is built with libc++
rem (use_custom_libcxx=true, which recent V8 requires), so anything linking it
rem must use the same standard library -- compiling this sample with MSVC's STL
rem produced 358 unresolved std::__Cr symbols, which is exactly the failure this
rem test exists to catch before the artifact ships.
rem
rem /clr used to be on this line and cannot be: it is mutually exclusive with
rem /EHsc, which MSVC 19.51 rejects outright (D8016), and this sample is native
rem C++ rather than managed C++/CLI.

set "clangcl=%dir%\v8\third_party\llvm-build\Release+Asserts\bin\clang-cl.exe"
if not exist "%clangcl%" (
  echo Chromium clang not found at %clangcl%
  exit /b 1
)

set "libcxxInc=%dir%\pack\libcxx-include"
if not exist "%libcxxInc%" (
  echo libc++ headers not found at %libcxxInc% -- run archive.bat first
  exit /b 1
)

call "%clangcl%" /EHsc /std:c++20 /Zc:__cplusplus /MT ^
  /D_LIBCPP_ABI_NAMESPACE=__Cr /D_LIBCPP_HAS_NO_LIBRARY_ALIGNED_ALLOCATION ^
  /experimental:library-preprocessor- ^
  -nostdinc++ -isystem"%libcxxInc%" ^
  /I"%dir%\v8" /I"%dir%\v8\include" ^
  /Fe".\hello-world" "%dir%\v8\samples\hello-world.cc" ^
  /link "%dir%\v8\out\release\obj\v8_monolith.lib" ^
  /DEFAULTLIB:advapi32.lib /DEFAULTLIB:dbghelp.lib /DEFAULTLIB:winmm.lib

if errorlevel 1 (
  echo Compilation failed
  exit /b %errorlevel%
)

call .\hello-world.exe

endlocal
