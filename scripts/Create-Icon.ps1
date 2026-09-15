# Deterministic Win32 icon: no design tool or build-time dependency required.
$root=Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Path (Join-Path $root 'assets') -Force | Out-Null
$stream=[IO.File]::Create((Join-Path $root 'assets/sidebar.ico'))
$w=[IO.BinaryWriter]::new($stream)
try{
    $w.Write([uint16]0);$w.Write([uint16]1);$w.Write([uint16]1)
    $w.Write([byte]16);$w.Write([byte]16);$w.Write([byte]0);$w.Write([byte]0)
    $w.Write([uint16]1);$w.Write([uint16]32);$w.Write([uint32]1128);$w.Write([uint32]22)
    $w.Write([uint32]40);$w.Write([int32]16);$w.Write([int32]32)
    $w.Write([uint16]1);$w.Write([uint16]32)
    $w.Write([uint32]0);$w.Write([uint32]1088)
    1..4|ForEach-Object{$w.Write([uint32]0)}
    for($y=15;$y -ge 0;$y--){for($x=0;$x -lt 16;$x++){
        $r=0;$g=0;$b=0;$a=0
        if($x -ge 1 -and $x -le 14 -and $y -ge 1 -and $y -le 14){$r=89;$g=103;$b=121;$a=255}
        if($x -ge 4 -and $x -le 6 -and $y -ge 4 -and $y -le 11){$r=239;$g=243;$b=248}
        if($x -ge 9 -and $x -le 11 -and (($y -ge 4 -and $y -le 6) -or ($y -ge 9 -and $y -le 11))){$r=180;$g=201;$b=223}
        $w.Write([byte]$b);$w.Write([byte]$g);$w.Write([byte]$r);$w.Write([byte]$a)
    }}
    1..64|ForEach-Object{$w.Write([byte]0)}
}finally{$w.Dispose();$stream.Dispose()}
