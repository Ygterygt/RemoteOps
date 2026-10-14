$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Root=Split-Path -Parent $PSScriptRoot
# Cross-checks the GUI catalog against descriptions, input validation, confirmation words, runner dispatch, report metadata and the parallel-safe lists.
function Get-FileAst($Path){$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e)}
function Find-Assign($Ast,$Left){$Ast.Find({param($N)$N -is [System.Management.Automation.Language.AssignmentStatementAst] -and $N.Left.Extent.Text -eq $Left},$true)}
$AppAst=Get-FileAst (Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1')
$RunAst=Get-FileAst (Join-Path $Root 'RemoteOps.App\RemoteOps.Runner.ps1')
$RepAst=Get-FileAst (Join-Path $Root 'RemoteOps.App\RemoteOps.Reports.ps1')
$Catalog=@(& ([scriptblock]::Create((Find-Assign $AppAst '$script:OperationCatalog').Right.Extent.Text)))
$Meta=& ([scriptblock]::Create((Find-Assign $RepAst '$script:RemoteOpsOperationMeta').Right.Extent.Text))
$Errors=@()
if($Catalog.Count -lt 20){throw "Catalog could not be read ($($Catalog.Count) operations)."}
foreach($Fn in @('Get-OperationDescription','Get-OptionalPropertyValue','Assert-OperationInputs')){
    $F=$AppAst.Find({param($N)$N -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Fn},$true)
    . ([scriptblock]::Create($F.Extent.Text))
}
# parallel-safe lists
$AppSafe=@((Find-Assign $AppAst '$script:ParallelSafeOperations').Right.Find({param($N)$N -is [System.Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object{$_.Value}|Sort-Object)
$AppSafe=@((& ([scriptblock]::Create((Find-Assign $AppAst '$script:ParallelSafeOperations').Right.Extent.Text)))|Sort-Object)
$RunSafe=@((& ([scriptblock]::Create((Find-Assign $RunAst '$script:ParallelSafeOperations').Right.Extent.Text)))|Sort-Object)
if(($AppSafe -join ',') -cne ($RunSafe -join ',')){$Errors+='Parallel-safe lists differ between App and Runner.'}
foreach($S in $AppSafe){if(@($Catalog|Where-Object{$_.Name -ceq $S}).Count -ne 1){$Errors+="Parallel-safe name not in catalog: $S"}}
# runner switch patterns
$Switch=$RunAst.Find({param($N)$N -is [System.Management.Automation.Language.SwitchStatementAst] -and ($N.Flags -band [System.Management.Automation.Language.SwitchFlags]::Regex) -and $N.Condition.Extent.Text -like '*$OperationName*'},$true)
$Patterns=@($Switch.Clauses|ForEach-Object{[string]$_.Item1.Extent.Text.Trim("'")})
# confirmation words
$ExpAssign=Find-Assign $AppAst '$Expected'
$ReqAssign=Find-Assign $RunAst '$RequiredConfirmation'
$ExpBlock=[scriptblock]::Create('param($Operation,$Values) '+$ExpAssign.Right.Extent.Text)
$ReqBlock=[scriptblock]::Create('param($OperationName,$Values) '+$ReqAssign.Right.Extent.Text)
$Variants=@{Action=@('Pull','Move','Replace','Start','Stop','Restart','Run','Enable','Disable','Install','Uninstall','Downgrade')}
foreach($Op in $Catalog){
    $N=$Op.Name
    if(-not $Meta.ContainsKey($N)){$Errors+="$N missing in Reports metadata";}
    else{$P=$Meta[$N] -split '\|',2;if($P[0] -cne $Op.Category -or $P[1] -cne $Op.Title){$Errors+="$N metadata differs from catalog ($($Meta[$N]) vs $($Op.Category)|$($Op.Title))"}}
    if((Get-OperationDescription $Op) -like 'Plugin operasyonu*'){$Errors+="$N has no description"}
    if(@($Patterns|Where-Object{$N -cmatch $_}).Count -ne 1){$Errors+="$N is not handled by exactly one runner switch branch"}
    $Keys=@($Op.Fields|ForEach-Object{$_.Key})
    if($Keys -cnotcontains 'Targets'){$Errors+="$N has no Targets field"}
    $Vals=@{};foreach($K in $Keys){$Vals[$K]=''}
    $Actions=@('')
    if($Keys -contains 'Action'){$Actions=@($Op.Fields|Where-Object{$_.Key -eq 'Action'}|ForEach-Object{$_.Options})}
    foreach($A in $Actions){
        $V=@{} + $Vals;if($A){$V.Action=$A}
        $V.Confirm='x'
        $E="$(& $ExpBlock $Op $V)";$R="$(& $ReqBlock $N $V)"
        if($E -cne $R){$Errors+="$N action '$A': App expects '$E' but Runner requires '$R'"}
    }
    # required keys must be real fields; empty values must be rejected when something is required
    $Threw=$false;$Msg='';try{Assert-OperationInputs -Operation $Op -Values $Vals}catch{$Threw=$true;$Msg=$_.Exception.Message}
    if($Threw){$Key=($Msg -replace '^Required input is empty: ','');if($Keys -cnotcontains $Key){$Errors+="$N requires unknown input key '$Key'"}}
}
# Every control bound with Window.FindName must exist in XAML and vice versa; four product tabs.
$AppText=[IO.File]::ReadAllText((Join-Path $Root 'RemoteOps.App\RemoteOps.App.ps1'),[Text.Encoding]::UTF8)
$Xaml=[regex]::Match($AppText,'(?s)\$script:WindowXaml = @''(.*?)\r?\n''@').Groups[1].Value
$XamlNames=@([regex]::Matches($Xaml,'x:Name="(\w+)"')|ForEach-Object{$_.Groups[1].Value}|Where-Object{$_ -notin 'Bd','Cp'})
$BindLine=@($AppText -split "`r?`n"|Where-Object{$_ -match 'foreach\(\$Name in @\(''ActiveIdentity'''})[0]
$Bound=@([regex]::Matches(($BindLine -replace '\)\)\{.*$',''),"'(\w+)'")|ForEach-Object{$_.Groups[1].Value})
foreach($B in $Bound){if($XamlNames -cnotcontains $B){$Errors+="Control '$B' is bound but not in the XAML"}}
foreach($X in $XamlNames){if($Bound -cnotcontains $X){$Errors+="XAML control '$X' is never bound"}}
if([regex]::Matches($Xaml,'<TabItem ').Count -ne 4){$Errors+='MainTabs must hold four tabs (Paketlerim, Paket Olustur, Operasyon, Rapor).'}
foreach($Need in 'OpenSettings','SettingsOverlay','CloseSettings'){if($Bound -cnotcontains $Need){$Errors+="$Need is not bound"}}
if($AppText -notmatch 'Key -eq ''Escape'' -and \$script:SettingsOverlay\.Visibility -eq ''Visible'''){$Errors+='Esc must close the settings overlay.'}if($Errors.Count -gt 0){throw ($Errors -join "`n")}
Write-Output ("PASS: catalog consistency ({0} operations): descriptions, report metadata, runner dispatch, confirmation words, input keys and parallel-safe lists agree." -f $Catalog.Count)
