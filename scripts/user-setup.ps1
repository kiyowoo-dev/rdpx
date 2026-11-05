$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Penanda dibuat di AWAL supaya tidak jalan berulang
$flag = "C:\setup\done.flag"
if (Test-Path $flag) { exit }
New-Item $flag -ItemType File -Force | Out-Null
Start-Transcript -Path "C:\setup\user-setup.log" -Force | Out-Null

$desktop = [Environment]::GetFolderPath("Desktop")

# ===== PINDAHKAN REPO HASIL CLONE KE DESKTOP USER INI =====
Get-ChildItem "C:\setup\repos" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $target = Join-Path $desktop $_.Name
    if (-not (Test-Path $target)) { Move-Item $_.FullName $target -Force }
}

# ===== DARK MODE (broadcast agar langsung terlihat) =====
$reg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
if (!(Test-Path $reg)) { New-Item -Path $reg -Force | Out-Null }
Set-ItemProperty $reg -Name AppsUseLightTheme -Value 0
Set-ItemProperty $reg -Name SystemUsesLightTheme -Value 0
Set-ItemProperty $reg -Name ColorPrevalence -Value 0 -ErrorAction SilentlyContinue
Add-Type -Namespace Win32 -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
$res = [UIntPtr]::Zero
[Win32.Native]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "ImmersiveColorSet", 2, 5000, [ref]$res) | Out-Null

# ===== VISUAL EFFECTS (mode Custom, sesuai screenshot) =====
Add-Type -Namespace Win32 -Name Spi -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint a, uint b, IntPtr c, uint d);
'@
# Nilai BOOL dikirim lewat pvParam, kecuali 0x0025 dan 0x004B yang lewat uiParam
function Set-Spi([uint32]$code, [bool]$on) {
    $v = [int]$on
    if ($code -eq 0x0025 -or $code -eq 0x004B) {
        [Win32.Spi]::SystemParametersInfo($code, [uint32]$v, [IntPtr]::Zero, 3) | Out-Null
    } else {
        [Win32.Spi]::SystemParametersInfo($code, 0, [IntPtr]$v, 3) | Out-Null
    }
}
Set-Spi 0x0025 $true    # Show window contents while dragging
Set-Spi 0x1005 $true    # Slide open combo boxes
Set-Spi 0x1007 $true    # Smooth-scroll list boxes
Set-Spi 0x004B $true    # Smooth edges of screen fonts
Set-Spi 0x1043 $false   # Animate controls and elements inside windows
Set-Spi 0x1003 $false   # Menu animation
Set-Spi 0x1013 $false   # Fade or slide menus into view
Set-Spi 0x1017 $false   # Tooltip animation
Set-Spi 0x1019 $false   # Fade or slide ToolTips into view
Set-Spi 0x1015 $false   # Fade out menu items after clicking
Set-Spi 0x101B $false   # Shadows under mouse pointer
Set-Spi 0x1025 $false   # Shadows under windows

function Set-Reg($path, $name, $value, $type = "DWord") {
    if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
    Set-ItemProperty $path -Name $name -Value $value -Type $type
}
$adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" VisualFXSetting 3
Set-Reg $adv TaskbarAnimations 0
Set-Reg $adv ListviewAlphaSelect 1
Set-Reg $adv ListviewShadow 0
Set-Reg $adv IconsOnly 0
Set-Reg "HKCU:\Software\Microsoft\Windows\DWM" EnableAeroPeek 1
Set-Reg "HKCU:\Software\Microsoft\Windows\DWM" AlwaysHibernateThumbnails 0
Set-Reg "HKCU:\Control Panel\Desktop\WindowMetrics" MinAnimate "0" "String"

# ===== ANTIGRAVITY IDE =====
Write-Host "Install Antigravity IDE"
$already = Get-ChildItem "$env:LOCALAPPDATA\Programs", $env:ProgramFiles -Directory -Filter "Antigravity*" -ErrorAction SilentlyContinue
if (-not $already) {
    $agUrl = "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/windows-x64/Antigravity%20IDE.exe"
    $agInstaller = "$env:TEMP\AntigravityIDE.exe"
    try {
        Invoke-WebRequest -Uri $agUrl -OutFile $agInstaller -UseBasicParsing -ErrorAction Stop
        Start-Process $agInstaller -ArgumentList "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /MERGETASKS=!runcode" -Wait
        Start-Sleep 5
        Remove-Item $agInstaller -Force -ErrorAction SilentlyContinue
    } catch { Write-Host "Gagal Antigravity: $_" }
} else {
    Write-Host "Antigravity sudah terpasang, dilewati."
}

$agExe = $null
foreach ($root in @("$env:LOCALAPPDATA\Programs", $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if (Test-Path $root) {
        $agExe = Get-ChildItem $root -Directory -Filter "Antigravity*" -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ChildItem $_.FullName -Filter "Antigravity*.exe" -File -ErrorAction SilentlyContinue } |
            Where-Object { $_.Name -notmatch "unins|update|setup" } |
            Select-Object -First 1 -ExpandProperty FullName
        if ($agExe) { break }
    }
}
if ($agExe) {
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktop\Antigravity IDE.lnk")
    $s.TargetPath = $agExe; $s.IconLocation = "$agExe,0"; $s.Save()
}

# ===== ROBLOX STUDIO =====
Write-Host "Install Roblox Studio"
$versionsDir = "$env:LOCALAPPDATA\Roblox\Versions"

function Find-Studio {
    Get-ChildItem $versionsDir -Filter "RobloxStudioBeta.exe" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# Hanya untuk log: versi terbaru dari Roblox (tidak dipakai untuk memasang ulang)
try {
    $latest = (Invoke-RestMethod "https://clientsettingscdn.roblox.com/v2/client-version/WindowsStudio64" `
        -UseBasicParsing -TimeoutSec 20).clientVersionUpload
    Write-Host "Versi Studio terbaru menurut Roblox: $latest"
} catch { $latest = $null }

$installerPath = "$env:TEMP\RobloxStudioInstaller.exe"
$sources = @(
    "https://raw.githubusercontent.com/oyy-gus/setup-windows/master/installer/RobloxStudioInstaller.exe"
)

$studio = Find-Studio
if (-not $studio) {
    foreach ($url in $sources) {
        # Hanya satu sumber: installer dari repo setup-windows
        try {
            Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
            if ((Get-Item $installerPath).Length -lt 100000) { throw "Installer tidak valid." }
        } catch {
            Write-Host "Gagal mengunduh dari $url : $_"
            continue
        }

        Write-Host "Menjalankan installer dari $url (satu kali)"
        $null = Start-Process $installerPath -PassThru

        # Tunggu sampai Studio terpasang dan installer selesai (maks 15 menit)
        $deadline = (Get-Date).AddMinutes(15)
        $foundAt = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep 5
            if (-not $studio) { $studio = Find-Studio }
            if ($studio) {
                if (-not $foundAt) { $foundAt = Get-Date }
                $busy = Get-Process RobloxStudioInstaller -ErrorAction SilentlyContinue
                if (-not $busy -or ((Get-Date) - $foundAt).TotalSeconds -gt 60) { break }
            }
        }
        break   # installer sudah dijalankan; jangan coba sumber lain
    }
} else {
    Write-Host "Roblox Studio sudah terpasang, dilewati."
}
Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

# Pastikan user ini bisa menulis ke folder Roblox (untuk auto-update)
icacls "$env:LOCALAPPDATA\Roblox" /grant "${env:USERNAME}:(OI)(CI)F" /T /C 2>$null | Out-Null

$studio = Find-Studio
if ($studio) {
    $launcher = Get-ChildItem $versionsDir -Filter "RobloxStudioLauncherBeta.exe" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $target = if ($launcher) { $launcher.FullName } else { $studio.FullName }
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktop\Roblox Studio.lnk")
    $s.TargetPath = $target; $s.IconLocation = "$($studio.FullName),0"; $s.Save()
    Write-Host "Roblox Studio siap."
} else {
    Write-Host "Roblox Studio GAGAL terpasang."
}

# ===== SELESAI =====
Stop-Transcript | Out-Null
