Copyright (c) 2010 RightScale Inc

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


Overview
--------

The "ChefNodeCmdlet.dll" module provides a set of cmdlets which extend the
functionality of the PowerShell environment to include tools useful for writing
Chef recipes for Windows.

See https://rightscale.onconfluence.com/display/rightscale/RightLink+ChefNodeCmdlet


Debugging from Visual Studio
----------------------------
VS 2008 C# projects appear not to allow variable substitution in debug command
lines (as has been allowed previously by C++ projects). This is likely to
improve in future, but in the meantime hardcode the .dll path (which gets
saved in your personal "ChefNodeCmdlet.csproj.user" file and is never checked
into source control).

Use the installed PowerShell 2.0 location as the executable path and use the
following as the command line string (substituting .dll path as needed).

Example:

Start external program:
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe

Command line arguments:
-NoExit -Command "&{ import-module 'C:\dev\right_net\instance\right_link\chef\lib\windows\ChefNodeCmdlet\Debug\ChefNodeCmdlet.dll' -verbose }"
