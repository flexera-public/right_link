while ($TRUE)
{
    $Error.clear()
    $nextAction = $NULL
    $nextAction = get-NextAction
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
