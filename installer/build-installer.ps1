[CmdletBinding()]
param(
    [ValidateSet('SurfFile', 'SuperDesigner', 'SuperSpecForge', 'All')]
    [string[]]$App = @('SurfFile'),
    [string]$FlutterPath,
    [string]$IsccPath,
    [string]$RuntimePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent

if (-not $FlutterPath) {
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutter) {
        $FlutterPath = $flutter.Source
    } else {
        $FlutterPath = Join-Path (Split-Path $projectRoot -Parent) 'flutter\bin\flutter.bat'
    }
}
if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    throw 'Flutter introuvable. Precisez -FlutterPath avec le chemin de flutter.bat.'
}

if (-not $IsccPath) {
    $compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($compiler) {
        $IsccPath = $compiler.Source
    } else {
        $candidates = @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
        )
        $IsccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
    }
}
if (-not $IsccPath -or -not (Test-Path -LiteralPath $IsccPath -PathType Leaf)) {
    throw 'Inno Setup 6 introuvable. Installez JRSoftware.InnoSetup ou precisez -IsccPath.'
}

if (-not $RuntimePath) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'Visual Studio introuvable. Precisez -RuntimePath vers les DLL CRT redistribuables x64.'
    }
    $visualStudio = & $vswhere -latest -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $visualStudio) {
        throw 'Les outils Visual C++ x64 sont introuvables.'
    }
    $redistRoot = Join-Path $visualStudio 'VC\Redist\MSVC'
    $versions = @(Get-ChildItem -LiteralPath $redistRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+(\.\d+)?$' } |
        Sort-Object { [version]$_.Name } -Descending)
    foreach ($version in $versions) {
        $crt = Get-ChildItem -Path (Join-Path $version.FullName 'x64\Microsoft.VC*.CRT') `
            -Directory | Select-Object -First 1
        if ($crt) {
            $RuntimePath = $crt.FullName
            break
        }
    }
}
foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not $RuntimePath -or
        -not (Test-Path -LiteralPath (Join-Path $RuntimePath $dll) -PathType Leaf)) {
        throw "Runtime Visual C++ x64 incomplet : $dll. Precisez -RuntimePath."
    }
}

$targets = @{
    SurfFile = @{
        AppRoot        = $projectRoot
        IssFile        = 'SurfFile.iss'
        ExeName        = 'surf_file.exe'
        OutputPrefix   = 'SurfFile'
    }
    SuperDesigner = @{
        AppRoot        = Join-Path $projectRoot 'packages\super_designer'
        IssFile        = 'SuperDesigner.iss'
        ExeName        = 'super_designer.exe'
        OutputPrefix   = 'SuperDesigner'
    }
    SuperSpecForge = @{
        AppRoot        = Join-Path $projectRoot 'packages\super_spec_forge'
        IssFile        = 'SuperSpecForge.iss'
        ExeName        = 'super_spec_forge.exe'
        OutputPrefix   = 'SuperSpecForge'
    }
}

$selectedApps = if ($App -contains 'All') {
    @('SurfFile', 'SuperDesigner', 'SuperSpecForge')
} else {
    @($App | Select-Object -Unique)
}

foreach ($appKey in $selectedApps) {
    $cfg = $targets[$appKey]
    $appRoot = $cfg.AppRoot
    $pubspecPath = Join-Path $appRoot 'pubspec.yaml'
    $manifest = Get-Content -LiteralPath $pubspecPath -Raw
    $versionMatch = [regex]::Match($manifest, '(?m)^version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?\s*$')
    if (-not $versionMatch.Success) {
        throw "La version de $pubspecPath doit avoir la forme major.minor.patch[+build]."
    }
    $versionName = $versionMatch.Groups[1].Value
    $hasBuildNumber = $versionMatch.Groups[2].Success
    $buildNumber = if ($hasBuildNumber) { $versionMatch.Groups[2].Value } else { '0' }
    $appVersion = if ($hasBuildNumber) { "$versionName+$buildNumber" } else { $versionName }
    $versionNumber = "$versionName.$buildNumber"

    Write-Host "=== Generation de l'installateur $appKey ($appVersion) ==="
    Push-Location $appRoot
    try {
        & $FlutterPath build windows --release "--build-name=$versionName" "--build-number=$buildNumber"
        if ($LASTEXITCODE -ne 0) {
            throw "La compilation Flutter de $appKey a echoue (code $LASTEXITCODE)."
        }
        $release = Join-Path $appRoot 'build\windows\x64\runner\Release'
        foreach ($file in @($cfg.ExeName, 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat')) {
            if (-not (Test-Path -LiteralPath (Join-Path $release $file) -PathType Leaf)) {
                throw "La compilation Release de $appKey est incomplete : $file."
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $release 'data\flutter_assets') -PathType Container)) {
            throw "Les assets Flutter sont absents de la compilation Release de $appKey."
        }
        & $IsccPath "/DAppVersion=$appVersion" "/DAppVersionNumber=$versionNumber" `
            "/DReleaseDir=$release" "/DRuntimeDir=$RuntimePath" `
            (Join-Path $PSScriptRoot $cfg.IssFile)
        if ($LASTEXITCODE -ne 0) {
            throw "La compilation Inno Setup de $appKey a echoue (code $LASTEXITCODE)."
        }
        $installer = Join-Path $projectRoot "build\installer\$($cfg.OutputPrefix)-$appVersion-windows-x64-setup.exe"
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            throw "L'installateur attendu est introuvable : $installer."
        }
        Write-Host "Installateur cree : $installer"
        Get-FileHash -LiteralPath $installer -Algorithm SHA256
    } finally {
        Pop-Location
    }
}
