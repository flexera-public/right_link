while ($TRUE)
{
    $Error.clear()
    $RS_lastError  = $NULL
    $RS_nextAction = $NULL
    $RS_nextAction = get-NextAction $RS_pipeName
    if ($Error.Count -eq 0)
    {
        try
        {
            write-output $RS_nextAction
            invoke-command -scriptblock $RS_nextAction
        }
        catch
        {
            $RS_lastError = $_
        }
        finally
        {
            if ($RS_lastError -ne $NULL)
            {
                write-output $RS_lastError
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
