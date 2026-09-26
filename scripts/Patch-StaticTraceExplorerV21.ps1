$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$templatePath = Join-Path $repoRoot "viewer\static-trace-v2.template.html"

if (-not (Test-Path $templatePath)) {
    throw "Missing template: $templatePath"
}

$html = [IO.File]::ReadAllText($templatePath)

$oldFolder = @'
function folderOf(m){
  let f=String(m?.file||"").replaceAll("\\\\","/");
  let i=f.lastIndexOf("/");
  let folder=i>=0?f.slice(0,i):"(root)";
  folder=folder.replace(/^gdcap\//,"");
  return folder||"(root)";
}
'@

$newFolder = @'
function folderOf(m){
  let f=String(m?.file||"").replaceAll("\\\\","/");

  // Keep only the directory part.
  const i=f.lastIndexOf("/");
  let folder=i>=0?f.slice(0,i):"(root)";

  // Normalize absolute / prefixed paths to the application-relative part.
  // Examples:
  //   C:/gd-cap/java-src/gdcap/features/copy -> features/copy
  //   java-src/gdcap/ui/main                 -> ui/main
  //   gdcap/shared/notepersistence           -> shared/notepersistence
  const marker="/gdcap/";
  const pos=folder.toLowerCase().lastIndexOf(marker);

  if(pos>=0){
    folder=folder.slice(pos+marker.length);
  }else{
    folder=folder.replace(/^gdcap\//i,"");
  }

  return folder||"(root)";
}
'@

$oldColor = @'
function colorForFolder(folder){
  const rules=configuredColorRules();
  let best=null;
  for(const prefix of Object.keys(rules)){
    if(prefix==="(root)"&&folder==="(root)"){best=prefix;continue}
    if(folder.startsWith(prefix) && (!best || prefix.length>best.length))best=prefix;
  }
  return best?rules[best]:"#6e7681";
}
'@

$newColor = @'
function colorForFolder(folder){
  const rules=configuredColorRules();
  const normalized=String(folder||"").replaceAll("\\\\","/").replace(/^\/+/,"");

  let best=null;

  for(const prefix of Object.keys(rules)){
    if(prefix==="(root)" && normalized==="(root)"){
      best=prefix;
      continue;
    }

    const p=String(prefix).replaceAll("\\\\","/").replace(/^\/+/,"");

    // Match either from the beginning or as a complete path segment.
    const matches =
      normalized.startsWith(p) ||
      normalized.includes("/"+p);

    if(matches && (!best || p.length>best.length)){
      best=prefix;
    }
  }

  return best ? rules[best] : "#6e7681";
}
'@

if (-not $html.Contains($oldFolder)) {
    throw "Could not find folderOf() block to patch. V2 template may differ."
}
if (-not $html.Contains($oldColor)) {
    throw "Could not find colorForFolder() block to patch. V2 template may differ."
}

$html = $html.Replace($oldFolder, $newFolder)
$html = $html.Replace($oldColor, $newColor)

$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($templatePath, $html, $utf8)

Write-Host "Patched: $templatePath"
Write-Host ""

$createScript = Join-Path $repoRoot "scripts\Create-StaticTraceExplorerV2.ps1"

if (Test-Path $createScript) {
    & $createScript
}
else {
    Write-Host "Create script not found:"
    Write-Host "  $createScript"
}
