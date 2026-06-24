#Requires -Version 5.0
<#
.SYNOPSIS
    SAP Quick Logon — launch SAP GUI sessions from a JSON system list without
    manually filling the SAP Logon Pad every time.

.DESCRIPTION
    Reads system definitions from a JSON file, presents an interactive TUI menu,
    and calls sapshcut.exe with the correct -guiparm / -system flags so the
    connection string is built exactly the way SAP expects it.

    Connection string logic (matches sapshcut.exe behaviour):
      • No SAP Router  → -guiparm="/H/<host>/S/<port>"
      • With SAP Router → -guiparm="<router>/H/<host>/S/<port>"

    The -system flag carries the SID (e.g. H23), NOT the connection string.

.NOTES
    Backward-compatible with PowerShell 5.x (Windows PowerShell).
    JSON path: %APPDATA%\SAP\Common\sap-systems.json
#>

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$JsonFile = "$env:APPDATA\SAP\Common\sap-systems.json"

# ---------------------------------------------------------------------------
# Helper: Resolve a .lnk shortcut to its target executable path
# ---------------------------------------------------------------------------
function Get-PathFromShortcut {
    param([string]$LnkPath)
    try {
        $shell    = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($LnkPath)
        return $shortcut.TargetPath
    } catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# Helper: Locate sapshcut.exe using several discovery strategies
# ---------------------------------------------------------------------------
function Find-SapShcut {

    # Strategy 1 — well-known default install paths (64-bit and 32-bit)
    $candidates = @(
        "${env:ProgramFiles}\SAP\FrontEnd\SAPgui\sapshcut.exe",
        "${env:ProgramFiles(x86)}\SAP\FrontEnd\SAPgui\sapshcut.exe"
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) { return $found }

    # Strategy 2 — resolve via Start Menu shortcuts under "SAP Front End"
    $shortcutFolder = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SAP Front End"
    if (Test-Path $shortcutFolder) {
        $lnkFiles = Get-ChildItem -Path $shortcutFolder -Filter "*.lnk" -ErrorAction SilentlyContinue
        foreach ($lnk in $lnkFiles) {
            $targetPath = Get-PathFromShortcut -LnkPath $lnk.FullName
            if (-not $targetPath) { continue }

            # Shortcut may point directly to sapshcut.exe
            if ($targetPath -match 'sapshcut\.exe$' -and (Test-Path $targetPath)) {
                return $targetPath
            }

            # Or it may point to saplogon.exe; sapshcut.exe lives in the same folder
            $installDir = Split-Path -Path $targetPath -Parent
            $candidate  = Join-Path $installDir "sapshcut.exe"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    # Strategy 3 — registry (SAP GUI installer writes InstallDir here)
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

    # Strategy 4 — fall back to PATH
    $inPath = Get-Command "sapshcut.exe" -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    return $null
}

# ---------------------------------------------------------------------------
# Helper: Build the -guiparm connection string for sapshcut.exe
#
#   Without router : /H/<host>/S/<port>
#   With router    : <router>/H/<host>/S/<port>
#
# The router string already starts with /H/ (e.g. /H/azrap001.eastus2.cloudapp.azure.com),
# so we simply prepend it — no extra separator is needed.
# ---------------------------------------------------------------------------
function Build-GuiParm {
    param($sys)

    if (-not $sys.host -or $sys.host.Trim() -eq "") { return $null }

    $hostPart = "/H/$($sys.host)/S/$($sys.port)"

    if ($sys.sapRouter -and $sys.sapRouter.Trim() -ne "") {
        # Concatenate: <router>/H/<host>/S/<port>
        return "$($sys.sapRouter.Trim())$hostPart"
    }

    return $hostPart
}

# ---------------------------------------------------------------------------
# Helper: Check whether a client value is in the system's favoriteClients list
# ---------------------------------------------------------------------------
function Test-IsFavoriteClient {
    param($sys, [string]$clientValue)

    if (-not $sys.favoriteClients) { return $false }
    return $sys.favoriteClients -contains $clientValue
}

# ---------------------------------------------------------------------------
# UI: Render the system/client selection menu
#     Returns a fresh array of menu items (each entry = one system+client row)
# ---------------------------------------------------------------------------
function Show-Menu {
    param([string]$FilterText = "")

    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║       SAP Quick Logon        ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Build a fresh list on every render so numbering is always consistent
    # $items = [System.Collections.Generic.List[PSCustomObject]]::new()
    # Plain array — the only collection type allowed in Constrained Language Mode
    $items    = @()
    $i     = 1

    foreach ($sys in $systems) {
        # Skip hidden systems
        if ($sys.hidden -eq $true) { continue }

        # Normalise client to array (JSON may have a single string value)
        $clients  = if ($sys.client -is [array]) { $sys.client } else { @($sys.client) }
        $anyShown = $false

        foreach ($c in $clients) {
            $label = "{0} [{1}]" -f $sys.name, $c

            # Apply search filter (case-insensitive substring match)
            if ($FilterText -and ($label -notmatch [regex]::Escape($FilterText))) { continue }

            $isFav  = Test-IsFavoriteClient -sys $sys -clientValue $c
            $marker = if ($isFav) { "★ " } else { "  " }
            $color  = if ($isFav) { "Green" } else { "White" }

            Write-Host ("  {0,2}.  {1}{2}" -f $i, $marker, $label) -ForegroundColor $color

            # $items.Add([PSCustomObject]@{ System = $sys; Client = $c })
            # Store as hashtable — allowed in Constrained Language Mode
            # PSCustomObject and New-Object are both blocked
            $items += @{ System = $sys; Client = $c }
            
            $i++
            $anyShown = $true
        }

        # Visual separator between system groups
        if ($anyShown) { Write-Host "" }
    }

    if ($items.Count -eq 0) {
        Write-Host "  (no matching systems)" -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host "  ──────────────────────────────" -ForegroundColor DarkGray
    Write-Host "   0.  Exit          /text = search" -ForegroundColor DarkGray
    Write-Host "  ──────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    return ,$items   # return as array (comma prefix prevents PS from unwrapping)
}

# ---------------------------------------------------------------------------
# Startup: locate sapshcut.exe
# ---------------------------------------------------------------------------

$SapShcut = Find-SapShcut

if (-not $SapShcut) {
    Write-Host "  sapshcut.exe could not be found automatically." -ForegroundColor Red
    Write-Host "  Please enter the full path to sapshcut.exe, or press Enter to exit." -ForegroundColor Yellow
    $manualPath = Read-Host "  Path"

    if (-not $manualPath -or -not (Test-Path $manualPath)) {
        Write-Host "  Invalid path. Exiting." -ForegroundColor Red
        exit 1
    }
    $SapShcut = $manualPath
}

# ---------------------------------------------------------------------------
# Startup: load system definitions from JSON
# ---------------------------------------------------------------------------

if (-not (Test-Path $JsonFile)) {
    Write-Host "  JSON file not found: $JsonFile" -ForegroundColor Red
    exit 1
}

$systems = Get-Content $JsonFile -Raw | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Main interaction loop
# ---------------------------------------------------------------------------

$filter = ""

while ($true) {
    # Render menu and capture the ordered item list for this render pass
    $menuItems = Show-Menu -FilterText $filter

    $prompt    = if ($filter) { "  Logon (filter: '$filter')" } else { "  Logon" }
    $userInput = (Read-Host $prompt).Trim()

    # Exit commands
    if ($userInput -match '^(0|q|exit)$') {
        Clear-Host
        break
    }

    # Filter command: /text sets filter, / alone clears it
    if ($userInput.StartsWith('/')) {
        $filter = $userInput.Substring(1).Trim()
        continue
    }

    # Validate numeric selection
    $choiceNum = 0
    if (-not [int]::TryParse($userInput, [ref]$choiceNum) `
        -or $choiceNum -lt 1 `
        -or $choiceNum -gt $menuItems.Count) {
        Write-Host "  Invalid choice." -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    $item   = $menuItems[$choiceNum - 1]
    $sys    = $item.System
    $client = $item.Client

    # Build the guiparm connection string (host/port + optional SAP Router prefix)
    $guiParm = Build-GuiParm -sys $sys

    # # Check guiparm 
    # if (-not $guiParm) {
    #     Write-Host "  Skipping $($sys.name): host is not configured." -ForegroundColor Yellow
    #     Start-Sleep -Milliseconds 800
    #     continue
    # }

    # Assemble sapshcut.exe arguments
    # -guiparm  : full RFC connection string (replaces the old -system for direct connections)
    # -system   : SID, used by SAP for session title and system identification
    # -maxgui   : start SAP GUI window maximized
    $argParts = @(
        "-guiparm=`"$guiParm`"",
        "-system=$($sys.system)",
        "-client=$client",
        "-user=`"$($sys.user)`"",
        "-pw=`"$($sys.password)`"",
        "-maxgui"
    )

    # Language is optional — only pass it when defined
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

    # Start-Sleep -Milliseconds 800
}