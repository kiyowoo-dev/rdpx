$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Hanya jalan sekali per sesi
$flag = "C:\setup\done.flag"
if (Test-Path $flag) { exit }
Start-Transcript -Path "C:\setup\user-setup.log" -Force | Out-Null

$desktop = [Environment]::GetFolderPath("Desktop")

# ===== AUTO-CLICKER (Next / Install / Finish) =====
$clickerPath = "$env:TEMP\autoclick.ps1"
@'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$procRegex = '^(unins\d*|_iu.*|_is.*|Un_A.*|Uninstall.*|helper|AntigravityIDE.*|Antigravity IDE.*|RobloxStudioInstaller.*|setup)$'
$btnRegex  = '^(Next|Install|Uninstall|Finish|Done|Yes|OK|Continue|I Agree|Agree|Accept)\b'
$AE = [Windows.Automation.AutomationElement]
$ctBtn   = New-Object Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
$ctRadio = New-Object Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [Windows.Automation.ControlType]::RadioButton)
$desc = [Windows.Automation.TreeScope]::Descendants
while ($true) {
    try {
        $wins = $AE::RootElement.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
        foreach ($w in $wins) {
            $pn = (Get-Process -Id $w.Current.ProcessId -ErrorAction SilentlyContinue).ProcessName
            if (-not $pn -or $pn -notmatch $procRegex) { continue }
            foreach ($r in $w.FindAll($desc, $ctRadio)) {
                if (($r.Current.Name -replace '&','') -match '^I accept') {
                    $sp = $r.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
                    if (-not $sp.Current.IsSelected) { $sp.Select() }
                }
            }
            foreach ($b in $w.FindAll($desc, $ctBtn)) {
                $n = $b.Current.Name -replace '&',''
                if ($b.Current.IsEnabled -and $n -match $btnRegex) {
                    $b.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
                    break
                }
            }
        }
    } catch {}
    Start-Sleep -Milliseconds 800
}
'@ | Set-Content -Path $clickerPath -Encoding UTF8

$clickerProc = Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File",$clickerPath -PassThru

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

# ===== ANTIGRAVITY IDE =====
Write-Host "Install Antigravity IDE"
$agUrl = "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/windows-x64/Antigravity%20IDE.exe"
$agInstaller = "$env:TEMP\AntigravityIDE.exe"
try {
    Invoke-WebRequest -Uri $agUrl -OutFile $agInstaller -UseBasicParsing -ErrorAction Stop
    Start-Process $agInstaller -ArgumentList "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /MERGETASKS=!runcode" -Wait
    Start-Sleep 5
    Remove-Item $agInstaller -Force -ErrorAction SilentlyContinue
} catch { Write-Host "Gagal Antigravity: $_" }

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
function Find-Studio {
    Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Filter "RobloxStudioBeta.exe" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
$studio = Find-Studio
$installerPath = "$env:TEMP\RobloxStudioInstaller.exe"
foreach ($url in @(
    "https://raw.githubusercontent.com/oyy-gus/setup-windows/master/installer/RobloxStudioInstaller.exe",
    "https://setup.rbxcdn.com/RobloxStudioInstaller.exe")) {
    if ($studio) { break }
    try {
        Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        if ((Get-Item $installerPath).Length -lt 100000) { throw "Installer tidak valid." }
        $p = Start-Process $installerPath -PassThru
        $p.WaitForExit(300000) | Out-Null
        for ($i = 0; $i -lt 60 -and -not $studio; $i++) { Start-Sleep 5; $studio = Find-Studio }
    } catch { Write-Host "Gagal dari $url : $_" }
}
Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
if ($studio) {
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktop\Roblox Studio.lnk")
    $s.TargetPath = $studio.FullName; $s.IconLocation = "$($studio.FullName),0"; $s.Save()
}

# ===== SELESAI =====
if ($clickerProc -and -not $clickerProc.HasExited) { Stop-Process -Id $clickerProc.Id -Force -ErrorAction SilentlyContinue }
Remove-Item $clickerPath -Force -ErrorAction SilentlyContinue
New-Item $flag -ItemType File -Force | Out-Null
Stop-Transcript | Out-Null
