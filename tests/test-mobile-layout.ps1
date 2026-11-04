$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$python = Get-ChildItem `
  -Path (Join-Path $env:LOCALAPPDATA "Programs\Python\Python*\python.exe") `
  -ErrorAction SilentlyContinue |
  Sort-Object FullName -Descending |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $python) { throw "A local Python installation was not found" }
$port = 8765
$chromeProfile = Join-Path ([IO.Path]::GetTempPath()) "cemal-mobile-layout-test-$PID"

function Get-HeadlessDom([string]$url) {
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $chrome
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  foreach ($argument in @(
    "--headless=new",
    "--disable-gpu",
    "--disable-extensions",
    "--no-first-run",
    "--user-data-dir=$chromeProfile",
    "--virtual-time-budget=5000",
    "--dump-dom",
    $url
  )) {
    [void]$startInfo.ArgumentList.Add($argument)
  }

  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $output = $process.StandardOutput.ReadToEnd()
  $errorOutput = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) {
    throw "Chrome exited with code $($process.ExitCode): $errorOutput"
  }
  return $output
}
$server = Start-Process -FilePath $python `
  -ArgumentList "-m", "http.server", "$port", "--bind", "127.0.0.1" `
  -WorkingDirectory $projectRoot `
  -WindowStyle Hidden `
  -PassThru

try {
  $serverReady = $false
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    try {
      Invoke-WebRequest "http://127.0.0.1:$port/" -UseBasicParsing | Out-Null
      $serverReady = $true
      break
    } catch {
      Start-Sleep -Milliseconds 100
    }
  }
  if (-not $serverReady) { throw "Local test server did not start" }

  $failures = @()
  foreach ($width in 320, 375, 768, 1024, 1440) {
    $url = "http://127.0.0.1:$port/tests/mobile-layout.html?width=$width"
    $html = Get-HeadlessDom $url

    $values = @{}
    foreach ($name in "ready", "viewport-width", "scroll-width", "nav-right", "hero-right", "actions-right", "basketball-focal-x", "taekwondo-focal-x", "header-bottom", "basketball-head-y", "taekwondo-head-y") {
      $match = [regex]::Match($html, "data-$name=`"([^`"]+)`"")
      if (-not $match.Success) {
        $previewLength = [Math]::Min(600, $html.Length)
        throw "Missing data-$name for ${width}px viewport. DOM preview: $($html.Substring(0, $previewLength))"
      }
      $values[$name] = $match.Groups[1].Value
    }

    if ($values["ready"] -ne "true") { $failures += "${width}px probe did not finish" }
    if ([double]$values["scroll-width"] -gt [double]$values["viewport-width"]) {
      $failures += "${width}px document overflows: scrollWidth=$($values['scroll-width']), viewport=$($values['viewport-width'])"
    }
    foreach ($element in "nav", "hero", "actions") {
      if ([double]$values["$element-right"] -gt ([double]$values["viewport-width"] + 0.5)) {
        $failures += "${width}px $element exceeds viewport: right=$($values["$element-right"])"
      }
    }
    if ($width -le 375) {
      $safeLeft = [double]$values["viewport-width"] * 0.18
      $safeRight = [double]$values["viewport-width"] * 0.82
      foreach ($scene in "basketball", "taekwondo") {
        $focalX = [double]$values["$scene-focal-x"]
        if ($focalX -lt $safeLeft -or $focalX -gt $safeRight) {
          $failures += "${width}px $scene subject is outside the safe frame: focalX=$focalX, safe=$safeLeft..$safeRight"
        }
      }
      $basketballRight = [double]$values["viewport-width"] * 0.62
      if ([double]$values["basketball-focal-x"] -gt $basketballRight) {
        $failures += "${width}px basketball subject is too far right: focalX=$($values['basketball-focal-x']), max=$basketballRight"
      }
      $minimumHeadY = [double]$values["header-bottom"] + 8
      foreach ($scene in "basketball", "taekwondo") {
        if ([double]$values["$scene-head-y"] -lt $minimumHeadY) {
          $failures += "${width}px $scene head is hidden by the header: headY=$($values["$scene-head-y"]), minimum=$minimumHeadY"
        }
      }
    }
  }

  if ($failures.Count) {
    $failures | ForEach-Object { Write-Output "FAIL: $_" }
    exit 1
  }

  Write-Output "Responsive layout fits at 320px, 375px, 768px, 1024px, and 1440px."
} finally {
  if ($server -and -not $server.HasExited) {
    Stop-Process -Id $server.Id
  }
}
