$RS_lastReturnCode = 0
while ($TRUE)
{
    $Error.clear()
    $RS_lastReturnCode = 0
    $RS_nextAction = $NULL
    $RS_nextAction = get-NextAction $RS_pipeName
    if ($Error.Count -eq 0)
    {
        try
        {
            write-output $RS_nextAction
            invoke-command -scriptblock $RS_nextAction
            $RS_lastReturnCode = $LastExitCode
        }
        catch
        {
            $exception_string = "+ The exception occurred near:`n+"

            $script_info    = $_.InvocationInfo
            $script_source  = get-content $script_info.ScriptName
            $first_line     = [system.math]::max($script_info.ScriptLineNumber - 3, 0)
            $last_line      = [system.math]::min($script_info.ScriptLineNumber + 3, $script_source.length)
            for($i=$first_line; $i -lt $last_line; $i++)
            {
                if (($i+1) -eq $script_info.ScriptLineNumber)
                {
                    $first_part     = $script_info.Line.Substring(0, $script_info.OffsetInLine)
                    $second_part    = $script_info.Line.Substring($script_info.OffsetInLine, $script_info.Line.length - $script_info.OffsetInLine)

                    $output = "`n+`t$first_part <<<< $second_part"
                }
                else
                {
                    $output = "`n+`t" + $script_source[$i]
                }
                $exception_string += $output
            }

            $error_string = $_ | out-string
            $error_string = $error_string.TrimEnd() + "`n+`n" +  $exception_string + "`n"

            write-output $error_string

            exit 1
        }
    }
    else
    {
        break
    }
}

exit $RS_lastReturnCode
