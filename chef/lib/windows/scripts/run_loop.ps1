set-executionPolicy Default
while ($TRUE)
{
    $Error.clear()
    $nextAction = $NULL
    $nextAction = get-NextAction $pipeName
    if ($Error.Count -eq 0)
    {
        write-output $nextAction
        set-executionpolicy -executionPolicy Unrestricted
        invoke-command -scriptblock $nextAction
        set-executionPolicy Default
    }
    else
    {
        break
    }
}
