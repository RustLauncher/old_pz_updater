param(
    [Parameter(Mandatory=$true)][string]$Profile,
    [Parameter(Mandatory=$true)][string]$World,
    [string]$Mode='Sandbox',
    [switch]$ConfirmDrPepperOnlyHistory
)
if (-not $ConfirmDrPepperOnlyHistory) { throw 'You must explicitly confirm that this world NEVER used MoreDamagedObjects. The current mod list is not a history record. Do not guess.' }

$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($World) -or [string]::IsNullOrWhiteSpace($Mode) -or $World -match '[/\\:]' -or $Mode -match '[/\\:]' -or $World -in @('.','..') -or $Mode -in @('.','..')) { throw 'Use save names, not paths, for World and Mode.' }
if ($Mode -eq 'Multiplayer') { $Mode='Multiplayer' }
if ($Mode -eq 'Multiplayer' -and $World -notmatch '^[A-Za-z0-9_-]+$') { throw 'For Multiplayer, World must be the exact server configuration name (letters, digits, underscores or hyphens), not a path, address or launch argument.' }

function Assert-GameStopped {
    $processes=@(Get-Process -Name java,javaw,ProjectZomboid* -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        $processPath=$null
        try { $processPath=$process.Path } catch { }
        if ($process.ProcessName -match '^ProjectZomboid') { throw ('Close Project Zomboid completely before preparing a save. Running process: '+$process.ProcessName+' (PID '+$process.Id+').') }
        if ([string]::IsNullOrWhiteSpace($processPath)) { throw ('Cannot verify that the game/server is stopped: the executable path of '+$process.ProcessName+' (PID '+$process.Id+') is inaccessible. Close that Java process, or rerun with permission to inspect it, before making an offline backup.') }
        if ($processPath -match 'ProjectZomboid') { throw ('Close Project Zomboid and its server completely before preparing a save. Running Java process: PID '+$process.Id+'.') }
        $commandLine=$null
        try { $commandLine=(Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId = '+$process.Id) -ErrorAction Stop).CommandLine } catch { }
        if ([string]::IsNullOrWhiteSpace($commandLine)) { throw ('Cannot verify that the game/server is stopped: the command line of '+$process.ProcessName+' (PID '+$process.Id+') is inaccessible. Close that Java process before making an offline backup.') }
        if ($commandLine -match 'ProjectZomboid|projectzomboid\.jar|zombie\.(network\.GameServer|GameWindow)') { throw ('Close the Project Zomboid server completely before preparing a save. Running Java process: PID '+$process.Id+'.') }
    }
}
function Assert-NoLinks([string]$folder) {
    $entries=@(Get-Item -LiteralPath $folder -Force)+@(Get-ChildItem -LiteralPath $folder -Recurse -Force)
    if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) { throw 'A save contains a link/junction. Refusing an incomplete or redirected backup.' }
}
function Get-SHA256Hash([string]$file) {
    $algorithm=[Security.Cryptography.SHA256]::Create()
    $stream=[IO.File]::OpenRead($file)
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','') } finally { $stream.Dispose(); $algorithm.Dispose() }
}
function Copy-VerifiedFolder([string]$source,[string]$destination) {
    $sourceFiles=@(Get-ChildItem -LiteralPath $source -File -Recurse -Force)
    $expectedHashes=@{}
    foreach ($file in $sourceFiles) { $expectedHashes[$file.FullName]=Get-SHA256Hash $file.FullName }
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
    $remainingSourceFiles=@(Get-ChildItem -LiteralPath $source -File -Recurse -Force)
    $copiedFiles=@(Get-ChildItem -LiteralPath $destination -File -Recurse -Force)
    if ($sourceFiles.Count -ne $copiedFiles.Count -or $sourceFiles.Count -ne $remainingSourceFiles.Count) { throw 'Backup file count changed or does not match. No preparation index was written.' }
    foreach ($file in $sourceFiles) {
        $relative=$file.FullName.Substring($source.Length).TrimStart([char[]]@('\','/'))
        $copy=Join-Path $destination $relative
        if (-not (Test-Path -LiteralPath $copy -PathType Leaf) -or (Get-SHA256Hash $file.FullName) -ne $expectedHashes[$file.FullName] -or (Get-SHA256Hash $copy) -ne $expectedHashes[$file.FullName]) { throw 'Backup verification failed or a source file changed. No preparation index was written; leave the server/game stopped.' }
    }
}
function Get-HexName([string]$value) { return ([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($value))).Replace('-','').ToLowerInvariant() }
function Write-PreparationIndex([string]$file,[string[]]$lines) {
    $stream=[IO.File]::Open($file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $bytes=[Text.Encoding]::UTF8.GetBytes(($lines -join "`r`n")+"`r`n")
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush()
    } finally { $stream.Dispose() }
}

Assert-GameStopped
$profilePath=(Resolve-Path -LiteralPath $Profile).Path
$saveRoot=Join-Path $profilePath 'Saves'
# Resolve names through enumeration: Windows path lookup accepts a different case,
# while the runtime preparation key preserves the exact mode/world spelling.
$modeMatches=@(Get-ChildItem -LiteralPath $saveRoot -Directory -Force | Where-Object { [string]::Equals($_.Name,$Mode,[StringComparison]::OrdinalIgnoreCase) })
if ($modeMatches.Count -ne 1) { throw 'Selected save mode is missing or ambiguous.' }
$modeDirectory=$modeMatches[0]
$worldMatches=@(Get-ChildItem -LiteralPath $modeDirectory.FullName -Directory -Force | Where-Object { [string]::Equals($_.Name,$World,[StringComparison]::OrdinalIgnoreCase) })
if ($worldMatches.Count -ne 1) { throw 'Selected save world is missing or ambiguous.' }
if ($Mode -ne 'Multiplayer') {
    $Mode=$modeDirectory.Name
    $World=$worldMatches[0].Name
}
# Multiplayer keeps the supplied exact server identity for its existing history guard.
$savePath=(Resolve-Path -LiteralPath $worldMatches[0].FullName).Path.TrimEnd([char[]]@('\','/'))
if (-not $savePath.StartsWith($saveRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Save is outside the selected profile.' }
Assert-NoLinks $savePath
$serverFiles=@()
if ($Mode -eq 'Multiplayer') {
    foreach ($required in @('map_meta.bin','map_t.bin','WorldDictionary.bin','global_mod_data.bin')) {
        if (-not (Test-Path -LiteralPath (Join-Path $savePath $required) -PathType Leaf)) { throw ('Not a complete server world: missing '+$required+'. Select the server profile and exact server name, not a client cache.') }
    }
    $serverFolder=Join-Path $profilePath 'Server'
    $serverConfig=Join-Path $serverFolder ($World+'.ini')
    if (-not (Test-Path -LiteralPath $serverConfig -PathType Leaf)) { throw 'Missing Server/<World>.ini. World must match the server configuration name exactly.' }
    $modLines=@(Get-Content -LiteralPath $serverConfig | Where-Object { $_ -match '^\s*Mods\s*=' })
    if ($modLines.Count -ne 1) { throw 'Server configuration must contain exactly one Mods= line.' }
    $savedMods=@(($modLines[0] -replace '^\s*Mods\s*=','').Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($suffix in @('.ini','_SandboxVars.lua','_spawnpoints.lua','_spawnregions.lua')) {
        $name=$World+$suffix
        $file=Join-Path $serverFolder $name
        if (Test-Path -LiteralPath $file -PathType Leaf) { $serverFiles+=,[pscustomobject]@{Source=$file;Relative=('Server/'+$name)} }
    }
    foreach ($suffix in @('.db','.db-wal','.db-shm','.db-journal')) {
        $file=Join-Path (Join-Path $profilePath 'db') ($World+$suffix)
        if (Test-Path -LiteralPath $file -PathType Leaf) { $serverFiles+=,[pscustomobject]@{Source=$file;Relative=('db/'+$World+$suffix)} }
    }
    foreach ($file in $serverFiles) { if ((Get-Item -LiteralPath $file.Source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Server configuration/database is a link. Refusing a redirected backup.' } }
} else {
    if (-not (Test-Path -LiteralPath (Join-Path $savePath 'map_ver.bin') -PathType Leaf)) { throw 'Not a saved world.' }
    $savedMods=Get-Content -LiteralPath (Join-Path $savePath 'mods.txt') -Raw
}
$history=Get-Content -LiteralPath (Join-Path $savePath 'WorldDictionaryLog.lua') -Raw
if ($Mode -eq 'Multiplayer') {
    $recordedWorlds=@([regex]::Matches($history,'saveWorld\s*=\s*"([^"\r\n]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if ($recordedWorlds.Count -ne 1 -or $recordedWorlds[0] -cne $World) { throw 'Server history does not match the exact World/configuration name. Do not prepare a renamed or mismatched world automatically.' }
}

if ($Mode -eq 'Multiplayer') {
    if ($savedMods -notcontains 'DrPepperFridge' -or $savedMods -contains 'MoreDamagedObjects') { throw 'The selected server configuration is not currently Dr-Pepper-only. Mixed worlds need individual recovery.' }
    if ($history -notmatch 'DrPepperFridge' -or $history -notmatch 'type\s*=\s*"info"' -or $history -notmatch 'itemMods' -or $history -notmatch 'pz-vanilla') { throw 'Missing or incomplete retained server history cannot confirm legacy Dr Pepper use.' }
} elseif ($savedMods -notmatch 'DrPepperFridge' -or $savedMods -match 'MoreDamagedObjects') { throw 'This is not a verified Dr-Pepper-only source. Mixed worlds need individual recovery.' }
if ($history -match 'MoreDamagedObjects') { throw 'MDO was found in world history. Refusing ambiguous migration.' }
$mapFolder=Join-Path $savePath 'map'
$chunks=@(Get-ChildItem -LiteralPath $mapFolder -File -Recurse -Filter '*.bin' | ForEach-Object {
    if ($_.Directory.Parent.FullName -ne $mapFolder -or $_.Directory.Name -notmatch '^(0|-?[1-9]\d*)$' -or $_.BaseName -notmatch '^(0|-?[1-9]\d*)$') { throw 'Unsupported chunk naming or directory layout.' }
    $_.Directory.Name+','+$_.BaseName
})
if ($chunks.Count -eq 0) { throw 'No saved chunks.' }
$backupLabel='-BeforePepperMigration-'

$indexFolder=Join-Path (Join-Path $profilePath 'Lua/DrPepperPosterMigration') (Get-HexName $Mode)
$indexFile=Join-Path $indexFolder ((Get-HexName $World)+'.txt')
if (Test-Path -LiteralPath $indexFile) { throw 'Preparation index already exists. Never regenerate it after adding a conflicting mod.' }
$backup=Join-Path (Split-Path -Parent $savePath) ($World+$backupLabel+(Get-Date -Format 'yyyyMMdd-HHmmss'))
$serverBackup=$null
if (Test-Path -LiteralPath $backup) { throw 'Backup already exists.' }
if ($serverFiles.Count -gt 0) { $serverBackup=$backup+'-ServerFiles'; if (Test-Path -LiteralPath $serverBackup) { throw 'Server configuration backup already exists.' } }
Assert-GameStopped
Copy-VerifiedFolder $savePath $backup
if ($serverBackup) {
    foreach ($file in $serverFiles) {
        $destination=Join-Path $serverBackup $file.Relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.Source -Destination $destination -Force
        if ((Get-SHA256Hash $file.Source) -ne (Get-SHA256Hash $destination)) { throw 'Server configuration/database backup verification failed. No preparation index was written.' }
    }
}
Assert-GameStopped
New-Item -ItemType Directory -Path $indexFolder -Force | Out-Null

$uniqueChunks=@($chunks | Sort-Object -Unique)
$lines=@('DrPepperPosterMigration-v2','source=legacy-dr-only',('world='+(Get-HexName $Mode)+'/'+(Get-HexName $World)),('chunks='+$uniqueChunks.Count))+$uniqueChunks+@('end='+$uniqueChunks.Count)
Write-PreparationIndex $indexFile $lines
[pscustomobject]@{Source=$savePath;Backup=$backup;ServerFilesBackup=$serverBackup;ServerFilesBackedUp=$serverFiles.Count;Index=$indexFile;Chunks=$uniqueChunks.Count;BinarySaveFilesModified=$false;HistoryConfirmedByUser=$true;CurrentModListIsHistoryProof=$false} | ConvertTo-Json
