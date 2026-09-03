#Requires -Version 5.0
# Invoked directly via SSH as its own isolated process.
# If Elastic kills this script (Potential Obfuscated PowerShell Script rule),
# no other stage is affected — each stage runs in its own SSH connection.

$ErrorActionPreference = 'SilentlyContinue'

$null = & ([scriptblock]::Create(
    [Text.Encoding]::Unicode.GetString(
        [Convert]::FromBase64String(
            [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes('$null = ' + [char]39 + 'nothing' + [char]39)
            )
        )
    )
))

$p = (([char]87)+([char]114)+([char]105)+([char]116)+([char]101)+([char]45)+([char]78)+([char]117)+([char]108)+([char]108))
$c = (('Inv'+'oke'+'-'+'Ex'+'pr'+'es'+'si'+'on'))
& ([scriptblock]::Create("$p `$null"))
