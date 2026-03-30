Get-Content slotduck.zip.b64 | Out-String | % { [System.Convert]::FromBase64String($_) } | Set-Content -Encoding Byte slotduck.zip
