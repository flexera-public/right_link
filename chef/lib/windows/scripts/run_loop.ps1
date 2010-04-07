while ($TRUE)
{
    $Error.clear()
    $nextAction = $NULL
    $nextAction = get-NextAction $pipeName
    if ($Error.Count -eq 0)
    {
        write-output $nextAction
        invoke-command -scriptblock $nextAction
    }
    else
    {
        break
    }
}
