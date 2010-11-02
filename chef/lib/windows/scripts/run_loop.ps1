$RS_lastExitCode = 0
$RS_lastErrorMessage = ""
$global:RS_lastErrorRecord = $NULL
while ($TRUE)
{
    try
    {
        $Error.clear()
        $LastExitCode = 0
        $RS_nextAction = $NULL
        $RS_nextAction = get-NextAction $RS_pipeName $RS_lastExitCode $RS_lastErrorMessage
        if ($RS_lastErrorMessage -ne "" -or $RS_lastExitCode -ne 0)
        {
            exit $RS_lastExitCode
        }
        elseif ($Error.Count -eq 0)
        {
            # note that $RS_nextAction may be wrapped with additional instructions and so
            # is too verbose for normal output. the next action usually refers to a locally
            # cached script whose name but not path is meaningful to the user (with the
            # exception of a terminating "exit" which doesn't need to be seen here). scripts
            # should provide sufficient standard output to indicate what activity is
            # occurring without our having to report which script is running.
            write-verbose $RS_nextAction

            # invoke next action.
            invoke-command -scriptblock $RS_nextAction
            $RS_lastExitCode = $global:LastExitCode
            if ($NULL -eq $RS_lastExitCode)
            {
                $RS_lastExitCode = 0
            }
            $RS_lastErrorMessage = ""
        }
        else
        {
            break
        }
    }
    catch
    {
        if ($RS_lastErrorMessage -ne "" -or $RS_lastExitCode -ne 0)
        {
            exit $RS_lastExitCode
        }
        if ($NULL -eq $global:RS_lastErrorRecord)
        {
            $global:RS_lastErrorRecord = $_
        }
    }

    if ($NULL -ne $global:RS_lastErrorRecord)
    {
        $invocationInfo = $global:RS_lastErrorRecord.invocationInfo
        write-debug ($invocationInfo | Out-String).TrimEnd()
        $scriptSnip = ""
        $scriptPath = $invocationInfo.ScriptName
        if (($NULL -ne $scriptPath) -and ($scriptPath.Length -gt 0))
        {
            $scriptSource = get-content $scriptPath
            $firstLine    = [system.math]::max($invocationInfo.ScriptLineNumber - 4, 0)
            $lastLine     = [system.math]::min($invocationInfo.ScriptLineNumber + 4, $scriptSource.length)
            for ($i = $firstLine; $i -lt $lastLine; ++$i)
            {
                $lineNumber = $i + 1
                if ($lineNumber -eq $invocationInfo.ScriptLineNumber)
                {
                    # the reported character offset in the offending line can be past the end for
                    # some exceptions. an example is missing inputs on a piped command line.
                    $lineOffset = $invocationInfo.OffsetInLine
                    $lineLength = $invocationInfo.Line.Length
                    if ($lineOffset -gt $lineLength)
                    {
                        $lineOffset = $lineLength
                    }
                    $firstPart   = $invocationInfo.Line.Substring(0, $lineOffset)
                    $secondPart  = $invocationInfo.Line.Substring($lineOffset, $lineLength - $lineOffset)
                    $scriptSnip += "`n    + $lineNumber" + ":`t$FirstPart <<<< $SecondPart"
                }
                else
                {
                    $scriptSnip += "`n    + $LineNumber" + ":`t" + $scriptSource[$i]
                }
            }
        }
        else
        {
            # failure occurred in an internal code fragment which has no meaningful script or line information.
            # the stringized error record contains sufficient information in this case.
            $scriptSnip = $NULL
        }
        $RS_lastErrorMessage = ($global:RS_lastErrorRecord | Out-String).TrimEnd()
        if ($NULL -ne $scriptSnip)
        {
            $RS_lastErrorMessage += "`n    +`n    + Script error near:" +  $scriptSnip + "`n"
        }
        else
        {
            $RS_lastErrorMessage += "`n    +`n    + Error occurred in internal code block."
        }
        $RS_lastExitCode = 1
    }
}

exit $RS_lastExitCode
