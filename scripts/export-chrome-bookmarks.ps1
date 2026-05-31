[CmdletBinding()]
param(
  [string]$BookmarksPath,
  [string]$Folder,
  [string]$OutputPage,
  [string]$SnapshotDirectory,
  [switch]$UseRemoteFavicons,
  [switch]$Open
)

$ErrorActionPreference = "Stop"

$SiteRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

if (-not $OutputPage) {
  $OutputPage = Join-Path $SiteRoot "bookmarks.html"
}

if (-not $SnapshotDirectory) {
  $SnapshotDirectory = Join-Path $SiteRoot "snapshots\bookmarks"
}

function Get-PropertyValue {
  param(
    [object]$Node,
    [string]$Name
  )

  if ($null -eq $Node) {
    return $null
  }

  $property = $Node.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function Get-ChildNodes {
  param([object]$Node)

  $children = Get-PropertyValue -Node $Node -Name "children"
  if ($null -eq $children) {
    return @()
  }

  return @($children)
}

function Test-BookmarkFolder {
  param([object]$Node)

  $type = Get-PropertyValue -Node $Node -Name "type"
  $children = Get-PropertyValue -Node $Node -Name "children"
  return ($type -eq "folder" -or $null -ne $children)
}

function Test-BookmarkUrl {
  param([object]$Node)

  $type = Get-PropertyValue -Node $Node -Name "type"
  $url = Get-PropertyValue -Node $Node -Name "url"
  return ($type -eq "url" -and -not [string]::IsNullOrWhiteSpace([string]$url))
}

function ConvertFrom-JsonCompat {
  param([string]$Json)

  $command = Get-Command ConvertFrom-Json
  if ($command.Parameters.ContainsKey("Depth")) {
    return $Json | ConvertFrom-Json -Depth 100
  }

  return $Json | ConvertFrom-Json
}

function Get-BookmarkFileCandidates {
  $profileRoots = @(
    (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"),
    (Join-Path $env:LOCALAPPDATA "Google\Chrome Beta\User Data"),
    (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data"),
    (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data"),
    (Join-Path $env:LOCALAPPDATA "Chromium\User Data")
  )

  foreach ($profileRoot in $profileRoots) {
    if (-not (Test-Path -LiteralPath $profileRoot)) {
      continue
    }

    Get-ChildItem -LiteralPath $profileRoot -Directory -ErrorAction SilentlyContinue |
      ForEach-Object {
        $bookmarksFile = Join-Path $_.FullName "Bookmarks"
        if (Test-Path -LiteralPath $bookmarksFile) {
          [pscustomobject]@{
            Browser = Split-Path (Split-Path $profileRoot -Parent) -Leaf
            Profile = $_.Name
            Path = $bookmarksFile
          }
        }
      }
  }
}

function Resolve-BookmarksPath {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path)) {
    return $Path.Trim([char]34)
  }

  $candidates = @(Get-BookmarkFileCandidates)

  if ($candidates.Count -eq 0) {
    return (Read-Host "没有自动找到 Bookmarks 文件，请输入完整路径").Trim([char]34)
  }

  Write-Host "找到以下 Bookmarks 文件："
  for ($i = 0; $i -lt $candidates.Count; $i++) {
    Write-Host ("  [{0}] {1} / {2} - {3}" -f ($i + 1), $candidates[$i].Browser, $candidates[$i].Profile, $candidates[$i].Path)
  }

  $answer = Read-Host "输入序号或完整路径，直接回车选 1"
  if ([string]::IsNullOrWhiteSpace($answer)) {
    return $candidates[0].Path
  }

  if ($answer -match "^\d+$") {
    $index = [int]$answer - 1
    if ($index -ge 0 -and $index -lt $candidates.Count) {
      return $candidates[$index].Path
    }
  }

  return $answer.Trim([char]34)
}

function Add-BookmarkFolder {
  param(
    [System.Collections.Generic.List[object]]$Folders,
    [object]$Node,
    [string[]]$PathParts
  )

  $Folders.Add([pscustomobject]@{
    Id = [string](Get-PropertyValue -Node $Node -Name "id")
    Name = [string](Get-PropertyValue -Node $Node -Name "name")
    Path = ($PathParts -join "/")
    Node = $Node
  }) | Out-Null

  foreach ($child in Get-ChildNodes -Node $Node) {
    if (-not (Test-BookmarkFolder -Node $child)) {
      continue
    }

    $childName = [string](Get-PropertyValue -Node $child -Name "name")
    if ([string]::IsNullOrWhiteSpace($childName)) {
      $childName = "未命名收藏夹"
    }

    Add-BookmarkFolder -Folders $Folders -Node $child -PathParts ($PathParts + $childName)
  }
}

function Get-BookmarkFolders {
  param([object]$BookmarkData)

  $folders = New-Object System.Collections.Generic.List[object]
  $roots = Get-PropertyValue -Node $BookmarkData -Name "roots"

  if ($null -eq $roots) {
    throw "Bookmarks 文件缺少 roots 节点。"
  }

  foreach ($property in $roots.PSObject.Properties) {
    if (-not (Test-BookmarkFolder -Node $property.Value)) {
      continue
    }

    $rootName = [string](Get-PropertyValue -Node $property.Value -Name "name")
    if ([string]::IsNullOrWhiteSpace($rootName)) {
      $rootName = $property.Name
    }

    Add-BookmarkFolder -Folders $folders -Node $property.Value -PathParts @($rootName)
  }

  return $folders.ToArray()
}

function Normalize-FolderQuery {
  param([string]$Query)

  $value = $Query.Trim()

  if ($value -match "[?&]id=([^&]+)") {
    $value = $Matches[1]
  }

  if ($value -match "^id=(.+)$") {
    $value = $Matches[1]
  }

  return (($value -replace "\\", "/") -replace "\s*/\s*", "/").Trim("/")
}

function Select-BookmarkFolder {
  param(
    [object[]]$Folders,
    [string]$Query
  )

  if ([string]::IsNullOrWhiteSpace($Query)) {
    Write-Host "可用收藏夹（最多显示前 80 个）："
    $max = [Math]::Min(80, $Folders.Count)
    for ($i = 0; $i -lt $max; $i++) {
      Write-Host ("  [{0}] id={1}  {2}" -f ($i + 1), $Folders[$i].Id, $Folders[$i].Path)
    }
    if ($Folders.Count -gt $max) {
      Write-Host ("  ... 还有 {0} 个，建议直接输入收藏夹 id 或路径。" -f ($Folders.Count - $max))
    }

    $Query = Read-Host "输入收藏夹 id、名称、路径，或 chrome://bookmarks/?id=..."
  }

  $normalized = Normalize-FolderQuery -Query $Query

  $matches = @($Folders | Where-Object { $_.Id -ieq $normalized })
  if ($matches.Count -eq 0) {
    $matches = @($Folders | Where-Object { $_.Path -ieq $normalized })
  }
  if ($matches.Count -eq 0) {
    $matches = @($Folders | Where-Object { $_.Name -ieq $normalized })
  }
  if ($matches.Count -eq 0) {
    $matches = @($Folders | Where-Object { $_.Path -like "*$normalized*" })
  }

  if ($matches.Count -eq 0) {
    throw "没有找到收藏夹：$Query"
  }

  if ($matches.Count -eq 1) {
    return $matches[0]
  }

  Write-Host "找到多个匹配项："
  for ($i = 0; $i -lt $matches.Count; $i++) {
    Write-Host ("  [{0}] id={1}  {2}" -f ($i + 1), $matches[$i].Id, $matches[$i].Path)
  }

  $answer = Read-Host "输入要导出的序号"
  if ($answer -notmatch "^\d+$") {
    throw "输入的序号无效。"
  }

  $index = [int]$answer - 1
  if ($index -lt 0 -or $index -ge $matches.Count) {
    throw "输入的序号超出范围。"
  }

  return $matches[$index]
}

function Get-DisplayHost {
  param([string]$Url)

  try {
    $hostName = ([Uri]$Url).Host
    if (-not [string]::IsNullOrWhiteSpace($hostName)) {
      return ($hostName -replace "^www\.", "")
    }
  } catch {
  }

  return $Url
}

function Add-BookmarkSections {
  param(
    [System.Collections.Generic.List[object]]$Sections,
    [object]$FolderNode,
    [string[]]$RelativePath
  )

  $items = New-Object System.Collections.Generic.List[object]

  foreach ($child in Get-ChildNodes -Node $FolderNode) {
    if (-not (Test-BookmarkUrl -Node $child)) {
      continue
    }

    $name = [string](Get-PropertyValue -Node $child -Name "name")
    $url = [string](Get-PropertyValue -Node $child -Name "url")

    if ([string]::IsNullOrWhiteSpace($name)) {
      $name = Get-DisplayHost -Url $url
    }

    $items.Add([pscustomobject]@{
      Name = $name
      Url = $url
      Description = Get-DisplayHost -Url $url
    }) | Out-Null
  }

  if ($items.Count -gt 0) {
    $title = "直接收藏"
    if ($RelativePath.Count -gt 0) {
      $title = $RelativePath -join " / "
    }

    $Sections.Add([pscustomobject]@{
      Title = $title
      Items = $items.ToArray()
    }) | Out-Null
  }

  foreach ($child in Get-ChildNodes -Node $FolderNode) {
    if (-not (Test-BookmarkFolder -Node $child)) {
      continue
    }

    $childName = [string](Get-PropertyValue -Node $child -Name "name")
    if ([string]::IsNullOrWhiteSpace($childName)) {
      $childName = "未命名收藏夹"
    }

    Add-BookmarkSections -Sections $Sections -FolderNode $child -RelativePath ($RelativePath + $childName)
  }
}

function Encode-Html {
  param([string]$Text)

  return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Get-BookmarkIcon {
  param([string]$Url)

  if ($UseRemoteFavicons) {
    return "https://www.google.com/s2/favicons?sz=64&domain_url=$([Uri]::EscapeDataString($Url))"
  }

  return "images/favicon.ico"
}

function Write-BookmarksPage {
  param(
    [object]$SelectedFolder,
    [object[]]$Sections,
    [string]$Path,
    [string]$SnapshotPath
  )

  $total = 0
  foreach ($section in $Sections) {
    $total += $section.Items.Count
  }

  $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $title = "收藏夹"
  if (-not [string]::IsNullOrWhiteSpace($SelectedFolder.Name)) {
    $title = $SelectedFolder.Name
  }

  $builder = New-Object System.Text.StringBuilder

  function Add-Line {
    param([string]$Line = "")
    $builder.AppendLine($Line) | Out-Null
  }

  Add-Line "<!DOCTYPE html>"
  Add-Line "<html lang=`"zh-CN`">"
  Add-Line "<head>"
  Add-Line "  <meta charset=`"UTF-8`">"
  Add-Line "  <meta name=`"viewport`" content=`"width=device-width, initial-scale=1`">"
  Add-Line "  <meta http-equiv=`"Cache-Control`" content=`"no-transform`">"
  Add-Line "  <meta http-equiv=`"Cache-Control`" content=`"no-siteapp`">"
  Add-Line "  <meta name=`"applicable-device`" content=`"pc,mobile`">"
  Add-Line "  <meta name=`"keywords`" content=`"个人导航,收藏夹`">"
  Add-Line ("  <meta name=`"description`" content=`"Chrome 收藏夹导出：{0}`">" -f (Encode-Html $SelectedFolder.Path))
  Add-Line ("  <title>{0} - 收藏导航</title>" -f (Encode-Html $title))
  Add-Line "  <link rel=`"stylesheet`" href=`"css/ops-coffee.css`" type=`"text/css`">"
  Add-Line "  <link rel=`"shortcut icon`" href=`"images/favicon.ico`">"
  Add-Line "  <link rel=`"preload`" as=`"image`" href=`"images/beijing.jpg`">"
  Add-Line "  <style>"
  Add-Line "    .bookmark-page-header {"
  Add-Line "      margin: 0 10px 20px;"
  Add-Line "      padding: 14px 16px;"
  Add-Line "      text-align: left;"
  Add-Line "      border: 1px solid var(--card-border);"
  Add-Line "      border-radius: 15px;"
  Add-Line "      color: var(--title-color);"
  Add-Line "      background: var(--card-bg);"
  Add-Line "      backdrop-filter: var(--surface-blur);"
  Add-Line "      -webkit-backdrop-filter: var(--surface-blur);"
  Add-Line "    }"
  Add-Line ""
  Add-Line "    .bookmark-page-title {"
  Add-Line "      margin: 0;"
  Add-Line "      font-size: 20px;"
  Add-Line "      line-height: 1.4;"
  Add-Line "      letter-spacing: 0;"
  Add-Line "    }"
  Add-Line ""
  Add-Line "    .bookmark-page-meta {"
  Add-Line "      margin: 6px 0 0;"
  Add-Line "      color: var(--text-muted);"
  Add-Line "      font-size: 12px;"
  Add-Line "      line-height: 1.6;"
  Add-Line "      word-break: break-all;"
  Add-Line "    }"
  Add-Line ""
  Add-Line "    .bookmark-empty {"
  Add-Line "      margin: 0 10px;"
  Add-Line "      padding: 16px;"
  Add-Line "      text-align: left;"
  Add-Line "      color: var(--text-muted);"
  Add-Line "      border: 1px solid var(--card-border);"
  Add-Line "      border-radius: 15px;"
  Add-Line "      background: var(--card-bg);"
  Add-Line "    }"
  Add-Line ""
  Add-Line "    body.site-page[data-density=`"compact`"] .bookmark-page-header {"
  Add-Line "      margin-bottom: 12px;"
  Add-Line "      padding: 10px 12px;"
  Add-Line "      border-radius: 10px;"
  Add-Line "    }"
  Add-Line "  </style>"
  Add-Line "</head>"
  Add-Line "<body class=`"site-page`" data-page=`"bookmarks`">"
  Add-Line "  <div class=`"header`" data-site-header></div>"
  Add-Line ""
  Add-Line "  <main id=`"content-wrapper`">"
  Add-Line "    <div class=`"container`">"
  Add-Line "      <section class=`"bookmark-page-header`" aria-label=`"收藏夹信息`">"
  Add-Line ("        <h1 class=`"bookmark-page-title`">{0}</h1>" -f (Encode-Html $title))
  Add-Line ("        <p class=`"bookmark-page-meta`">来源：{0} · {1} 个链接 · 生成时间：{2}</p>" -f (Encode-Html $SelectedFolder.Path), $total, (Encode-Html $generatedAt))
  Add-Line ("        <p class=`"bookmark-page-meta`">快照：{0}</p>" -f (Encode-Html $SnapshotPath))
  Add-Line "      </section>"

  if ($Sections.Count -eq 0) {
    Add-Line "      <p class=`"bookmark-empty`">这个收藏夹下面没有可导出的链接。</p>"
  } else {
    for ($sectionIndex = 0; $sectionIndex -lt $Sections.Count; $sectionIndex++) {
      $section = $Sections[$sectionIndex]
      $sectionId = "bookmarks-section-$sectionIndex"

      Add-Line ("      <section class=`"nav-cell clearfix`" aria-labelledby=`"{0}`">" -f $sectionId)
      Add-Line ("        <h2 class=`"nav-section-title`" id=`"{0}`">{1}</h2>" -f $sectionId, (Encode-Html $section.Title))
      Add-Line "        <ul class=`"nav-list`">"

      foreach ($item in $section.Items) {
        $itemName = Encode-Html $item.Name
        $itemUrl = Encode-Html $item.Url
        $itemDescription = Encode-Html $item.Description
        $itemIcon = Encode-Html (Get-BookmarkIcon -Url $item.Url)

        Add-Line "          <li>"
        Add-Line ("            <a class=`"nav-item clearfix has-description`" href=`"{0}`" target=`"_blank`" rel=`"noopener noreferrer`" aria-label=`"{1}：{2}`">" -f $itemUrl, $itemName, $itemDescription)
        Add-Line ("              <img class=`"nav-img`" src=`"{0}`" alt=`"`" loading=`"lazy`" decoding=`"async`">" -f $itemIcon)
        Add-Line ("              <div class=`"nav-name`">{0}</div>" -f $itemName)
        Add-Line ("              <p>{0}</p>" -f $itemDescription)
        Add-Line "            </a>"
        Add-Line "          </li>"
      }

      Add-Line "        </ul>"
      Add-Line "      </section>"
    }
  }

  Add-Line "    </div>"
  Add-Line "  </main>"
  Add-Line ""
  Add-Line "  <script src=`"js/site-shell.js`"></script>"
  Add-Line "  <script>"
  Add-Line "    (() => {"
  Add-Line "      const list = document.querySelector(`".header-menu ul`");"
  Add-Line "      if (!list) {"
  Add-Line "        return;"
  Add-Line "      }"
  Add-Line ""
  Add-Line "      const item = document.createElement(`"li`");"
  Add-Line "      const link = document.createElement(`"a`");"
  Add-Line "      item.className = `"current-menu-item`";"
  Add-Line "      link.href = `"bookmarks.html`";"
  Add-Line "      link.textContent = `"收藏`";"
  Add-Line "      link.setAttribute(`"aria-current`", `"page`");"
  Add-Line "      item.append(link);"
  Add-Line "      list.append(item);"
  Add-Line "    })();"
  Add-Line "  </script>"
  Add-Line "  <script src=`"js/site-preferences.js`"></script>"
  Add-Line "  <script src=`"js/liquid-glass.js`" defer></script>"
  Add-Line "  <script src=`"js/background-loader.js`"></script>"
  Add-Line "</body>"
  Add-Line "</html>"

  $outputDirectory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
  }

  Set-Content -LiteralPath $Path -Value $builder.ToString() -Encoding UTF8
  return $total
}

$BookmarksPath = Resolve-BookmarksPath -Path $BookmarksPath

if (-not (Test-Path -LiteralPath $BookmarksPath)) {
  throw "Bookmarks 文件不存在：$BookmarksPath"
}

New-Item -ItemType Directory -Force -Path $SnapshotDirectory | Out-Null
$snapshotPath = Join-Path $SnapshotDirectory ("Bookmarks-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
Copy-Item -LiteralPath $BookmarksPath -Destination $snapshotPath -Force

$rawBookmarks = Get-Content -LiteralPath $snapshotPath -Raw -Encoding UTF8
$bookmarkData = ConvertFrom-JsonCompat -Json $rawBookmarks
$folders = @(Get-BookmarkFolders -BookmarkData $bookmarkData)

if ($folders.Count -eq 0) {
  throw "没有从 Bookmarks 文件中解析到收藏夹。"
}

$selectedFolder = Select-BookmarkFolder -Folders $folders -Query $Folder
$sections = New-Object System.Collections.Generic.List[object]
Add-BookmarkSections -Sections $sections -FolderNode $selectedFolder.Node -RelativePath @()

$count = Write-BookmarksPage -SelectedFolder $selectedFolder -Sections ($sections.ToArray()) -Path $OutputPage -SnapshotPath $snapshotPath

Write-Host ("已复制 Bookmarks 快照：{0}" -f $snapshotPath)
Write-Host ("已导出收藏夹：id={0}  {1}" -f $selectedFolder.Id, $selectedFolder.Path)
Write-Host ("已生成页面：{0}" -f $OutputPage)
Write-Host ("导出链接数：{0}" -f $count)

if ($Open) {
  Start-Process -FilePath $OutputPage
}
