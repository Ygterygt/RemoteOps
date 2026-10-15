function New-RemoteOpsOfflineRunnerFixture {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$FixtureRoot,[Parameter(Mandatory)][string]$DataRoot,[Parameter(Mandatory)][string]$StatePath)
 foreach($p in @($SourceRoot,$FixtureRoot,$DataRoot,$StatePath)){if(-not [IO.Path]::IsPathRooted($p)){throw 'Fixture paths must be absolute.'}}
 if(Test-Path -LiteralPath $FixtureRoot){throw 'Fixture destination must not exist.'}
 New-Item -ItemType Directory -Path $FixtureRoot -Force|Out-Null
 foreach($dir in @('RemoteOps.App','Modules')){Copy-Item -LiteralPath (Join-Path $SourceRoot $dir) -Destination $FixtureRoot -Recurse}
 New-Item -ItemType Directory -Path $DataRoot -Force|Out-Null
 $app=Join-Path $FixtureRoot 'RemoteOps.App'
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'FixtureBoundary.ps1') -Destination $app
 $env:REMOTEOPS_OFFLINE_STATE=[IO.Path]::GetFullPath($StatePath)
 $env:REMOTEOPS_OFFLINE_RUNNER=Join-Path $app 'RemoteOps.Runner.ps1'
 function Replace-OfflineExact($Text,$Anchor,$Replacement){if(([regex]::Matches($Text,[regex]::Escape($Anchor))).Count -ne 1){throw ('Fixture anchor mismatch: '+$Anchor)};$Text.Replace($Anchor,$Replacement)}
 $runner=$env:REMOTEOPS_OFFLINE_RUNNER
 $text=[IO.File]::ReadAllText($runner)
 $text=Replace-OfflineExact $text '$Request = $null' ('$Request = $null'+"`r`n"+'. (Join-Path $PSScriptRoot ''FixtureBoundary.ps1'')'+"
"+'if($PreflightBase64){Invoke-OfflineBlocked ''Preflight''}')
 $text=Replace-OfflineExact $text 'Microsoft.PowerShell.Management\Start-Process @PSBoundParameters' 'Invoke-OfflineStartProcess @PSBoundParameters'
 $text=Replace-OfflineExact $text '$Request = ConvertFrom-Json -InputObject $RequestJson -ErrorAction Stop' ('$Request = ConvertFrom-Json -InputObject $RequestJson -ErrorAction Stop'+"`r`n"+'    Assert-OfflineRequest $Request')
 $text=Replace-OfflineExact $text '$BasePath = ''C:\Temp\YD_RemoteOps.App''' ('$BasePath = '''+$DataRoot.Replace("'","''")+"'")
 # Dot-source again after production function definitions/modules have loaded.
 $text=Replace-OfflineExact $text '    # Mod 3: operasyon listesini yaz ve cik.' ('    . (Join-Path $PSScriptRoot ''FixtureBoundary.ps1'')'+"`r`n"+'    # Mod 3: operasyon listesini yaz ve cik.')
 [IO.File]::WriteAllText($runner,$text,[Text.UTF8Encoding]::new($true))
 $recipe=Join-Path $app 'RemoteOps.RecipeExecution.ps1'
 $text=[IO.File]::ReadAllText($recipe)
 $text=Replace-OfflineExact $text '$Process=Microsoft.PowerShell.Management\Start-Process -FilePath' '$Process=Invoke-OfflineStartProcess -FilePath'
 [IO.File]::WriteAllText($recipe,$text,[Text.UTF8Encoding]::new($true))
 return $runner
}

