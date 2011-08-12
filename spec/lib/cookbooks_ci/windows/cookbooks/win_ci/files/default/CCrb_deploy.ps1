# Copyright (c) 2010 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# check inputs.
$sevenZipExePath = $env:SEVEN_ZIP_EXE_PATH
if ("$sevenZipExePath" -eq "")
{
    Write-Error "SEVEN_ZIP_EXE_PATH was not set."
    exit 100
}
$installCCrbPath = $env:INSTALL_CCRB_BAT_FILE_PATH
if ("$installCCrbPath" -eq "")
{
    Write-Error "INSTALL_CCRB_BAT_FILE_PATH was not set."
    exit 101
}
$adminPassword = $env:ADMIN_PASSWORD
if ("$adminPassword" -eq "")
{
    Write-Error "ADMIN_PASSWORD was not set."
    exit 102
}
$toolsBucket = $env:TOOLS_BUCKET
if ("$toolsBucket" -eq "")
{
    Write-Error "TOOLS_BUCKET was not set."
    exit 103
}
$dashboardUrl = $env:DASHBOARD_URL
if ("$dashboardUrl" -eq "")
{
    Write-Error "DASHBOARD_URL was not set."
    exit 104
}
$projects_value = $env:PROJECTS
if ("$projects_value" -eq "")
{
    Write-Error "PROJECTS was not set."
    exit 105
}
else
{
    $projects = @{}
    foreach ($entry in $projects_value.Split("&"))
    {
        $tuple = $entry.Split("=")
        if ($tuple.Length -ne 2)
        {
            Write-Error "Invalid projects string = ""$projects"""
            exit 106
        }
        $projects[$tuple[0]] = $tuple[1]
    }
}


# set admin password
net user administrator "$adminPassword"


# prepare to download.
#
# note that RightLinkService is supposed to place it's version of curl on the
# PATH.
$downloadRoot = "C:\downloads"
if (test-path $downloadRoot)
{
    rd -Recurse -Force $downloadRoot
}
md $downloadRoot | Out-Null


# download tools.
$toolsZipFileName = "tools.zip"
$toolsZipFilePath = join-path $downloadRoot $toolsZipFileName
Write-Output "Downloading ""$toolsZipFileName"""
Write-Verbose "curl -s -S -f -L --retry 7 -w ""%{http_code}"" -o ""$toolsZipFilePath"" ""$toolsBucket/$toolsZipFileName"""
curl -s -S -f -L --retry 7 -w "%{http_code}" -o "$toolsZipFilePath" "$toolsBucket/$toolsZipFileName" | Out-Null
if ($LastExitCode -ne 0)
{
    Write-Error "Failed to download ""$toolsZipFileName"""
    exit $LastExitCode
}


# download wix installer.
$wixMsiFileName = "Wix3.msi"
$wixMsiFilePath = join-path $downloadRoot $wixMsiFileName
Write-Output "Downloading ""$wixMsiFileName"""
Write-Verbose "curl -s -S -f -L --retry 7 -w ""%{http_code}"" -o ""$wixMsiFilePath"" ""$toolsBucket/$wixMsiFileName"""
curl -s -S -f -L --retry 7 -w "%{http_code}" -o "$wixMsiFilePath" "$toolsBucket/$wixMsiFileName" | Out-Null
if ($LastExitCode -ne 0)
{
    Write-Error "Failed to download ""$wixMsiFileName"""
    exit $LastExitCode
}


# unzip the tools package.
$toolsRootPath = "C:\"
$toolsTargetPath = "C:\tools"  # assuming tools folder at root of .zip contents
if (test-path $toolsTargetPath)
{
    rd -Recurse -Force $toolsTargetPath
}
Write-Output "Unzipping ""$toolsZipFilePath"" to ""$toolsTargetPath"""
Write-Verbose """$sevenZipExePath"" x ""$toolsZipFilePath"" ""-o$toolsRootPath"" -r"
& "$sevenZipExePath" x "$toolsZipFilePath" "-o$toolsRootPath" -r | Out-Null
if ($LastExitCode -ne 0)
{
    Write-Error "Unzip failed."
    exit $LastExitCode
}


# copy 7-zip into the exploded tools directory.
$sevenZipSrcDir = split-path -Parent $sevenZipExePath
$sevenZipDstDir = join-path $toolsTargetPath "build\7zip\bin"
if (test-path $sevenZipDstDir)
{
    rd -Recurse -Force $sevenZipDstDir
}
md $sevenZipDstDir | Out-Null
xcopy /R /E /Y "$sevenZipSrcDir" "$sevenZipDstDir"
if ($LastExitCode -ne 0)
{
    Write-Error "7-zip xcopy failed."
    exit $LastExitCode
}


# create a text file containing the dashboard url for configuring CCrb later.
$dashboardUrlFilePath = join-path $toolsTargetPath "dashboard_url.txt"
echo "$dashboardUrl" | out-file $dashboardUrlFilePath -encoding ascii


# silently install the wix .msi.
#
# note that msiexec returns immediately and runs the installer in the
# background. it is not critical that the installer complete before the recipe
# is finished and begins initializing CCrb since that takes some time to setup.
$programFilesX86 = get-item "env:ProgramFiles(x86)" -ea SilentlyContinue
if ($null -eq $programFilesX86)
{
    $wixBinPath = join-path $env:ProgramFiles "Windows Installer XML v3\bin"
}
else
{
    $wixBinPath = join-path $programFilesX86.Value "Windows Installer XML v3\bin"
}
if (!(test-path $wixBinPath))
{
    Write-Output "Silently installing ""$wixMsiFileName"""
    Write-Verbose "msiexec /i ""$wixMsiFilePath"" /quiet"
    msiexec /i "$wixMsiFilePath" /quiet
    if ($LastExitCode -ne 0)
    {
        Write-Error "Wix install failed."
        exit $LastExitCode
    }
}


# put tool shortcuts directory first on the PATH.
$oldPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
$toolsCmdPath = join-path $toolsTargetPath "build\cmd"
$newPath = $toolsCmdPath + ";" + $oldPath + ";" + $wixBinPath
[Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")


# generate the add projects script.
if ($True)
{
    $scriptFilePath = join-path $toolsTargetPath "AddCCrbProjects.bat"
    $scriptLines = @("@echo off", "setlocal")
    foreach ($project in $projects.GetEnumerator())
    {
        $scriptLines += "`r`nrem # add {0} project" -f $project.key
        $scriptLines += "set PROJECT_NAME={0}" -f $project.key
        $scriptLines += "set PROJECT_URL={0}" -f $project.value
        $scriptLines += "set PROJECT_DIR_PATH=%WINDOWS_CI_USER_CRUISE_HOME%\projects\%PROJECT_NAME%"
        $scriptLines += "if not exist ""%PROJECT_DIR_PATH%"" ("
        $scriptLines += "    cd ""%WINDOWS_CI_CCRB_HOME%"""
        $scriptLines += "    call cruise add ""%PROJECT_NAME%"" -s git -r ""%PROJECT_URL%"""
        $scriptLines += "    if %ERRORLEVEL% neq 0 ("
        $scriptLines += "        echo Failed to add ""%PROJECT_NAME%"""
        $scriptLines += "        exit /B 100"
        $scriptLines += "    )"
        $scriptLines += ")"
    }
    $script = ""
    foreach ($line in $scriptLines)
    {
        $script += $line + "`r`n"
    }
    echo $script | out-file $scriptFilePath -encoding ascii
}


# generate the setup projects script.
if ($True)
{
    $scriptFilePath = join-path $toolsTargetPath "SetupCCrbProjects.bat"
    $scriptLines = @("@echo off", "setlocal")
    foreach ($project in $projects.GetEnumerator())
    {
        $scriptLines += "`r`nrem # setup {0} project" -f $project.key
        $scriptLines += "set PROJECT_NAME={0}" -f $project.key
        $scriptLines += "set PROJECT_WORK_PATH=%WINDOWS_CI_USER_CRUISE_HOME%\projects\%PROJECT_NAME%\work"
        $scriptLines += "cd ""%PROJECT_WORK_PATH%"""
        $scriptLines += "if %ERRORLEVEL% neq 0 ("
        $scriptLines += "    echo ""%PROJECT_WORK_PATH%"" does not exist."
        $scriptLines += "    exit /B 100"
        $scriptLines += ")"
        $scriptLines += "call rake cruise:setup_windows"
        $scriptLines += "if %ERRORLEVEL% neq 0 ("
        $scriptLines += "    echo Failed to invoke cruise:setup_windows for ""%PROJECT_WORK_PATH%"""
        $scriptLines += "    exit /B 101"
        $scriptLines += ")"
    }
    $script = ""
    foreach ($line in $scriptLines)
    {
        $script += $line + "`r`n"
    }
    echo $script | out-file $scriptFilePath -encoding ascii
}


# invoke install script from right_net for next stage of setup.
if (test-path $installCCrbPath)
{
    & $installCCrbPath
    $result = $LastExitCode
    if ($result -eq 0)
    {
        net start CCrb
        $result = $LastExitCode
    }
    exit $result
}
else
{
    Write-Error "Cannot locate ""$installCCrbPath"""
    exit 107
}
