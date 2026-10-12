[CmdletBinding()]
param(
    [string]$ReleaseDir,

    [string]$OutFile,

    [string]$LauncherDir,

    [string]$VisualStudioPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

if (-not $ReleaseDir) {
    $ReleaseDir = Join-Path $repoRoot 'app\build\windows\x64\runner\Release'
}
if (-not $OutFile) {
    $OutFile = Join-Path $repoRoot 'dist\VMwareLocalizer-portable.exe'
}
if (-not $LauncherDir) {
    $LauncherDir = Join-Path $repoRoot 'tool\launcher'
}

if (-not (Test-Path -LiteralPath $ReleaseDir)) {
    throw "Release directory not found: $ReleaseDir`nBuild it first: cd app; flutter build windows --release"
}

$releaseFull = (Resolve-Path -LiteralPath $ReleaseDir).Path
$entryPoint = Join-Path $releaseFull 'vmware_localizer.exe'
if (-not (Test-Path -LiteralPath $entryPoint)) {
    throw "Entry point not found: $entryPoint"
}

$source = Join-Path $LauncherDir 'launcher.cpp'
if (-not (Test-Path -LiteralPath $source)) {
    throw "Launcher source not found: $source"
}

$resourceScript = Join-Path $LauncherDir 'launcher.rc'
$iconSource = Join-Path $repoRoot 'app\windows\runner\resources\app_icon.ico'
if (-not (Test-Path -LiteralPath $iconSource)) {
    throw "Application icon not found: $iconSource"
}

function Find-VisualStudio {
    param([string]$Hint)

    if ($Hint) {
        if (Test-Path -LiteralPath $Hint) { return (Resolve-Path -LiteralPath $Hint).Path }
        throw "Visual Studio path not found: $Hint"
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $found = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null
        if ($found -and (Test-Path -LiteralPath $found)) {
            return (Resolve-Path -LiteralPath $found).Path
        }
    }

    $roots = @(
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio'),
        ${env:ProgramFiles(x86)},
        'D:\Dev\toolbox'
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($root in $roots) {
        $candidates = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Visual Studio' }
        foreach ($candidate in $candidates) {
            $vcvars = Join-Path $candidate.FullName 'VC\Auxiliary\Build\vcvars64.bat'
            if (Test-Path -LiteralPath $vcvars) { return $candidate.FullName }
        }
    }

    throw "Visual Studio with the C++ toolset was not found. Pass -VisualStudioPath."
}

$vsPath = Find-VisualStudio -Hint $VisualStudioPath
$vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path -LiteralPath $vcvars)) {
    throw "vcvars64.bat not found under $vsPath"
}
Write-Host "Toolchain: $vsPath"

$buildDir = Join-Path $repoRoot 'tool\launcher\build'
if (-not (Test-Path -LiteralPath $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
}
$launcherExe = Join-Path $buildDir 'launcher.exe'
$launcherRes = Join-Path $buildDir 'launcher.res'

# The icon is copied beside the resource script so that the script's relative
# reference resolves; the source of truth stays in the application's resource folder.
Copy-Item -LiteralPath $iconSource -Destination (Join-Path $buildDir 'app_icon.ico') -Force

$buildCmd = Join-Path $buildDir 'compile.cmd'
$clLine = 'cl.exe /nologo /O2 /GS /W4 /WX /EHsc /std:c++17 /DUNICODE /D_UNICODE ' +
    "`"$source`" `"$launcherRes`" /link /SUBSYSTEM:WINDOWS /OUT:`"$launcherExe`" " +
    'user32.lib shell32.lib ole32.lib advapi32.lib'
$rcLine = 'rc.exe /nologo /fo ' + "`"$launcherRes`"" + ' ' + "`"$resourceScript`""
$clCommand = @(
    '@echo off',
    "cd /d `"$buildDir`"",
    "call `"$vcvars`" >nul 2>&1",
    'where rc.exe >nul 2>&1',
    'if errorlevel 1 (echo rc.exe not found on PATH ^(Windows SDK missing^) & exit /b 1)',
    $rcLine,
    'if errorlevel 1 (echo Resource compilation failed & exit /b 1)',
    $clLine,
    'exit /b %ERRORLEVEL%'
) -join "`r`n"
Set-Content -LiteralPath $buildCmd -Value $clCommand -Encoding ASCII

Write-Host 'Compiling the launcher'
Push-Location $buildDir
try {
    $compile = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList @('/c', "`"$buildCmd`"") -Wait -PassThru -NoNewWindow
    if ($compile.ExitCode -ne 0) { throw "Compilation failed (exit code $($compile.ExitCode))" }
}
finally {
    Pop-Location
}
if (-not (Test-Path -LiteralPath $launcherExe)) { throw 'Compilation produced no output' }

$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$outFull = Join-Path (Resolve-Path -LiteralPath $outDir).Path (Split-Path -Leaf $OutFile)

$payloadZip = Join-Path $buildDir 'payload.zip'
if (Test-Path -LiteralPath $payloadZip) { Remove-Item -LiteralPath $payloadZip -Force }

Write-Host "Compressing $releaseFull"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $releaseFull, $payloadZip,
    [System.IO.Compression.CompressionLevel]::Optimal, $false)

$payloadBytes = [System.IO.File]::ReadAllBytes($payloadZip)
$digest = [System.Security.Cryptography.SHA256]::Create().ComputeHash($payloadBytes)

Copy-Item -LiteralPath $launcherExe -Destination $outFull -Force

$stream = [System.IO.File]::Open($outFull, [System.IO.FileMode]::Append,
    [System.IO.FileAccess]::Write)
try {
    $stream.Write($payloadBytes, 0, $payloadBytes.Length)

    $trailer = New-Object System.Collections.Generic.List[byte]
    $trailer.AddRange([System.Text.Encoding]::ASCII.GetBytes('VMWLPK01'))
    $trailer.AddRange([System.BitConverter]::GetBytes([uint64]$payloadBytes.Length))
    $trailer.AddRange($digest)
    $trailer.AddRange([System.BitConverter]::GetBytes([uint32]52))
    $bytes = $trailer.ToArray()
    $stream.Write($bytes, 0, $bytes.Length)
}
finally {
    $stream.Dispose()
}

Remove-Item -LiteralPath $payloadZip -Force -ErrorAction SilentlyContinue

$rawSize = (Get-ChildItem -LiteralPath $releaseFull -Recurse -File |
    Measure-Object -Property Length -Sum).Sum
$finalSize = (Get-Item -LiteralPath $outFull).Length
$hexDigest = ($digest | ForEach-Object { $_.ToString('x2') }) -join ''

Write-Host ''
Write-Host ("  bundle    : {0:N0} bytes ({1:N2} MB)" -f $rawSize, ($rawSize / 1MB))
Write-Host ("  portable  : {0:N0} bytes ({1:N2} MB)" -f $finalSize, ($finalSize / 1MB))
Write-Host ("  ratio     : {0:P0}" -f ($finalSize / $rawSize))
Write-Host ("  payload   : {0:N0} bytes" -f $payloadBytes.Length)
Write-Host ("  payload id: {0}" -f $hexDigest.Substring(0, 16))
Write-Host ''
Write-Host "Done: $outFull"
