# Dump every flavor the Windows clipboard is offering, byte-exactly.
#
#   powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File clipdump.ps1 <label> [outdir]
#
# Writes <outdir>\<label>.formats, .plain.txt, .html.txt, .rtf.txt as UTF-8
# with NO byte order mark, because a BOM added by the tool would corrupt the
# very thing we are measuring. -Sta is required: the clipboard API needs a
# single-threaded apartment and silently returns nothing without it.

param(
  [Parameter(Mandatory = $true)][string]$Label,
  [string]$OutDir = "$env:USERPROFILE\clipdump"
)

Add-Type -AssemblyName System.Windows.Forms | Out-Null
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Write-Utf8NoBom($path, $text) {
  if ($null -eq $text) { return $false }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
  return $true
}

$data = [System.Windows.Forms.Clipboard]::GetDataObject()
if ($null -eq $data) { Write-Host "clipboard is empty"; exit 1 }

$formats = $data.GetFormats()
Write-Utf8NoBom "$OutDir\$Label.formats" ($formats -join "`n") | Out-Null
Write-Host "=== flavors offered"
$formats | ForEach-Object { Write-Host "    $_" }

$kinds = @{
  'plain' = [System.Windows.Forms.TextDataFormat]::UnicodeText
  'html'  = [System.Windows.Forms.TextDataFormat]::Html
  'rtf'   = [System.Windows.Forms.TextDataFormat]::Rtf
}
foreach ($name in @('plain', 'html', 'rtf')) {
  $text = [System.Windows.Forms.Clipboard]::GetText($kinds[$name])
  if ([string]::IsNullOrEmpty($text)) { continue }
  $path = "$OutDir\$Label.$name.txt"
  Write-Utf8NoBom $path $text | Out-Null
  Write-Host ("=== {0}: {1} chars -> {2}" -f $name, $text.Length, $path)
}

# The plain flavor as hex, so a stripped backtick, a lost '>', a CRLF or an
# NBSP is visible rather than inferred.
$plain = [System.Windows.Forms.Clipboard]::GetText([System.Windows.Forms.TextDataFormat]::UnicodeText)
if (-not [string]::IsNullOrEmpty($plain)) {
  Write-Host "=== plain flavor (60 = backtick, 3E = '>', 0D = CR, C2A0 = NBSP)"
  $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($plain)
  for ($i = 0; $i -lt $bytes.Length; $i += 16) {
    $slice = $bytes[$i..([Math]::Min($i + 15, $bytes.Length - 1))]
    $hex = ($slice | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
    $asc = -join ($slice | ForEach-Object {
        if ($_ -ge 32 -and $_ -lt 127) { [char]$_ } else { '.' } })
    Write-Host ('{0:x8}  {1,-47}  {2}' -f $i, $hex, $asc)
  }
}
