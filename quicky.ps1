# SAP Quick Logon
$JsonFile = "$env:APPDATA\SAP\Common\sap-systems.json"

function Get-PathFromShortcut {
    param([string]$LnkPath)

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($LnkPath)
        return $shortcut.TargetPath
    } catch {
        return $null
    }
}

function Find-SapShcut {
    # 1. Try common default install paths (64-bit and 32-bit)
    $candidates = @(
        "${env:ProgramFiles}\SAP\FrontEnd\SAPgui\sapshcut.exe",
        "${env:ProgramFiles(x86)}\SAP\FrontEnd\SAPgui\sapshcut.exe"
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) { return $found }

    # 2. Resolve via Start Menu shortcut(s) under "SAP Front End"
    $shortcutFolder = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SAP Front End"
    if (Test-Path $shortcutFolder) {
        $lnkFiles = Get-ChildItem -Path $shortcutFolder -Filter "*.lnk" -ErrorAction SilentlyContinue

        foreach ($lnk in $lnkFiles) {
            $targetPath = Get-PathFromShortcut -LnkPath $lnk.FullName
            if (-not $targetPath) { continue }

            # If the shortcut itself points to sapshcut.exe, use it directly
            if ($targetPath -match 'sapshcut\.exe$' -and (Test-Path $targetPath)) { return $targetPath }

            # Otherwise, the shortcut likely points to saplogon.exe (or similar)
            # sapshcut.exe normally lives in the same install folder
            $installDir = Split-Path -Path $targetPath -Parent
            $candidate = Join-Path $installDir "sapshcut.exe"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    # 3. Try registry (SAP GUI install path)
    $regPaths = @(
        "HKLM:\SOFTWARE\SAP\SAP Shared\SAPGUI Frontend",
        "HKLM:\SOFTWARE\WOW6432Node\SAP\SAP Shared\SAPGUI Frontend"
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $installDir = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallDir
            if ($installDir) {
                $candidate = Join-Path $installDir "sapshcut.exe"
                if (Test-Path $candidate) { return $candidate }
            }
        }
    }

    # 4. Try PATH environment variable
    $inPath = Get-Command "sapshcut.exe" -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    return $null
}

$SapShcut = Find-SapShcut

if (-not $SapShcut) {
    Write-Host "  sapshcut.exe could not be found automatically." -ForegroundColor Red
    Write-Host "  Please enter the full path to sapshcut.exe manually," -ForegroundColor Yellow
    Write-Host "  or press Enter to exit." -ForegroundColor Yellow
    $manualPath = Read-Host "  Path"

    if (-not $manualPath -or -not (Test-Path $manualPath)) {
        Write-Host "  Invalid path. Exiting." -ForegroundColor Red
        exit 1
    }
    $SapShcut = $manualPath
}

if (-not (Test-Path $JsonFile)) {
    Write-Host "  File not found: $JsonFile" -ForegroundColor Red
    exit 1
}

$systems = Get-Content $JsonFile -Raw | ConvertFrom-Json

function Build-ConnString {
    param($sys)

    # Only prepend sapRouter when it actually has a value
    if ($sys.sapRouter -and $sys.sapRouter.Trim() -ne "") {
        return "$($sys.sapRouter)/H/$($sys.host)/S/$($sys.port)"
    }
    return "/H/$($sys.host)/S/$($sys.port)"
}

function Test-IsFavoriteClient {
    param($sys, [string]$clientValue)

    if (-not $sys.favoriteClients) { return $false }
    return $sys.favoriteClients -contains $clientValue
}

function Show-Menu {
    param([string]$FilterText = "")

    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║       SAP Quick Logon        ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    $script:menuSystems = @()
    # $script:menuClients = @()
    $i = 1

    foreach ($sys in $systems) {
        $clients = if ($sys.client -is [array]) { $sys.client } else { @($sys.client) }

        $anyShown = $false

	    if ($sys.hidden -eq $true) { continue }

        foreach ($c in $clients) {
            $label = "{0} [{1}]" -f $sys.name, $c

            if ($FilterText -and ($label -notmatch [regex]::Escape($FilterText))) { continue }

            $isFav = Test-IsFavoriteClient -sys $sys -clientValue $c
            $marker = if ($isFav) { "★ " } else { "  " }
            $color  = if ($isFav) { "Green" } else { "White" }

            Write-Host ("  {0,2}.  {1}{2}" -f $i, $marker, $label) -ForegroundColor $color

            $script:menuItems += [PSCustomObject]@{ System = $sys; Client = $c }
            # $script:menuSystems += $sys
            # $script:menuClients += $c

            $i++
            $anyShown = $true
        }

        # Blank line between systems for readability
        if ($anyShown) { Write-Host "" }
    }

    if ($script:menuItems.Count -eq 0) {
        Write-Host "  (no matching systems)" -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host "  ──────────────────────────────" -ForegroundColor DarkGray
    Write-Host "   0.  Exit          /text = search" -ForegroundColor DarkGray
    Write-Host "  ──────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

$filter = ""

while ($true) {
    Show-Menu -FilterText $filter

    $prompt = if ($filter) { "  Logon (filter: '$filter')" } else { "  Logon" }
    $userInput = Read-Host $prompt

    if ($userInput -match '^(0|q|exit)$') { Clear-Host; break }

    # Type /text to filter, or / alone to clear the filter
    if ($userInput.StartsWith('/')) {
        $filter = $userInput.Substring(1).Trim()
        continue
    }

    $choiceNum = 0
    if (-not [int]::TryParse($userInput, [ref]$choiceNum) -or $choiceNum -lt 1 -or $choiceNum -gt $menuItems.Count) {
        Write-Host "  Invalid choice." -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    $item   = $menuItems[$choiceNum - 1]
    $sys    = $item.System
    $client = $item.Client

    # $connStr = Build-ConnString -sys $sys
    $connStr = $sys.system

    $argParts = @(
        "-type=SAPGUI",
        "-system=`"$connStr`"",
        "-client=$client",
        "-user=`"$($sys.user)`"",
        "-pw=`"$($sys.password)`""
        # "–maxgui"
    )

    # Language is optional
    if ($sys.language -and $sys.language.Trim() -ne "") {
        $argParts += "-language=$($sys.language)"
    }

    $argString = $argParts -join " "

    try {
        Start-Process -FilePath $SapShcut -ArgumentList $argString -ErrorAction Stop
        Write-Host ""
        Write-Host ("  Launching {0} [{1}] ..." -f $sys.name, $client) -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host ("  Failed to launch {0}: {1}" -f $sys.name, $_.Exception.Message) -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 800
}