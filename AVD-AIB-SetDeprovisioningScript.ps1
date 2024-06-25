# This updates the C:\DeprovisioningScript.ps1 to utilise the /mode:vm to stop the "Please wait for the windows modules installer"

((Get-Content -path C:\DeprovisioningScript.ps1 -Raw) -replace 'Sysprep.exe /oobe /generalize /quiet /quit','Sysprep.exe /oobe /generalize /quit /mode:vm' ) | Set-Content -Path C:\DeprovisioningScript.ps1
