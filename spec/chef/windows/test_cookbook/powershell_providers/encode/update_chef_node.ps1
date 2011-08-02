$message = Get-NewResource message
Set-ChefNode -Path "testnode" -StringValue $message 
