## snapshot.ps1 — Tager dagligt snapshot af mappestrukturen og opdaterer HTML-filen
## Konfiguration
$rootDir   = Split-Path -Parent $PSScriptRoot   # VD-mappen (parent af _historik)
$htmlFile  = Join-Path $PSScriptRoot "mappehistorik.html"
$today     = Get-Date -Format "yyyy-MM-dd"
$maxDepth  = 2

## Hent mapper (2 niveauer), ekskluder _historik
$folders = @()
Get-ChildItem -Path $rootDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "_historik" } |
    Sort-Object Name |
    ForEach-Object {
        $folders += $_.Name
        Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object {
                $folders += "  " + $_.Name
            }
    }

$snapshotText = $folders -join "`n"

## Hvis HTML-filen ikke findes, opret den med tom data
if (-not (Test-Path $htmlFile)) {
    $htmlContent = @"
<!DOCTYPE html>
<html lang="da">
<head>
<meta charset="UTF-8">
<title>Mappehistorik — VD</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Consolas,'Courier New',monospace;background:#1e1e2e;color:#cdd6f4;padding:20px}
h1{font-size:1.3em;margin-bottom:12px;color:#89b4fa}
.controls{display:flex;align-items:center;gap:14px;margin-bottom:18px;flex-wrap:wrap}
.date-label{font-size:1.1em;font-weight:bold;color:#a6e3a1;min-width:110px}
.nav-btn{background:#313244;border:1px solid #45475a;color:#cdd6f4;padding:4px 12px;cursor:pointer;border-radius:4px;font-size:1em}
.nav-btn:hover{background:#45475a}
input[type=date]{background:#313244;border:1px solid #45475a;color:#cdd6f4;padding:4px 8px;border-radius:4px;font-size:1em;font-family:inherit;color-scheme:dark}
pre{background:#181825;padding:16px;border-radius:8px;overflow-x:auto;line-height:1.6;font-size:0.95em;white-space:pre-wrap}
.diff-added{color:#a6e3a1;font-weight:bold}
.diff-removed{color:#f38ba8;text-decoration:line-through}
.toggle-row{margin-bottom:10px;display:flex;align-items:center;gap:10px}
.toggle-row label{cursor:pointer;color:#89b4fa}
.info{color:#6c7086;font-size:0.85em;margin-top:12px}
</style>
</head>
<body>
<h1>Mappehistorik — VD</h1>
<div class="toggle-row">
  <input type="checkbox" id="showDiff" checked>
  <label for="showDiff">Vis forskelle fra forrige dag</label>
</div>
<div class="controls">
  <button class="nav-btn" onclick="step(-1)">&#9664; Forrige</button>
  <input type="date" id="datePicker">
  <button class="nav-btn" onclick="step(1)">N&aelig;ste &#9654;</button>
  <span class="date-label" id="dateLabel"></span>
</div>
<pre id="tree"></pre>
<p class="info" id="info"></p>

<script>
var SNAPSHOTS = {};
// DATA_MARKER

var dates = Object.keys(SNAPSHOTS).sort();
var datePicker = document.getElementById('datePicker');
var dateLabel = document.getElementById('dateLabel');
var tree = document.getElementById('tree');
var info = document.getElementById('info');
var showDiff = document.getElementById('showDiff');
var currentIdx = dates.length - 1;

function render() {
  if (dates.length === 0) { tree.textContent = '(ingen data endnu)'; return; }
  if (currentIdx < 0) currentIdx = 0;
  if (currentIdx >= dates.length) currentIdx = dates.length - 1;
  var d = dates[currentIdx];
  datePicker.value = d;
  datePicker.min = dates[0];
  datePicker.max = dates[dates.length - 1];
  dateLabel.textContent = 'Snapshot ' + (currentIdx+1) + ' af ' + dates.length;
  var lines = SNAPSHOTS[d];
  if (showDiff.checked && currentIdx > 0) {
    var prev = new Set(SNAPSHOTS[dates[currentIdx-1]]);
    var curr = new Set(lines);
    var allLines = [];
    SNAPSHOTS[dates[currentIdx-1]].forEach(function(l){ if(!curr.has(l)) allLines.push({t:l,s:'r'}); });
    lines.forEach(function(l){ allLines.push({t:l, s: prev.has(l)?'':'a'}); });
    tree.innerHTML = allLines.map(function(o){
      if(o.s==='a') return '<span class="diff-added">+ '+esc(o.t)+'</span>';
      if(o.s==='r') return '<span class="diff-removed">- '+esc(o.t)+'</span>';
      return '  '+esc(o.t);
    }).join('\n');
  } else {
    tree.textContent = lines.join('\n');
  }
}

function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}

function step(d){
  currentIdx = Math.max(0, Math.min(dates.length-1, currentIdx + d));
  render();
}

datePicker.addEventListener('input', function(){
  var picked = datePicker.value;
  var best = 0;
  for (var i = 0; i < dates.length; i++) {
    if (dates[i] <= picked) best = i;
  }
  currentIdx = best;
  render();
});
showDiff.addEventListener('change', render);

render();
</script>
</body>
</html>
"@
    Set-Content -Path $htmlFile -Value $htmlContent -Encoding UTF8
}

## Læs eksisterende HTML og indsæt/opdater dagens snapshot
$html = Get-Content -Path $htmlFile -Raw -Encoding UTF8

# Byg JS-array fra linjer
$jsLines = ($folders | ForEach-Object {
    '"' + ($_ -replace '\\', '\\\\' -replace '"', '\"') + '"'
}) -join ','

$entry = "SNAPSHOTS[`"$today`"]=[$jsLines];"

if ($html -match "SNAPSHOTS\[`"$today`"\]") {
    # Erstat eksisterende snapshot for i dag
    $html = $html -replace "SNAPSHOTS\[`"$today`"\]\s*=\s*\[.*?\];", $entry
} else {
    # Indsæt nyt snapshot før DATA_MARKER
    $html = $html -replace "// DATA_MARKER", "$entry`n// DATA_MARKER"
}

Set-Content -Path $htmlFile -Value $html -Encoding UTF8

Write-Host "Snapshot gemt for $today"
