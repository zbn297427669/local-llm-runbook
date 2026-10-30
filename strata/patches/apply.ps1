<#
    Re-apply this machine's local patches to a Strata Terminal install.

    Why this exists: the Terminal is shipped as a versioned archive and replaced whole on
    update, so local edits (GPU power capping, the bare-command help) disappear. This script
    puts them back -- and only ever inserts lines, never rewrites existing ones, so a patch
    that no longer fits says so instead of corrupting the file.

    Usage:
        .\apply.ps1 -Check        report what is applied / missing / would not fit (default)
        .\apply.ps1 -Apply        insert the missing patches
        .\apply.ps1 -Revert       remove every patch this script added
        .\apply.ps1 -Terminal DIR check a different Terminal install

    Exit codes: 0 all good, 1 something needs a human, 2 bad usage.

    Anchors are exact lines from the upstream source, not line numbers. After a Terminal
    update that rewrites a patched function, -Check names the patch that no longer fits and
    the file it is in; fix the anchor in patches.json then, or delete the patch if upstream
    now does the same thing.
#>
param(
    [switch]$Check,
    [switch]$Apply,
    [switch]$Revert,
    [string]$Terminal
)

$ErrorActionPreference = 'Stop'
$HERE = $PSScriptRoot

if (-not $Terminal) {
    # the Terminal root is the folder that holds strata.py; ../terminal/current is the
    # junction the installer keeps pointed at the newest version
    $Terminal = Join-Path (Split-Path $HERE -Parent) 'terminal\current'
}
if (-not (Test-Path (Join-Path $Terminal 'strata.py'))) {
    Write-Host "No Terminal at '$Terminal' (strata.py not found)." -ForegroundColor Red
    Write-Host 'Pass -Terminal <folder> or check that the junction still points at a version folder.'
    exit 2
}

$manifestPath = Join-Path $HERE 'patches.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

function Read-Text([string]$Path) {
    # no BOM, no newline translation: the file goes back byte-identical except for the insert
    [IO.File]::ReadAllText($Path)
}
function Write-Text([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Count-Of([string]$Haystack, [string]$Needle) {
    if (-not $Needle) { return 0 }
    ([regex]::Matches($Haystack, [regex]::Escape($Needle))).Count
}

$results = @()

# ---------------------------------------------------------------- new files
foreach ($nf in $manifest.new_files) {
    $target = Join-Path $Terminal $nf.to
    $source = Join-Path $HERE $nf.from
    $state = if (-not (Test-Path $source)) { 'missing-source' }
             elseif (-not (Test-Path $target)) { 'not-applied' }
             else {
                 $t = Read-Text $target
                 if (Count-Of $t $nf.marker -ge 1) { 'applied' } else { 'conflict' }
             }
    $results += [pscustomobject]@{ Id = $nf.id; Kind = 'file'; State = $state; File = $nf.to; Note = '' }
}

# ---------------------------------------------------------------- patches
foreach ($p in $manifest.patches) {
    $path = Join-Path $Terminal $p.file
    if (-not (Test-Path $path)) {
        $results += [pscustomobject]@{ Id = $p.id; Kind = 'patch'; State = 'missing-file'; File = $p.file; Note = '' }
        continue
    }
    $text = Read-Text $path
    $note = ''

    # applied? the marker is the function this patch defines
    if ((Count-Of $text $p.marker) -ge 1) {
        # the call site must be there too, or the function is dead code.
        # Compare on the first line only: a multi-line call can differ in line endings.
        $callFirst = ($p.call -split "`r?`n")[0]
        $callSeen = (Count-Of $text $callFirst) -ge 1
        $state = if ($callSeen) { 'applied' } else { 'partial' }
        if (-not $callSeen) { $note = 'the function is present but nothing calls it' }
        $results += [pscustomobject]@{ Id = $p.id; Kind = 'patch'; State = $state; File = $p.file; Note = $note }
        continue
    }

    # not applied: can the anchors be found?
    $before = Count-Of $text $p.insert_before
    if ($before -ne 1) {
        $results += [pscustomobject]@{ Id = $p.id; Kind = 'patch'; State = 'anchor-missing'; File = $p.file
                                      Note = ("'{0}' found {1} times (need exactly 1)" -f $p.insert_before.Trim(), $before) }
        continue
    }
    # insert-before-call anchors on a line inside the function that gets the call
    if ($p.kind -eq 'insert-before-call') {
        $after = Count-Of $text $p.insert_after
        if ($after -lt 1) {
            $results += [pscustomobject]@{ Id = $p.id; Kind = 'patch'; State = 'anchor-missing'; File = $p.file
                                          Note = ("'{0}' not found inside that function" -f $p.insert_after.Trim()) }
            continue
        }
    }
    # insert-function-and-call anchors the call on a line inside the caller
    else {
        $scopeAnchor = if ($p.call_anchor_after_marker_of) { $p.call_anchor_after_marker_of } else { $p.insert_before }
        $scopeAt = $text.IndexOf($scopeAnchor)
        $callAt = if ($scopeAt -ge 0) { $text.IndexOf($p.call_anchor, $scopeAt) } else { -1 }
        if ($callAt -lt 0) {
            $results += [pscustomobject]@{ Id = $p.id; Kind = 'patch'; State = 'anchor-missing'; File = $p.file
                                          Note = ("'{0}' not found after '{1}'" -f $p.call_anchor.Trim(), $scopeAnchor.Trim()) }
            continue
        }
    }
    if (-not (Test-Path (Join-Path $HERE $p.snippet))) {
        $results += [pscustomobject]@{ Id = $p.id; Kind = 'patch'; State = 'missing-source'; File = $p.file; Note = $p.snippet }
        continue
    }
    $results += [pscustomobject]@{ Id = $p.id; Kind = 'patch'; State = 'not-applied'; File = $p.file; Note = '' }
}

# ---------------------------------------------------------------- report
function Show-Report($rows) {
    $w = 20
    Write-Host ("Terminal: {0}" -f $Terminal) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ('  {0,-20} {1,-16} {2}' -f 'PATCH', 'STATE', 'FILE / NOTE')
    Write-Host ('  {0,-20} {1,-16} {2}' -f '-----', '-----', '-----------')
    foreach ($r in $rows) {
        $colour = switch ($r.State) {
            'applied'       { 'Green' }
            'not-applied'   { 'Yellow' }
            'partial'       { 'Yellow' }
            default         { 'Red' }
        }
        $detail = $r.File
        if ($r.Note) { $detail = "$detail  -- $($r.Note)" }
        Write-Host ('  {0,-20} {1,-16} {2}' -f $r.Id, $r.State, $detail) -ForegroundColor $colour
    }
    Write-Host ''
}

# ---------------------------------------------------------------- revert
if ($Revert) {
    $changed = 0
    foreach ($nf in $manifest.new_files) {
        $target = Join-Path $Terminal $nf.to
        if (Test-Path $target) {
            Remove-Item -LiteralPath $target -Force
            Write-Host "removed  $($nf.to)" -ForegroundColor DarkGray
            $changed++
        }
    }
    foreach ($p in $manifest.patches) {
        $path = Join-Path $Terminal $p.file
        if (-not (Test-Path $path)) { continue }
        $text = Read-Text $path
        if ((Count-Of $text $p.marker) -lt 1) { continue }

        # The snippet is stored with LF; the file may use CRLF. Normalise a copy of the
        # file's text to LF, cut both the snippet and the call in that space, then put the
        # file's own line endings back. A plain .Replace on raw text misses every CRLF file.
        $crlf = $text -match "`r`n"
        $lfText = if ($crlf) { $text -replace "`r`n", "`n" } else { $text }
        $snippet = (Read-Text (Join-Path $HERE $p.snippet)) -replace "`r`n", "`n"
        if ($snippet -notmatch "`n$") { $snippet += "`n" }
        $call = ($p.call -replace "`r`n", "`n")

        $new = $lfText.Replace($snippet, '')
        # the call may sit alone on its line(s); drop the whole line it occupies
        $new = $new.Replace($call + "`n", '')
        if ($new -eq $lfText) { $new = $lfText.Replace($call, '') }

        if ($new -ne $lfText) {
            if ($crlf) { $new = $new -replace "`n", "`r`n" }
            Write-Text $path $new
            Write-Host "reverted $($p.id) in $($p.file)" -ForegroundColor DarkGray
            $changed++
        }
    }
    Write-Host ''
    if ($changed) { Write-Host "Reverted $changed item(s)." -ForegroundColor Green }
    else { Write-Host 'Nothing to revert.' -ForegroundColor DarkGray }
    exit 0
}

# ---------------------------------------------------------------- apply
if ($Apply) {
    $todo = $results | Where-Object { $_.State -in 'not-applied' }
    $blocked = $results | Where-Object { $_.State -in @('anchor-missing', 'missing-file', 'conflict', 'partial', 'missing-source') }
    if ($blocked) {
        Show-Report $results
        Write-Host 'Not applying: the items above need a human first.' -ForegroundColor Red
        exit 1
    }
    if (-not $todo) {
        Show-Report $results
        Write-Host 'Everything is already applied.' -ForegroundColor Green
        exit 0
    }

    foreach ($r in $todo) {
        if ($r.Kind -eq 'file') {
            $nf = $manifest.new_files | Where-Object { $_.id -eq $r.Id }
            Copy-Item -LiteralPath (Join-Path $HERE $nf.from) -Destination (Join-Path $Terminal $nf.to) -Force
            Write-Host "added    $($nf.to)" -ForegroundColor Green
            continue
        }
        $p = $manifest.patches | Where-Object { $_.id -eq $r.Id }
        $path = Join-Path $Terminal $p.file
        $text = Read-Text $path

        # Everything inserted must use the file's own line endings: the Terminal ships CRLF,
        # the snippets live in this repo as LF (the same reason .gitattributes exists there).
        $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
        $snippet = Read-Text (Join-Path $HERE $p.snippet)
        $snippet = $snippet -replace "`r`n", "`n"
        if ($snippet -notmatch "`n$") { $snippet += "`n" }
        if ($nl -eq "`r`n") { $snippet = $snippet -replace "`n", "`r`n" }
        # the call is authored in patches.json with \n as well
        $call = ($p.call -replace "`r`n", "`n")
        if ($nl -eq "`r`n") { $call = $call -replace "`n", "`r`n" }

        # 1. the function goes before the target definition
        $text = $text.Replace($p.insert_before, $snippet + $nl + $p.insert_before)

        # 2. the call goes after its anchor
        if ($p.kind -eq 'insert-before-call') {
            $text = $text.Replace($p.insert_after, $p.insert_after + $nl + $call)
        } else {
            # Search from the function that receives the call, so a "    return 0" in some
            # earlier function cannot capture it.
            $scopeAnchor = if ($p.call_anchor_after_marker_of) { $p.call_anchor_after_marker_of } else { $p.insert_before }
            $scopeAt = $text.IndexOf($scopeAnchor)
            $idx = $text.IndexOf($p.call_anchor, $scopeAt)
            if ($idx -lt 0) { throw "apply: '$($p.call_anchor.Trim())' vanished from $($p.file)" }
            # call_before_anchor puts the call above the anchor line (e.g. before the
            # function's `return`); otherwise it goes below it.
            if ($p.call_before_anchor) {
                $text = $text.Insert($idx, $call + $nl)
            } else {
                $at = $idx + $p.call_anchor.Length
                $text = $text.Insert($at, $nl + $call)
            }
        }

        # No newline collapsing: the upstream files already contain runs of blank lines
        # (54 of them in runner.py), and squashing those would rewrite the whole file and
        # make every future diff unreadable.
        Write-Text $path $text
        Write-Host "patched  $($p.id) in $($p.file)" -ForegroundColor Green
    }
    Write-Host ''
    Write-Host 'Applied. Run with -Check to confirm.' -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------- check (default)
Show-Report $results
$bad = $results | Where-Object { $_.State -notin @('applied', 'not-applied') }
if ($bad) {
    Write-Host 'Needs a human: the states in red above.' -ForegroundColor Red
    Write-Host 'Either the Terminal changed shape (fix the anchor in patches.json) or upstream'
    Write-Host 'now does the same thing (delete that patch).'
    exit 1
}
$pending = $results | Where-Object { $_.State -eq 'not-applied' }
if ($pending) {
    Write-Host 'Some patches are not applied. Run with -Apply.' -ForegroundColor Yellow
    exit 0
}
Write-Host 'All patches applied.' -ForegroundColor Green
exit 0
