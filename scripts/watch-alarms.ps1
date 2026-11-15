# Shows the state of every xora-test alarm, refreshing every 30s. Ctrl+C to stop.
param([string]$Region = 'ap-southeast-1', [int]$IntervalSeconds = 30)

while ($true) {
    Clear-Host
    Write-Host "xora-test alarms  $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
    aws cloudwatch describe-alarms --region $Region --alarm-name-prefix xora-test- `
        --query 'MetricAlarms[].[AlarmName,StateValue,StateUpdatedTimestamp]' --output table
    Start-Sleep -Seconds $IntervalSeconds
}
