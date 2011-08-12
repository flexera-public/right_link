$message = Get-NewResource message
$savedValue = Get-ChefNode "testnode"
if (-not($message -eq $savedValue))
{
    exit 100
}

exit 0
