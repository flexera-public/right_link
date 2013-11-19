@echo off
rem # Copyright (c) 2009-2011 RightScale Inc
rem #
rem # Permission is hereby granted, free of charge, to any person obtaining
rem # a copy of this software and associated documentation files (the
rem # "Software"), to deal in the Software without restriction, including
rem # without limitation the rights to use, copy, modify, merge, publish,
rem # distribute, sublicense, and/or sell copies of the Software, and to
rem # permit persons to whom the Software is furnished to do so, subject to
rem # the following conditions:
rem #
rem # The above copyright notice and this permission notice shall be
rem # included in all copies or substantial portions of the Software.
rem #
rem # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
rem # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
rem # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
rem # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
rem # LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
rem # OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
rem # WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

setlocal

rem # use dev source if specified. "ruby.exe" will be located as usual.

if "%1" equ "dev" (
  if exist "%~dp0..\..\..\..\right_link" (
    set RS_RIGHT_LINK_FULL_HOME=%~dp0..\..\..\..
    set RS_RIGHT_LINK_HOME=%~dps0..\..\..\..
  )
)
call "%~dp0LocateSpecSandBox.bat"
if %ERRORLEVEL% neq 0 (
  echo Unable to locate sandbox.
  exit /B %ERRORLEVEL%
)


rem # put found "ruby.exe" on the path for convenience in dev. the production
rem # environment should not expect the sandbox "ruby.exe" to be on the path
rem # because users may want their own ruby on the path.

if "%1" neq "dev" goto :AfterRuby

set PATH=%PATH%;%RS_RUBY_HOME%\bin
set RS_DEV_HOME=%RS_RIGHT_LINK_HOME%\..\..
set RS_CURL_EXE=c:\tools\shell\bin\curl.exe
set RS_TAR_RB=c:\tools\shell\script\tar.rb
set RS_RIGHT_RUN_EXE=%RS_DEV_HOME%\right_link_package\instance\win32_sandbox_service\RightRun\bin\Release\RightRun.exe

:AfterRuby
if exist "%RS_RIGHT_LINK_HOME%\right_link_package\instance\bin\windows" (
  set RS_RIGHT_LINK_PACKAGE_BIN_WINDOWS=%RS_RIGHT_LINK_HOME%\right_link_package\instance\bin\windows
) else (
  set RS_RIGHT_LINK_PACKAGE_BIN_WINDOWS=%RS_RIGHT_LINK_HOME%\bin\windows
)
set PATH=%PATH%;%RS_RIGHT_LINK_PACKAGE_BIN_WINDOWS%


rem # include spec scripts on path
set PATH=%PATH%;%~dps0.
start "RightScale SandBox" cmd.exe /k "cd /d "%RS_RIGHT_LINK_FULL_HOME%""
