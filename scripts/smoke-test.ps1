<#
.SYNOPSIS
  UC0 smoke test: check that the CloudWatch -> SNS -> Xora Resolve path works without waiting for real metrics.

.DESCRIPTION
  -Mode SetAlarmState (default): briefly forces a real alarm to ALARM, so a genuine CloudWatch
                                 notification goes through SNS. CloudWatch sets it back on its next evaluation.
  -Mode RawPublish             : publishes a hand-made CloudWatch-style alarm JSON straight to the SNS topic.

.EXAMPLE
  .\smoke-test.ps1
  .\smoke-test.ps1 -Mode RawPublish -State OK
#>
param(
    [ValidateSet('SetAlarmState', 'RawPublish')]
    [string]$Mode = 'SetAlarmState',

    [ValidateSet('ALARM', 'OK')]
    [string]$State = 'ALARM',

    [string]$AlarmName = 'xora-test-cpu-high',
    [string]$Region = 'ap-southeast-1'
)

$ErrorActionPreference = 'Stop'
$tfDir = Join-Path $PSScriptRoot '..\terraform'

if ($Mode -eq 'SetAlarmState') {
    aws cloudwatch set-alarm-state --region $Region --alarm-name $AlarmName `
        --state-value $State --state-reason "Xora Resolve connector smoke test (manual set-alarm-state)"
    if ($LASTEXITCODE -ne 0) { throw 'set-alarm-state failed' }
    Write-Host "Alarm $AlarmName forced to $State. Check Xora Resolve for a new alert or incident." -ForegroundColor Cyan
    return
}

$topicArn   = terraform "-chdir=$tfDir" output -raw sns_topic_arn
$instanceId = terraform "-chdir=$tfDir" output -raw instance_id
$accountId  = aws sts get-caller-identity --query Account --output text
$now        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fff+0000')
$oldState   = if ($State -eq 'ALARM') { 'OK' } else { 'ALARM' }

$message = [ordered]@{
    AlarmName        = 'xora-test-smoke'
    AlarmDescription = 'Synthetic smoke-test alarm for the Xora Resolve CloudWatch connector'
    AWSAccountId     = $accountId
    NewStateValue    = $State
    NewStateReason   = 'Synthetic test: Threshold Crossed: 1 datapoint [95.0] was greater than the threshold (80.0).'
    StateChangeTime  = $now
    Region           = 'Asia Pacific (Singapore)'
    AlarmArn         = "arn:aws:cloudwatch:${Region}:${accountId}:alarm:xora-test-smoke"
    OldStateValue    = $oldState
    Trigger          = [ordered]@{
        MetricName         = 'CPUUtilization'
        Namespace          = 'AWS/EC2'
        StatisticType      = 'Statistic'
        Statistic          = 'AVERAGE'
        Dimensions         = @(@{ name = 'InstanceId'; value = $instanceId })
        Period             = 300
        EvaluationPeriods  = 1
        ComparisonOperator = 'GreaterThanThreshold'
        Threshold          = 80.0
        TreatMissingData   = 'notBreaching'
    }
} | ConvertTo-Json -Depth 5 -Compress

$tmp = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($tmp, $message)
try {
    aws sns publish --region $Region --topic-arn $topicArn `
        --subject "${State}: `"xora-test-smoke`" in Asia Pacific (Singapore)" `
        --message "file://$tmp"
    if ($LASTEXITCODE -ne 0) { throw 'sns publish failed' }
    Write-Host "Raw $State message published to $topicArn" -ForegroundColor Cyan
}
finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}
