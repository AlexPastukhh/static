$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$templatePath = Join-Path $repoRoot "viewer\static-trace-v2.template.html"

if (-not (Test-Path $templatePath)) {
    throw "Missing template: $templatePath"
}

$html = [IO.File]::ReadAllText($templatePath)

# Add export button next to Folder colors.
$buttonNeedle = '<button id="settingsBtn">Folder colors</button>'
$buttonReplacement = @'
<button id="settingsBtn">Folder colors</button>
  <button id="exportBtn">Export current result</button>
'@

if (-not $html.Contains($buttonNeedle)) {
    throw "Could not find Folder colors button in template."
}

$html = $html.Replace($buttonNeedle, $buttonReplacement)

# Add export logic immediately before final initial render calls.
$renderNeedle = 'renderSidebar();renderMain();'

$exportJs = @'

function buildCurrentExport(){
  const depth=Math.max(1,Math.min(8,Number($("depth").value)||3));

  const payload={
    viewerVersion:"2.3",
    exportedAt:new Date().toISOString(),
    selectedMethod:selected ? selected.fullName : null,
    settings:{
      direction:$("direction").value,
      depth,
      showConstructors:$("constructors").checked,
      showExternal:$("external").checked,
      search:$("search").value
    },
    selectedMethodData:selected || null,
    directOutgoingCalls:selected ? (out.get(selected.fullName)||[]) : [],
    directIncomingCalls:selected ? (incoming.get(selected.fullName)||[]) : [],
    directExternalCalls:selected ? (externalByCaller.get(selected.fullName)||[]) : [],
    renderedText:$("main").innerText,
    renderedHtml:$("main").innerHTML
  };

  return payload;
}

function safeFileName(value){
  return String(value||"trace")
    .replace(/[^a-zA-Z0-9._-]+/g,"_")
    .replace(/^_+|_+$/g,"")
    .slice(0,120) || "trace";
}

$("exportBtn").onclick=()=>{
  const payload=buildCurrentExport();
  const json=JSON.stringify(payload,null,2);
  const blob=new Blob([json],{type:"application/json;charset=utf-8"});
  const url=URL.createObjectURL(blob);
  const a=document.createElement("a");

  a.href=url;
  a.download=`static-trace-${safeFileName(selected?.owner)}-${safeFileName(selected?.name)}.json`;

  document.body.appendChild(a);
  a.click();
  a.remove();

  setTimeout(()=>URL.revokeObjectURL(url),1000);
};

'@

# Insert only once.
if ($html.Contains('function buildCurrentExport()')) {
    Write-Host "Export support already present; skipping JS insertion."
}
else {
    $lastIndex = $html.LastIndexOf($renderNeedle)

    if ($lastIndex -lt 0) {
        throw "Could not find final renderSidebar();renderMain(); in template."
    }

    $html = $html.Insert($lastIndex, $exportJs)
}

$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($templatePath, $html, $utf8)

Write-Host "Patched viewer with current-result export."
Write-Host "Template: $templatePath"
Write-Host ""

$createScript = Join-Path $repoRoot "scripts\Create-StaticTraceExplorerV2.ps1"

if (-not (Test-Path $createScript)) {
    throw "Missing create script: $createScript"
}

& $createScript
