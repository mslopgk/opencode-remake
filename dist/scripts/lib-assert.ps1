# 테스트용 어서션. Pester 를 쓰지 않는다 (학생 환경에는 Pester 3.4 뿐이고
# 리포의 bash 테스트와 같은 결을 유지한다).
$script:Pass = 0
$script:Fail = 0

function Assert-Pass([string]$Msg) {
    $script:Pass++
    Write-Host ("  ok   " + $Msg)
}

function Assert-Failure([string]$Msg) {
    $script:Fail++
    Write-Host ("  FAIL " + $Msg) -ForegroundColor Red
}

function Assert-Eq($Actual, $Expected, [string]$Msg) {
    if ($Actual -eq $Expected) { Assert-Pass $Msg }
    else { Assert-Failure ("$Msg (기대='$Expected' 실제='$Actual')") }
}

function Assert-True($Condition, [string]$Msg) {
    if ($Condition) { Assert-Pass $Msg } else { Assert-Failure $Msg }
}

function Assert-Contains([string]$Haystack, [string]$Needle, [string]$Msg) {
    if ($null -ne $Haystack -and $Haystack.Contains($Needle)) { Assert-Pass $Msg }
    else { Assert-Failure ("$Msg ('$Needle' 없음)") }
}

function Assert-NotContains([string]$Haystack, [string]$Needle, [string]$Msg) {
    if ($null -eq $Haystack -or -not $Haystack.Contains($Needle)) { Assert-Pass $Msg }
    else { Assert-Failure ("$Msg ('$Needle' 가 있으면 안 됨)") }
}

function Assert-FileExists([string]$Path, [string]$Msg) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { Assert-Pass $Msg }
    else { Assert-Failure ("$Msg (파일 없음: $Path)") }
}

function Test-Summary {
    Write-Host ""
    Write-Host ("{0} passed, {1} failed" -f $script:Pass, $script:Fail)
    return ($script:Fail -eq 0)
}
