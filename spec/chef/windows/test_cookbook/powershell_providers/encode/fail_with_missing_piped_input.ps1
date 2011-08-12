# note that there are intentionally not enough arguments for ConvertTo-SecureString
$plainTextPassword = 'Secret123!'
$securePassword = write-output $plainTextPassword | ConvertTo-SecureString
