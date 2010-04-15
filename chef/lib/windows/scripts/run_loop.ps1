set-executionPolicy Default
while ($TRUE)
{
    $Error.clear()
    $lastError  = $NULL
    $nextAction = $NULL
    $nextAction = get-NextAction $RS_pipeName
    if ($Error.Count -eq 0)
    {
        try
        {
            write-output $nextAction
            set-executionpolicy -executionPolicy Unrestricted
            invoke-command -scriptblock $nextAction
        }
        catch
        {
            $lastError = $_
        }
        finally
        {
            set-executionPolicy Default
            if ($lastError -ne $NULL)
            {
                write-output $lastError
                exit 100
            }
        }
    }
    else
    {
        break
    }
}

exit 0
