## snapshot.ps1 — Tager dagligt snapshot af mappestrukturen og opdaterer HTML-filen
## Konfiguration
$rootDir   = Split-Path -Parent $PSScriptRoot   # VD-mappen (parent af _historik)
$htmlFile  = Join-Path $PSScriptRoot "mappehistorik.html"
$today     = Get-Date -Format "yyyy-MM-dd"

## Funktion: Læs eller opret folder-id i desktop.ini
function Get-OrCreateFolderId {
    param([string]$folderPath)
    $desktopIni = Join-Path $folderPath "desktop.ini"
    $guidPattern = 'FolderId=([0-9a-fA-F\-]{36})'

    if (Test-Path $desktopIni) {
        $existingAttrs = (Get-Item $desktopIni -Force).Attributes
        try {
            $content = [System.IO.File]::ReadAllText($desktopIni)
        } catch {
            $content = ""
        }
        $match = [regex]::Match($content, $guidPattern)
        if ($match.Success) {
            return $match.Groups[1].Value
        }
        # Eksisterende desktop.ini uden [Claude] — append
        $id = [guid]::NewGuid().ToString()
        $appendContent = $content.TrimEnd() + "`r`n`r`n[Claude]`r`nFolderId=$id`r`nCreated=$today`r`n"
        (Get-Item $desktopIni -Force).Attributes = 'Normal'
        [System.IO.File]::WriteAllText($desktopIni, $appendContent)
        (Get-Item $desktopIni -Force).Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
        return $id
    } else {
        $id = [guid]::NewGuid().ToString()
        $newContent = "[Claude]`r`nFolderId=$id`r`nCreated=$today`r`n"
        [System.IO.File]::WriteAllText($desktopIni, $newContent)
        (Get-Item $desktopIni -Force).Attributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
        return $id
    }
}

## Rekursiv mappevandring (alle niveauer)
function Walk-Folder {
    param([string]$path, [int]$level)
    Get-ChildItem -Path $path -Directory -Force -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $indent = "  " * $level
            $script:folders   += $indent + $_.Name
            $script:folderIds += (Get-OrCreateFolderId $_.FullName)
            Walk-Folder $_.FullName ($level + 1)
        }
}

## Hent mapper (alle niveauer), ekskluder _historik, og hent/opret folder-id
$script:folders = @()
$script:folderIds = @()
Get-ChildItem -Path $rootDir -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "_historik" } |
    Sort-Object Name |
    ForEach-Object {
        $script:folders   += $_.Name
        $script:folderIds += (Get-OrCreateFolderId $_.FullName)
        Walk-Folder $_.FullName 1
    }
$folders   = $script:folders
$folderIds = $script:folderIds

$snapshotText = $folders -join "`n"

## Hvis HTML-filen ikke findes, opret den med tom data
if (-not (Test-Path $htmlFile)) {
    $htmlContent = @"
<!DOCTYPE html>
<html lang="da">
<head>
<meta charset="UTF-8">
<title>Mappehistorik &mdash; VD</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Consolas,'Courier New',monospace;background:#1e1e2e;color:#cdd6f4;padding:20px}
h1{font-size:1.3em;margin-bottom:12px;color:#89b4fa}
.controls{display:flex;align-items:center;gap:14px;margin-bottom:18px;flex-wrap:wrap}
.date-label{font-size:1.1em;font-weight:bold;color:#a6e3a1;min-width:110px}
.nav-btn{background:#313244;border:1px solid #45475a;color:#cdd6f4;padding:4px 12px;cursor:pointer;border-radius:4px;font-size:1em}
.nav-btn:hover{background:#45475a}
input[type=date]{background:#313244;border:1px solid #45475a;color:#cdd6f4;padding:4px 8px;border-radius:4px;font-size:1em;font-family:inherit;color-scheme:dark}
select{background:#313244;border:1px solid #45475a;color:#cdd6f4;padding:4px 8px;border-radius:4px;font-size:1em;font-family:inherit}
pre{background:#181825;padding:16px;border-radius:8px;overflow-x:auto;line-height:1.6;font-size:0.95em;white-space:pre-wrap}
.diff-added{color:#a6e3a1;font-weight:bold}
.diff-removed{color:#f38ba8;text-decoration:line-through}
.diff-renamed{color:#f9e2af;font-weight:bold}
.diff-renamed .arrow{color:#89b4fa;margin:0 6px}
.diff-renamed .old{opacity:0.7}
.toggle-row{margin-bottom:10px;display:flex;align-items:center;gap:10px}
.toggle-row label{cursor:pointer;color:#89b4fa}
.info{color:#6c7086;font-size:0.85em;margin-top:12px}
</style>
</head>
<body>
<h1>Mappehistorik &mdash; VD</h1>
<div class="toggle-row">
  <input type="checkbox" id="showDiff" checked>
  <label for="showDiff">Vis forskelle fra forrige dag</label>
  <span style="margin-left:20px">Dybde:</span>
  <select id="depthPicker"></select>
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
var SNAPSHOT_IDS = {};
// DATA_MARKER

var dates = Object.keys(SNAPSHOTS).sort();
var datePicker = document.getElementById('datePicker');
var dateLabel = document.getElementById('dateLabel');
var tree = document.getElementById('tree');
var info = document.getElementById('info');
var showDiff = document.getElementById('showDiff');
var depthPicker = document.getElementById('depthPicker');
var currentIdx = dates.length - 1;

function getIdentity(line){
  var s = line.replace(/^\s+/,'');
  s = s.replace(/^\d+_/,'');
  var idx = s.indexOf('_');
  return idx >= 0 ? s.substring(0, idx) : s;
}

function getDepth(line){
  var indent = (line.match(/^\s*/) || [''])[0].length;
  return (indent / 2) + 1;
}

function filterByDepth(lines, ids, maxDepth){
  if (!maxDepth) return { lines: lines.slice(), ids: (ids || []).slice() };
  var outL = [];
  var outI = [];
  for (var i = 0; i < lines.length; i++){
    if (getDepth(lines[i]) <= maxDepth){
      outL.push(lines[i]);
      outI.push(ids && ids[i] ? ids[i] : null);
    }
  }
  return { lines: outL, ids: outI };
}

function populateDepthPicker(){
  var maxDepth = 1;
  Object.keys(SNAPSHOTS).forEach(function(d){
    SNAPSHOTS[d].forEach(function(l){
      var dep = getDepth(l);
      if (dep > maxDepth) maxDepth = dep;
    });
  });
  var saved = localStorage.getItem('mappehistorik_depth') || '2';
  depthPicker.innerHTML = '';
  for (var i = 1; i <= maxDepth; i++){
    var opt = document.createElement('option');
    opt.value = String(i);
    opt.textContent = String(i);
    depthPicker.appendChild(opt);
  }
  var allOpt = document.createElement('option');
  allOpt.value = '0';
  allOpt.textContent = 'Alle';
  depthPicker.appendChild(allOpt);
  // Vælg gemt dybde, eller 2 hvis ikke gemt
  if (saved && depthPicker.querySelector('option[value="'+saved+'"]')){
    depthPicker.value = saved;
  } else {
    depthPicker.value = '2';
  }
}

function render() {
  if (dates.length === 0) { tree.textContent = '(ingen data endnu)'; return; }
  if (currentIdx < 0) currentIdx = 0;
  if (currentIdx >= dates.length) currentIdx = dates.length - 1;
  var d = dates[currentIdx];
  datePicker.value = d;
  datePicker.min = dates[0];
  datePicker.max = dates[dates.length - 1];
  dateLabel.textContent = 'Snapshot ' + (currentIdx+1) + ' af ' + dates.length;
  var maxD = parseInt(depthPicker.value) || 0;
  var curr = filterByDepth(SNAPSHOTS[d], SNAPSHOT_IDS[d] || [], maxD);
  var lines = curr.lines;
  var currIds = curr.ids;
  if (showDiff.checked && currentIdx > 0) {
    var prevDate = dates[currentIdx-1];
    var prev = filterByDepth(SNAPSHOTS[prevDate], SNAPSHOT_IDS[prevDate] || [], maxD);
    var prevLines = prev.lines;
    var prevIds = prev.ids;
    var prevSet = new Set(prevLines);
    var currSet = new Set(lines);

    // Byg linje → id mapping (til ID-baseret omdøbningsdetektion)
    var prevLineToId = {};
    var currLineToId = {};
    prevLines.forEach(function(l, i){ if(prevIds[i]) prevLineToId[l] = prevIds[i]; });
    lines.forEach(function(l, i){ if(currIds[i]) currLineToId[l] = currIds[i]; });

    // Beregn slettede og tilføjede linjer
    var removedLines = prevLines.filter(function(l){ return !currSet.has(l); });
    var addedLines   = lines.filter(function(l){ return !prevSet.has(l); });

    var renameByNew = {};      // nyt linje -> gammelt linje
    var renamedRemovedSet = new Set();
    var consumedAdded = new Set();

    // PRIMÆRT: ID-baseret omdøbningsdetektion
    var addedById = {};
    addedLines.forEach(function(l){
      var id = currLineToId[l];
      if (id) {
        (addedById[id] = addedById[id] || []).push(l);
      }
    });
    removedLines.forEach(function(l){
      var id = prevLineToId[l];
      if (id && addedById[id] && addedById[id].length > 0){
        var newL = addedById[id].shift();
        renameByNew[newL] = l;
        renamedRemovedSet.add(l);
        consumedAdded.add(newL);
      }
    });

    // FALLBACK: Navn-baseret heuristik for linjer uden ID-match
    var fallbackRemoved = removedLines.filter(function(l){ return !renamedRemovedSet.has(l); });
    var fallbackAdded   = addedLines.filter(function(l){ return !consumedAdded.has(l); });

    var removedByIdent = {};
    var addedByIdent   = {};
    fallbackRemoved.forEach(function(l){
      var id = getIdentity(l);
      (removedByIdent[id] = removedByIdent[id] || []).push(l);
    });
    fallbackAdded.forEach(function(l){
      var id = getIdentity(l);
      (addedByIdent[id] = addedByIdent[id] || []).push(l);
    });
    Object.keys(removedByIdent).forEach(function(id){
      if (id && removedByIdent[id].length === 1 && addedByIdent[id] && addedByIdent[id].length === 1){
        var oldL = removedByIdent[id][0];
        var newL = addedByIdent[id][0];
        renameByNew[newL] = oldL;
        renamedRemovedSet.add(oldL);
        consumedAdded.add(newL);
      }
    });

    // Byg output: først slettede (ikke del af omdøbning), dernæst nuværende rækkefølge
    var allLines = [];
    prevLines.forEach(function(l){
      if (!currSet.has(l) && !renamedRemovedSet.has(l)){
        allLines.push({t:l, s:'r'});
      }
    });
    lines.forEach(function(l){
      if (prevSet.has(l)) {
        allLines.push({t:l, s:''});
      } else if (renameByNew[l]) {
        allLines.push({t:l, s:'m', old: renameByNew[l]});
      } else {
        allLines.push({t:l, s:'a'});
      }
    });

    tree.innerHTML = allLines.map(function(o){
      if(o.s==='a') return '<span class="diff-added">+ '+esc(o.t)+'</span>';
      if(o.s==='r') return '<span class="diff-removed">- '+esc(o.t)+'</span>';
      if(o.s==='m'){
        var indent = (o.t.match(/^\s*/) || [''])[0];
        var oldName = o.old.replace(/^\s+/, '');
        var newName = o.t.replace(/^\s+/, '');
        return '<span class="diff-renamed">'+indent+'~ <span class="old">'+esc(oldName)+'</span><span class="arrow">&rarr;</span>'+esc(newName)+'</span>';
      }
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
depthPicker.addEventListener('change', function(){
  localStorage.setItem('mappehistorik_depth', depthPicker.value);
  render();
});

populateDepthPicker();
render();
</script>
</body>
</html>
"@
    Set-Content -Path $htmlFile -Value $htmlContent -Encoding UTF8
}

## Læs eksisterende HTML og indsæt/opdater dagens snapshot
$html = Get-Content -Path $htmlFile -Raw -Encoding UTF8

## SIKKERHEDSCHECK 1: Find alle eksisterende snapshot-datoer FØR ændring
$existingDates = [regex]::Matches($html, 'SNAPSHOTS\["(\d{4}-\d{2}-\d{2})"\]') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique

## SIKKERHEDSCHECK 2: Lav backup før enhver ændring (roterende .bak)
$backupFile = "$htmlFile.bak"
Copy-Item -Path $htmlFile -Destination $backupFile -Force

# Byg JS-arrays fra linjer og id'er
$jsLines = ($folders | ForEach-Object {
    '"' + ($_ -replace '\\', '\\\\' -replace '"', '\"') + '"'
}) -join ','

$jsIds = ($folderIds | ForEach-Object {
    '"' + $_ + '"'
}) -join ','

$linesEntry = "SNAPSHOTS[`"$today`"]=[$jsLines];"
$idsEntry   = "SNAPSHOT_IDS[`"$today`"]=[$jsIds];"

# Indsæt/opdater SNAPSHOTS[today]
if ($html -match "SNAPSHOTS\[`"$today`"\]") {
    $html = $html -replace "SNAPSHOTS\[`"$today`"\]\s*=\s*\[.*?\];", $linesEntry
} else {
    $html = $html -replace "// DATA_MARKER", "$linesEntry`n// DATA_MARKER"
}

# Indsæt/opdater SNAPSHOT_IDS[today]
if ($html -match "SNAPSHOT_IDS\[`"$today`"\]") {
    $html = $html -replace "SNAPSHOT_IDS\[`"$today`"\]\s*=\s*\[.*?\];", $idsEntry
} else {
    $html = $html -replace "// DATA_MARKER", "$idsEntry`n// DATA_MARKER"
}

## SIKKERHEDSCHECK 3: Verificér at ingen historiske datoer er tabt
$newDates = [regex]::Matches($html, 'SNAPSHOTS\["(\d{4}-\d{2}-\d{2})"\]') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique

$lostDates = $existingDates | Where-Object { $_ -notin $newDates }
if ($lostDates) {
    Write-Error "AFBRUDT: Sikkerhedscheck fejlede — følgende datoer ville blive tabt: $($lostDates -join ', '). Filen er IKKE ændret. Backup findes i $backupFile"
    exit 1
}

## SIKKERHEDSCHECK 4: Verificér at den nye streng indeholder DATA_MARKER (struktur intakt)
if ($html -notmatch "// DATA_MARKER") {
    Write-Error "AFBRUDT: DATA_MARKER mangler efter ændring — filen virker korrupt. Backup findes i $backupFile"
    exit 1
}

## SIKKERHEDSCHECK 5: Verificér minimum filstørrelse (beskyt mod tom fil)
if ($html.Length -lt 2000) {
    Write-Error "AFBRUDT: Ny HTML er mistænkeligt lille ($($html.Length) tegn). Backup findes i $backupFile"
    exit 1
}

Set-Content -Path $htmlFile -Value $html -Encoding UTF8

Write-Host "Snapshot gemt for $today ($($newDates.Count) snapshots i alt)"
