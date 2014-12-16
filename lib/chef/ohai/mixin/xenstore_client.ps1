param(
  [Parameter(Mandatory=$True,Position=0)][string]$command,
  [Parameter(Mandatory=$True,Position=1)][string]$value
)

function error($msg) {
  echo $msg
  exit 1
}
 
$sessionName = "XenStoreReader"
 
$session = Get-WmiObject -Namespace root\wmi -Query "select * from CitrixXenStoreSession where Id='$sessionName'"
if (!($session)) {
  $base = Get-WmiObject -Namespace root\wmi -Class CitrixXenStoreBase 
  $base.AddSession($sessionName) | Out-Null
  $session = Get-WmiObject -Namespace root\wmi -Query "select * from CitrixXenStoreSession where Id='$sessionName'"
}
 
switch -regex ($command)
{
   "^read$"  {
     $res = $session.GetValue($value)
     if ($res) {
      return $res.value
     } else {
      error -msg "Could not find value $value"
     }
  }
  "^(ls|dir)$" {
    $res = $session.GetChildren($value)
    if ($res) {
      return $res.children.ChildNodes -replace "$value/", ""
    } else {
      error -msg "Could not find dir $value"
    }
  }
  default {
    error -msg "Unrecognized command $command. Only 'read' and 'dir' are currently supported"
  }
}
