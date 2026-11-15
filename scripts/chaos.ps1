<#
.SYNOPSIS
  Inject a failure scenario on the Xora test EC2 instance through SSM (no SSH needed).

.EXAMPLE
  .\chaos.ps1 -Scenario cpu
  .\chaos.ps1 -Scenario stop
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('cpu', 'errors', 'disk', 'memory', 'service-down', 'correlated', 'flap', 'stop', 'status')]
    [string]$Scenario,

    [string]$Region = 'ap-southeast-1'
)

$ErrorActionPreference = 'Stop'
$tfDir = Join-Path $PSScriptRoot '..\terraform'

$instanceId = terraform "-chdir=$tfDir" output -raw instance_id
if ($LASTEXITCODE -ne 0 -or -not $instanceId) { throw 'Could not read instance_id from terraform output. Did you run terraform apply?' }

# Write the SSM parameters to a temp file (no BOM). This avoids PowerShell JSON quoting problems.
$paramsJson = @{ commands = @("sudo /opt/chaos/chaos.sh $Scenario") } | ConvertTo-Json -Compress
$tmp = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($tmp, $paramsJson)

try {
    $startedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $commandId = aws ssm send-command --region $Region --instance-ids $instanceId `
        --document-name AWS-RunShellScript --comment "xora chaos: $Scenario" `
        --parameters "file://$tmp" --query 'Command.CommandId' --output text
    if ($LASTEXITCODE -ne 0) { throw 'aws ssm send-command failed' }

    Write-Host "Scenario '$Scenario' sent to $instanceId (command $commandId) at $startedUtc" -ForegroundColor Cyan
    aws ssm wait command-executed --region $Region --command-id $commandId --instance-id $instanceId

    aws ssm get-command-invocation --region $Region --command-id $commandId --instance-id $instanceId `
        --query 'StandardOutputContent' --output text
}
finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

# Timeline used to measure "fault injected -> alert in Xora -> RCA proposed"
$logDir = Join-Path $PSScriptRoot '..\results'
New-Item -ItemType Directory -Force $logDir | Out-Null
$timeline = Join-Path $logDir 'timeline.csv'
if (-not (Test-Path $timeline)) { 'utc_time,scenario,instance_id,ssm_command_id' | Out-File $timeline -Encoding utf8 }
"$startedUtc,$Scenario,$instanceId,$commandId" | Out-File $timeline -Append -Encoding utf8
Write-Host "Logged to $timeline" -ForegroundColor DarkGray
