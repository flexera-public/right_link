$RS_LastExitCode = 0
$RS_LastError = ""
while ($TRUE)
{
    try
    {
        $Error.clear()
        $LastExitCode = 0
        $RS_nextAction = $NULL
        $RS_nextAction = get-NextAction $RS_pipeName $RS_LastExitCode $RS_LastError
        if ($RS_LastError -ne "" -or $RS_LastExitCode -ne 0)
        {
            exit $RS_LastExitCode
        }
        elseif($Error.Count -eq 0)
        {
            write-output $RS_nextAction
            invoke-command -scriptblock $RS_nextAction
            $RS_LastExitCode = $global:LastExitCode
            if ($NULL -eq $RS_LastExitCode)
            {
                $RS_LastExitCode = 0
            }
            $RS_LastError = ""
        }
        else
        {
            break
        }
    }
    catch
    {
        if ($RS_LastError -ne "" -or $RS_LastExitCode -ne 0)
        {
            exit $RS_LastExitCode
        }

        $ScriptSnip = ""

        $ErrorRecord    = $_
        $InvocationInfo = $ErrorRecord.InvocationInfo
        $ScriptSource  = get-content $InvocationInfo.ScriptName
        $FirstLine     = [system.math]::max($InvocationInfo.ScriptLineNumber - 4, 0)
        $LastLine      = [system.math]::min($InvocationInfo.ScriptLineNumber + 4, $ScriptSource.length)
        for($i=$FirstLine; $i -lt $LastLine; $i++)
        {
            $LineNumber = $i+1
            if ($LineNumber -eq $InvocationInfo.ScriptLineNumber)
            {
                $FirstPart     = $InvocationInfo.Line.Substring(0, $InvocationInfo.OffsetInLine - 1)
                $SecondPart    = $InvocationInfo.Line.Substring($InvocationInfo.OffsetInLine, $InvocationInfo.Line.length - $InvocationInfo.OffsetInLine)

                $ScriptSnip += "`n    + $LineNumber" + ":`t$FirstPart <<<< $SecondPart"
            }
            else
            {
                $ScriptSnip +=  "`n    + $LineNumber" + ":`t" + $ScriptSource[$i]
            }
        }

        $RS_LastError =  ($ErrorRecord | Out-String).TrimEnd() + "`n    +`n    + Script error near:" +  $ScriptSnip + "`n"
        $RS_LastExitCode = 1
    }
}

write-output "exiting run-loop"

exit $RS_LastExitCode
