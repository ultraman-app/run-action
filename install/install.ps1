# Installs Ultraman for this user: the app and the `ultraman` command. No admin rights needed.
#   irm https://ultraman-app.github.io/install.ps1 | iex
# Only the command, for CI:
#   $env:ULTRAMAN_CLI_ONLY = 1; irm https://ultraman-app.github.io/install.ps1 | iex
# A given version: $env:ULTRAMAN_VERSION = '0.1.0'
#
# It runs inside a script block so nothing it defines stays in your session, and it throws instead of calling exit,
# which would close the window you pasted it into.
& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue' # Windows PowerShell's progress bar makes downloads several times slower
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  function Fail([string]$msg) { throw "ultraman: $msg" }

  $os = if ($env:ULTRAMAN_OS) { $env:ULTRAMAN_OS } else { 'windows' }
  if ($os -ne 'windows') { Fail "$os is not supported yet by install.ps1; on macOS and Linux use install.sh" }
  $arch = if ($env:ULTRAMAN_ARCH) { $env:ULTRAMAN_ARCH } elseif ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  if ($arch -notin @('AMD64', 'x64')) { Fail "Windows on $arch is not supported yet (only x64)" }

  $cliOnly = [bool]$env:ULTRAMAN_CLI_ONLY
  $base = if ($env:ULTRAMAN_BASE_URL) { $env:ULTRAMAN_BASE_URL }
          elseif ($env:ULTRAMAN_VERSION) { "https://github.com/ultraman-app/ultraman-app.github.io/releases/download/v$($env:ULTRAMAN_VERSION.TrimStart('v'))" }
          else { 'https://github.com/ultraman-app/ultraman-app.github.io/releases/latest/download' }
  $root = if ($env:ULTRAMAN_INSTALL_ROOT) { $env:ULTRAMAN_INSTALL_ROOT } else { $env:LOCALAPPDATA }
  # Not inside %LOCALAPPDATA%\Ultraman: that's the app's folder, and its uninstaller removes it whole.
  $cliDir = Join-Path $root 'ultraman-cli'
  $cliAsset = 'ultraman-cli-windows-x64.zip'
  $appAsset = 'Ultraman-windows-x64-setup.exe'

  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ultraman-" + [guid]::NewGuid())
  New-Item -ItemType Directory $tmp | Out-Null
  try {
    function Get-Asset([string]$name) {
      $file = Join-Path $tmp $name
      try { Invoke-WebRequest -UseBasicParsing -Uri "$base/$name" -OutFile $file }
      catch { Fail "couldn't download $base/$name ($($_.Exception.Message))" }
      $file
    }

    # .NET's SHA-256 and not Get-FileHash: Windows PowerShell started from PowerShell 7 inherits its module path and
    # can't load Get-FileHash.
    function Get-Sha256([string]$file) {
      $sha = [Security.Cryptography.SHA256]::Create()
      $stream = [IO.File]::OpenRead($file)
      try { -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) } finally { $stream.Dispose(); $sha.Dispose() }
    }

    # Everything is downloaded and checked before anything is touched: a failure leaves the previous install as it was.
    $sums = Get-Content (Get-Asset 'SHA256SUMS')

    # The release's signature: with a release key (scripts/release-key.sh writes it into $releaseKey below; a test or a
    # fork can pass ULTRAMAN_RELEASE_KEY), SHA256SUMS must come signed by its private key. Someone who replaces a release
    # and its checksums without that key can't get it installed.
    $releaseKey = '<RSAKeyValue><Modulus>pgC1Yv14KqDbjGS7St81bq2NQhxJpGqJOXOfjKDmeQRfUWqbHo3y+HDF5rtIrtT9WX7IA+j4IYPUsj77mHyENBXFHjRZDgeqIyFvnRrhFL6XDPdkZGLahWhk20Oz5NWmacWFoO0tKb0t5Eu/wuincBpPsdoFjGM1f23/TIH3BUVQe9hyPtzXM+lGCpUEfACHNW8NWHru6K5REQ6KnFdJdfq6zfEaaplbS3Xq8HGzZhehdRIM7AeWwT6LwGUThjzM0jYpt/Cc4KyKye10upGxjtc5qKs9HXjO5PyMKfVHdPGJKD7WURAXU8nUUWKllmr3osInRSVyQOWts+FfXlKYKGrGFmd09A+Zxj0FN1v9ksBITYlhUvAr0yWyVYDOyKG4eWhIQ3eR9HQsrjIOEnRKKDX6LG2Ujd8uJCIssL1PJ/NKgR+ClbOk4jkVu1ymL6yRk/3ECMAB/qcKFS0LY7Iob1wV8RJcrW18DnEU/eRnXIUwZQKJOWrIpQdTl7Cvv6mx</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
    if ($env:ULTRAMAN_RELEASE_KEY) { $releaseKey = $env:ULTRAMAN_RELEASE_KEY }
    if ($releaseKey) {
      $sig = Join-Path $tmp 'SHA256SUMS.sig'
      try { Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA256SUMS.sig" -OutFile $sig }
      catch { Fail "the release has no signature (SHA256SUMS.sig); nothing was changed" }
      $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
      try {
        $rsa.FromXmlString($releaseKey)
        $valid = $rsa.VerifyData([IO.File]::ReadAllBytes((Join-Path $tmp 'SHA256SUMS')), 'SHA256', [IO.File]::ReadAllBytes($sig))
      } finally { $rsa.Dispose() }
      if (-not $valid) { Fail "SHA256SUMS doesn't carry a valid signature from Ultraman's release key; nothing was changed" }
    }
    function Get-Checked([string]$name) {
      $file = Get-Asset $name
      $line = $sums | Where-Object { ($_ -split '\s+', 2)[1] -replace '^\*', '' -eq $name } | Select-Object -First 1
      if (-not $line) { Fail "$name isn't in SHA256SUMS" }
      if ((Get-Sha256 $file) -ne ($line -split '\s+')[0]) { Fail "${name}: the checksum doesn't match; nothing was changed" }
      $file
    }
    $cliZip = Get-Checked $cliAsset
    $setup = if ($cliOnly) { $null } else { Get-Checked $appAsset }

    Write-Output 'Installing Ultraman...'
    # The CLI: unpacked next to the old one, then swapped. The system's tar is much faster than Expand-Archive.
    New-Item -ItemType Directory -Force $root | Out-Null
    $new = "$cliDir.new"
    $old = "$cliDir.old"
    foreach ($d in @($new, $old)) { if (Test-Path $d) { Remove-Item -Recurse -Force $d } }
    New-Item -ItemType Directory $new | Out-Null
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tar) { & $tar -xf $cliZip -C $new; if ($LASTEXITCODE) { Fail "couldn't unpack $cliAsset" } }
    else { Expand-Archive -Path $cliZip -DestinationPath $new }
    if (Test-Path $cliDir) { Rename-Item $cliDir (Split-Path $old -Leaf) }
    Rename-Item $new (Split-Path $cliDir -Leaf)
    if (Test-Path $old) { Remove-Item -Recurse -Force $old }

    if ($setup) {
      # Tauri's NSIS installer, per user and silent.
      $p = Start-Process -FilePath $setup -ArgumentList '/S' -Wait -PassThru
      if ($p.ExitCode) { Fail "the app's installer ended with code $($p.ExitCode)" }
    }

    # The command on the PATH. Under GitHub Actions, for the next steps; otherwise the user's PATH, kept as an
    # expandable string so entries like %USERPROFILE%\bin keep working.
    if ($env:GITHUB_PATH) {
      # Without a BOM: Windows PowerShell's Add-Content -Encoding utf8 writes one, and the runner would read it as part of the path.
      [IO.File]::AppendAllText($env:GITHUB_PATH, "$cliDir`n")
    } else {
      $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
      $raw = [string]$key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
      if (($raw -split ';') -notcontains $cliDir) {
        $key.SetValue('Path', ((@($raw.TrimEnd(';'), $cliDir) | Where-Object { $_ }) -join ';'), 'ExpandString')
        # Setting any user variable makes Windows tell new terminals that the environment changed.
        [Environment]::SetEnvironmentVariable('ULTRAMAN_INSTALLED', '1', 'User')
      }
      $key.Close()
    }
    $env:Path = "$env:Path;$cliDir"

    $installed = (& (Join-Path $cliDir 'ultraman.cmd') --version) -replace '^ultraman ', ''
    if ($LASTEXITCODE) { Fail "the installed command doesn't run" }
    Write-Output "Ultraman $installed installed."
    if (-not $cliOnly) { Write-Output '  app:     Start menu > Ultraman' }
    Write-Output "  command: $cliDir\ultraman.cmd (open a new terminal and run: ultraman --version)"
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}
