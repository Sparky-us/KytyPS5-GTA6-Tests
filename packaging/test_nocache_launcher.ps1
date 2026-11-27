$ErrorActionPreference = 'Stop'
$testRoot = Join-Path $env:RUNNER_TEMP 'Test 01 with spaces'
$patched = Join-Path $testRoot 'patched'
$oldCache = Join-Path $patched '_PipelineCache'
$game = Join-Path $testRoot 'Game & files\Extracted title'
$assets = Join-Path $patched 'assets'
New-Item -ItemType Directory -Force -Path $oldCache, $game, $assets | Out-Null
Set-Content -LiteralPath (Join-Path $game 'eboot.bin') -Value 'Test fixture'
Set-Content -LiteralPath (Join-Path $assets 'asset.txt') -Value 'Test fixture'
Set-Content -LiteralPath (Join-Path $oldCache 'PPSA38500.shaders') -Value 'preserve this shader cache'
Set-Content -LiteralPath (Join-Path $oldCache 'PPSA38500.bin') -Value 'preserve this Vulkan cache'
$saved = Join-Path $testRoot 'game-path.txt'
Set-Content -LiteralPath $saved -Value (Split-Path $game -Parent)
$launcher = Join-Path $testRoot 'Launch-NoCache.ps1'
Copy-Item (Join-Path $PSScriptRoot 'Launch-NoCache.ps1') $launcher
$fakeRuntime = Join-Path $patched 'kyty_emulator.exe'
Add-Type -OutputAssembly $fakeRuntime -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
public static class Fixture {
    public static int Main(string[] args) {
        if (args.Length < 4 || args[0] != "--game" || args[2] != "--printf-direction" || args[3] != "Console") return 8;
        string flags = string.Join(" ", args, 4, args.Length - 4);
        if (flags != (Environment.GetEnvironmentVariable("GTA6_TEST_EXPECT_FLAGS") ?? "")) return 11;
        if (!File.Exists(args[1]) || Path.GetFileName(args[1]) != "eboot.bin") return 9;
        if (Directory.Exists("_PipelineCache") || !File.Exists("assets/asset.txt")) return 10;
        Console.WriteLine("Fixture ran from fresh folder with the correct arguments");
        Console.Error.WriteLine("Fixture stderr captured");
        long pc = Process.GetCurrentProcess().MainModule.BaseAddress.ToInt64() + 4096;
        Console.WriteLine("Unhandled host exception: pc=0x" + pc.ToString("X16"));
        Thread.Sleep(2200);
        return unchecked((int)0xc0000005);
    }
}
'@
$hash = (Get-FileHash -LiteralPath $fakeRuntime -Algorithm SHA256).Hash
foreach ($profile in @('nocache-baseline', 'compat-validate')) {
    $extra = @()
    $env:GTA6_TEST_EXPECT_FLAGS = ''
    if ($profile -eq 'compat-validate') {
        $extra = @('-ValidateCompatShaders')
        $env:GTA6_TEST_EXPECT_FLAGS = '--redzone --guest-tsc --readback-linear-images --readback-tiled-images --readback-storage-images --sync-raw-image-buffers --flush-draws 1 --tessellation --occlusion-queries --shader-validation'
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -RuntimeSha256 $hash -NonInteractive @extra
    if ($LASTEXITCODE -ne -1073741819) { throw "Expected the fixture's access violation exit code, got $LASTEXITCODE" }
    $report = Get-ChildItem (Join-Path $testRoot 'logs') -Filter "$profile-*.txt"
    $content = Get-Content -LiteralPath $report.FullName -Raw
    foreach ($expected in @('Fixture ran from fresh folder with the correct arguments', 'Fixture stderr captured', 'Fault PC module candidate: kyty_emulator.exe+0x1000')) {
        if (!$content.Contains($expected)) { throw "Expected report entry missing: $expected" }
    }
}
if ((Get-Content -LiteralPath (Join-Path $oldCache 'PPSA38500.shaders')) -ne 'preserve this shader cache' -or
    (Get-Content -LiteralPath (Join-Path $oldCache 'PPSA38500.bin')) -ne 'preserve this Vulkan cache') {
    throw 'Existing cache was changed'
}
Write-Host 'PASS: saved path, fresh cache, original cache, process exit, stdout/stderr, and module resolution.'
exit 0
