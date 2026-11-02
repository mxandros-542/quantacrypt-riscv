$ErrorActionPreference = 'Stop'
$taskRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskZipPath = Join-Path (Split-Path -Parent $taskRoot) 'mldsa44_ibex.zip'
$taskFiles = @()
foreach ($taskDirectory in @('include','src','vendor','examples','platform','tests','docs','tools')) {
  $taskFiles += Get-ChildItem -LiteralPath (Join-Path $taskRoot $taskDirectory) -File -Recurse |
    Where-Object { $_.FullName -notmatch '__pycache__' -and $_.Extension -ne '.pyc' }
}
foreach ($taskName in @('README.md','LICENSE','Makefile','.gitignore',
    'build/ibex/mldsa44_demo.elf','build/ibex/mldsa44_demo.bin',
    'build/ibex/mldsa44_demo.map','build/validation_acvp.json')) {
  $taskFiles += Get-Item -LiteralPath (Join-Path $taskRoot $taskName)
}
Add-Type -AssemblyName System.IO.Compression
$taskStream = [System.IO.File]::Open($taskZipPath, [System.IO.FileMode]::CreateNew)
try {
  $taskArchive = [System.IO.Compression.ZipArchive]::new($taskStream, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($taskFile in $taskFiles) {
      $taskRelative = [System.IO.Path]::GetRelativePath($taskRoot, $taskFile.FullName).Replace('\','/')
      if ($taskRelative.StartsWith('..')) { throw 'Package entry escaped project directory' }
      $taskEntry = $taskArchive.CreateEntry('mldsa44_ibex/' + $taskRelative, [System.IO.Compression.CompressionLevel]::Optimal)
      $taskInput = [System.IO.File]::OpenRead($taskFile.FullName)
      $taskOutput = $taskEntry.Open()
      try { $taskInput.CopyTo($taskOutput) } finally { $taskInput.Dispose(); $taskOutput.Dispose() }
    }
  } finally { $taskArchive.Dispose() }
} finally { $taskStream.Dispose() }
$taskCheck = [System.IO.Compression.ZipFile]::OpenRead($taskZipPath)
try {
  if ($taskCheck.Entries.Count -ne $taskFiles.Count) { throw 'ZIP entry count mismatch' }
  foreach ($taskRequired in @('src/sign_core.c','vendor/dilithium/ntt.c','build/ibex/mldsa44_demo.elf','README.md')) {
    if ($null -eq $taskCheck.GetEntry('mldsa44_ibex/' + $taskRequired)) { throw ('Missing ' + $taskRequired) }
  }
  Write-Output ('Verified ZIP entries: ' + $taskCheck.Entries.Count)
} finally { $taskCheck.Dispose() }
Get-Item -LiteralPath $taskZipPath | Select-Object FullName,Length
Get-FileHash -LiteralPath $taskZipPath -Algorithm SHA256
