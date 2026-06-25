#Requires -Version 3.0

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[i] Administrator privileges required, requesting..."
    if ($PSCommandPath) {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        $webCommand = "irm https://raw.githubusercontent.com/itsSourCream/zapret-minecraft-fix/main/main.ps1 | iex"
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$webCommand`"" -Verb RunAs
    }
    exit
}

function Pause-Console {
    Write-Host "`nPress Enter to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

$newFilterBlock = '--filter-tcp=25565 --ipset-exclude="%LISTS%ipset-exclude.txt" --dpi-desync-any-protocol=1 --dpi-desync-cutoff=n5 --dpi-desync=multisplit --dpi-desync-split-seqovl=582 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_4pda_to.bin" --new ^'

function Test-ZapretRoot {
    param([string]$dir)
    if (-not (Test-Path (Join-Path $dir "lists") -PathType Container)) {
        return $false
    }
    $batFiles = Get-ChildItem -Path $dir -Filter "general*.bat" -File -ErrorAction SilentlyContinue
    if (-not $batFiles -or $batFiles.Count -eq 0) {
        return $false
    }
    return $true
}

function Find-ByProcess {
    $processes = Get-CimInstance Win32_Process -Filter "name='winws.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $processes) {
        $path = $p.ExecutablePath
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $root = Split-Path (Split-Path $path -Parent) -Parent
            if (Test-ZapretRoot $root) {
                return $root
            }
        }
    }
    return $null
}

function Find-Zapret {
    $p = Find-ByProcess
    if ($p) {
        Write-Host "[i] Found via winws.exe process"
        return $p
    }
    return $null
}

function Test-ZapretServiceRunning {
    $sc = sc.exe query zapret 2>$null
    if ($sc -match "RUNNING") {
        return $true
    }
    return $false
}

function Get-WinwsBatName {
    $tasklist = tasklist.exe /V /FI "IMAGENAME eq winws.exe" /FO CSV /NH 2>$null
    foreach ($line in $tasklist) {
        $idx = $line.IndexOf("zapret: ")
        if ($idx -ge 0) {
            $rest = $line.Substring($idx + 8).Trim('"',"`r","`n"," ")
            if (-not [string]::IsNullOrWhiteSpace($rest)) {
                return $rest
            }
        }
    }
    return $null
}

function Restart-Zapret {
    param([string]$zapret)

    if (Test-ZapretServiceRunning) {
        Write-Host "[i] zapret is running as a service. Restarting it..." -ForegroundColor Cyan
        $null = sc.exe stop zapret
        Start-Sleep -Seconds 2
        $null = sc.exe start zapret
        return "[+] zapret service restarted."
    }

    $batName = Get-WinwsBatName
    if (-not $batName) {
        return "[!] Could not determine which .bat launched winws.exe - restart manually."
    }
    
    $batPath = Join-Path $zapret "$batName.bat"
    if (-not (Test-Path $batPath)) {
        return "[!] File $batPath not found - restart manually."
    }

    $null = taskkill.exe /IM winws.exe /F 2>$null

    Start-Process cmd -ArgumentList "/c start `"`" /D `"$zapret`" `"$batName.bat`"" -WindowStyle Hidden
    
    return "[+] zapret restarted via $batName.bat"
}

function Patch-Bat {
    param([string]$path)
    
    $enc = [System.Text.Encoding]::Default
    $data = [System.IO.File]::ReadAllText($path, $enc)
    $orig = $data
    
    if (-not $data.Contains("--wf-tcp=")) {
        return $false
    }

    $data = [regex]::Replace($data, "--wf-tcp=([^\s\^]+)", {
        param($match)
        $portsStr = $match.Groups[1].Value
        $ports = $portsStr -split ","
        $found = $false
        foreach ($p in $ports) {
            if ($p.Trim() -eq "25565") {
                $found = $true
                break
            }
        }
        if ($found) {
            return $match.Value
        } else {
            return "--wf-tcp=" + $portsStr + ",25565"
        }
    })

    if (-not $data.Contains("--filter-tcp=25565")) {
        $useCRLF = $orig.Contains("`r`n")
        $lines = $data.Replace("`r`n", "`n") -split "`n"
        $outLines = @()
        $inserted = $false
        
        foreach ($ln in $lines) {
            $outLines += $ln
            if (-not $inserted -and $ln.Contains("--wf-tcp=")) {
                $outLines += $newFilterBlock
                $inserted = $true
            }
        }
        
        $joined = $outLines -join "`n"
        if ($useCRLF) {
            $joined = $joined.Replace("`n", "`r`n")
        }
        $data = $joined
    }

    if ($data -eq $orig) {
        return $false
    }
    
    [System.IO.File]::WriteAllText($path, $data, $enc)
    return $true
}

function Run-Script {
    $zapret = Find-Zapret
    if (-not $zapret) {
        Write-Host "[!] Could not find zapret: winws.exe process is not running or not accessible." -ForegroundColor Red
        Write-Host "    Start zapret (service.bat) and try again." -ForegroundColor Red
        return 1
    }
    Write-Host "[+] zapret found: $zapret" -ForegroundColor Green



    $matches = Get-ChildItem -Path $zapret -Filter "general*.bat" -File
    if (-not $matches -or $matches.Count -eq 0) {
        Write-Host "[!] No general*.bat files found in $zapret" -ForegroundColor Red
        return 1
    }

    $patched = 0
    foreach ($f in $matches) {
        try {
            $changed = Patch-Bat $f.FullName
            if ($changed) {
                $patched++
                Write-Host "[+] Patched: $($f.Name)" -ForegroundColor Green
            } else {
                Write-Host "[=] No changes: $($f.Name)" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "[!] $($f.Name): $_" -ForegroundColor Red
        }
    }
    
    Write-Host "`n[i] Files changed: $patched/$($matches.Count)"

    $restartMsg = Restart-Zapret $zapret
    if ($restartMsg -match "^\[!\]") {
        Write-Host $restartMsg -ForegroundColor Red
    } else {
        Write-Host $restartMsg -ForegroundColor Green
    }
    
    return 0
}

$exitCode = Run-Script
Pause-Console
exit $exitCode
