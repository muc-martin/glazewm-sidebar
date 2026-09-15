Set-StrictMode -Version Latest

function ConvertTo-SidebarConfiguration {
    param([Parameter(Mandatory)][string]$Text)
    # Deliberately constrained editor: preserve user YAML, reject ambiguous forms.
    # Standard GlazeWM block mappings and inline or block command lists are supported.
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($Text -split '\r?\n')) { $lines.Add($line) }
    foreach ($key in @('startup_commands', 'shutdown_commands')) {
        $matches = @(0..($lines.Count-1) | Where-Object { $lines[$_] -match "^  ${key}:" })
        if ($matches.Count -ne 1) { throw "Expected one general.$key entry. Configuration was not changed." }
        $index = $matches[0]
        $value = ($lines[$index] -replace "^  ${key}:\s*", '').Trim()
        $commands = [Collections.Generic.List[string]]::new()
        $end = $index + 1
        if ($value.StartsWith('[')) {
            if ($value -notmatch '^\[(.*)\]\s*(?:#.*)?$') { throw "Unsupported inline $key list." }
            $body = $Matches[1].Trim()
            while ($body.Length) {
                if ($body -match "^'((?:''|[^'])*)'\s*(,|$)") {
                    $commands.Add($Matches[1].Replace("''", "'")); $body=$body.Substring($Matches[0].Length).Trim()
                } elseif ($body -match '^"((?:\\.|[^"\\])*)"\s*(,|$)') {
                    # JSON is a safe subset for the double-quoted commands we accept.
                    $commands.Add((ConvertFrom-Json ('"'+$Matches[1]+'"'))); $body=$body.Substring($Matches[0].Length).Trim()
                } else { throw "Use quoted command strings in $key; ambiguous YAML was left unchanged." }
            }
        } elseif (!$value -or $value.StartsWith('#')) {
            while ($end -lt $lines.Count -and ($lines[$end] -match '^\s*$|^\s*#|^    ')) {
                $entry=$lines[$end].Trim()
                if ($entry -and !$entry.StartsWith('#')) {
                    if ($entry -match "^-\s+'((?:''|[^'])*)'\s*(?:#.*)?$") { $commands.Add($Matches[1].Replace("''", "'")) }
                    elseif ($entry -match '^-\s+"((?:\\.|[^"\\])*)"\s*(?:#.*)?$') { $commands.Add((ConvertFrom-Json ('"'+$Matches[1]+'"'))) }
                    elseif ($entry -match '^-\s+([^\[\]{}&*!|>]+)$') { $commands.Add(($Matches[1] -replace '\s+#.*$','').Trim()) }
                    else { throw "Unsupported block command in $key." }
                }
                $end++
            }
        } else { throw "Unsupported $key format." }
        $keep = @($commands | Where-Object {
            $launch = $_ -match '(?i)^shell-exec\s+(?:"[^"\r\n]*[\\/]|[^\s"\r\n]*[\\/])?(?:zebar|native-sidebar)(?:\.exe)?"?(?:\s|$)'
            $stop = $_ -match '(?i)^shell-exec\s+taskkill(?:\.exe)?\s+.*?/IM\s+"?(?:zebar|native-sidebar)\.exe"?(?:\s|$)'
            !($launch -or $stop)
        })
        $encoded = @($keep | ForEach-Object { "'" + $_.Replace("'", "''") + "'" })
        $lines[$index] = '  ' + $key + ': [' + ($encoded -join ', ') + ']'
        if ($end -gt $index+1) { $lines.RemoveRange($index+1,$end-$index-1) }
    }
    $gaps = @(0..($lines.Count-1) | Where-Object {$lines[$_] -match '^  outer_gap:\s*(?:#.*)?$'})
    if ($gaps.Count -ne 1) { throw 'Expected one block outer_gap mapping.' }
    $found=@{}
    for($i=$gaps[0]+1;$i -lt $lines.Count;$i++) {
        if($lines[$i] -match '^\S|^  \S') {break}
        if($lines[$i] -match '^    (top|left):\s*[''"]?([0-9.]+)px[''"]?\s*(?:#.*)?$') {
            $key=$Matches[1]; if($found.ContainsKey($key)){throw 'Duplicate gap key.'};$found[$key]=$true
            $amount=if($key -eq 'left'){44}else{8};$lines[$i]="    ${key}: '${amount}px'"
        }
    }
    if($found.Count -ne 2){throw 'Expected top and left pixel gaps; configuration was not changed.'}
    if (($lines -join "`n") -notmatch 'window_process:\s*\{\s*equals:\s*[''"]native-sidebar[''"]\s*\}') {
        $rules=@(0..($lines.Count-1)|Where-Object {$lines[$_] -match '^window_rules:\s*(?:#.*)?$'})
        if($rules.Count -ne 1){throw 'Expected one block window_rules list.'}
        $lines.InsertRange($rules[0]+1,[string[]]@("  - commands: ['ignore']",'    match:','      - window_process: { equals: "native-sidebar" }'))
    }
    $newline=if($Text.Contains("`r`n")){"`r`n"}else{"`n"}
    return $lines -join $newline
}

function Get-WorkspaceNames {
    param([string]$Text)
    $section=[regex]::Match($Text,'(?ms)^workspaces:\s*\r?\n(.*?)(?=^\S|\z)').Groups[1].Value
    $names=@([regex]::Matches($section,'(?m)^  - name:\s*[''"]?([a-zA-Z0-9_.-]+)[''"]?\s*(?:#.*)?$') | ForEach-Object {$_.Groups[1].Value})
    $entries=@([regex]::Matches($section,'(?m)^  - name:'))
    if(!$names.Count -or $names.Count -ne $entries.Count){throw 'Workspace names must use letters, numbers, underscore, dot or hyphen.'}
    return $names
}
