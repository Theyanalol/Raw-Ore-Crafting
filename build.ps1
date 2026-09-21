#requires -version 5
<#
    Builds the "Raw Ore Crafting" Forge mod for 1.16.5 and 1.20.1.

    Usage:  powershell -ExecutionPolicy Bypass -File .\build.ps1

    Notes:
      * The 1.20.1 build is a data-only mod (lowcodefml), it is only zipped.
      * The 1.16.5 build needs one tiny @Mod class, so a JDK (javac/jar) is
        required. The Forge universal jar is used as compile-only classpath
        and is downloaded into .\tools on first run.
#>
param(
    [string]$ForgeVersion = "1.16.5-36.2.39"
)

$ErrorActionPreference = "Stop"
$root  = $PSScriptRoot
$tools = Join-Path $root "tools"
$dist  = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $tools, $dist | Out-Null

function Test-Javac([string]$dir) {
    if (-not $dir) { return $false }
    return (Test-Path (Join-Path $dir "javac.exe")) -or (Test-Path (Join-Path $dir "javac"))
}

function Get-JdkBin {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME "bin") }

    $java = Get-Command java -ErrorAction SilentlyContinue
    if ($java) {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $props = & $java.Source -XshowSettings:properties -version 2>&1 | Out-String
        $ErrorActionPreference = $prev
        $m = [regex]::Match($props, 'java\.home\s*=\s*(.+)')
        if ($m.Success) { $candidates += (Join-Path $m.Groups[1].Value.Trim() "bin") }
    }

    $candidates += "C:\Program Files\Java\latest\jdk-21\bin"

    foreach ($c in $candidates) {
        if (Test-Javac $c) { return $c }
    }

    $javac = Get-Command javac -ErrorAction SilentlyContinue
    if ($javac) { return (Split-Path $javac.Source) }

    throw "javac not found. Install a JDK 8+ (a JDK is required, a JRE is not enough)."
}

$jdk = Get-JdkBin
$javac = Join-Path $jdk "javac.exe"
$jar   = Join-Path $jdk "jar.exe"

function New-ModJar {
    param([string]$StageDir, [string]$OutFile)
    if (Test-Path $OutFile) { Remove-Item -Force $OutFile }
    & $jar --create --file $OutFile -C $StageDir .
    if ($LASTEXITCODE -ne 0) { throw "jar failed for $OutFile" }
}

# ---------------------------------------------------------------- 1.20.1 (data only)
Write-Host "==> Building 1.20.1 (lowcodefml, data only)" -ForegroundColor Cyan
$stage = Join-Path $tools "stage\1.20.1"
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -Recurse -Force (Join-Path $root "src-1.20.1\resources\*") $stage
New-ModJar -StageDir $stage -OutFile (Join-Path $dist "orecrafting-1.20.1-1.0.0.jar")

# ---------------------------------------------------------------- 1.16.5 (tiny mod class)
Write-Host "==> Building 1.16.5 (javafml)" -ForegroundColor Cyan
$forgeJar = Join-Path $tools "forge-$ForgeVersion-universal.jar"
if (-not (Test-Path $forgeJar)) {
    $url = "https://maven.minecraftforge.net/net/minecraftforge/forge/$ForgeVersion/forge-$ForgeVersion-universal.jar"
    Write-Host "    downloading $url"
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $url -OutFile $forgeJar -TimeoutSec 120
}

$classes = Join-Path $tools "classes\1.16.5"
Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$sources = Get-ChildItem (Join-Path $root "src-1.16.5\java") -Recurse -Filter *.java | ForEach-Object { $_.FullName }
$prev = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $javac --release 8 -Xlint:-options -encoding UTF-8 -cp $forgeJar -d $classes $sources
$javacExit = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($javacExit -ne 0) { throw "javac failed for 1.16.5" }

$stage = Join-Path $tools "stage\1.16.5"
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -Recurse -Force (Join-Path $root "src-1.16.5\resources\*") $stage
Copy-Item -Recurse -Force (Join-Path $classes "*") $stage
New-ModJar -StageDir $stage -OutFile (Join-Path $dist "orecrafting-1.16.5-1.0.0.jar")

Write-Host ""
Write-Host "Done. Output:" -ForegroundColor Green
Get-ChildItem $dist -Filter *.jar | ForEach-Object { Write-Host ("  {0}  ({1:N0} bytes)" -f $_.Name, $_.Length) }
