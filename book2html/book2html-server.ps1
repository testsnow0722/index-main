[CmdletBinding()]
param(
  [int]$Port = 8765,
  [string]$SiteRoot,
  [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$script:StopRequested = $false

function Test-Book2HtmlResourceRoot {
  param([string]$Root)

  if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root -PathType Container)) {
    return $false
  }

  $requiredFiles = @(
    "css\ops-coffee.css",
    "js\site-shell.js",
    "js\site-preferences.js",
    "js\liquid-glass.js",
    "js\background-loader.js",
    "images\favicon.ico",
    "images\beijing.jpg"
  )

  foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) {
      return $false
    }
  }

  return $true
}

function Resolve-Book2HtmlSiteContext {
  param([string]$RequestedSiteRoot)

  if (-not [string]::IsNullOrWhiteSpace($RequestedSiteRoot)) {
    $resolved = (Resolve-Path -LiteralPath $RequestedSiteRoot).Path
    if (-not (Test-Book2HtmlResourceRoot -Root $resolved)) {
      throw "指定的 SiteRoot 缺少运行资源，请确认其中包含 css、js、images。"
    }

    return [pscustomobject]@{
      siteRoot = $resolved
      resourceRoot = $resolved
      resourcePrefix = ""
      resourceMode = "custom"
      isMinimalMode = $false
    }
  }

  $scriptRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
  $parentRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot "..")).Path
  $dataRoot = Join-Path $scriptRoot "data"

  if (Test-Book2HtmlResourceRoot -Root $parentRoot) {
    return [pscustomobject]@{
      siteRoot = $parentRoot
      resourceRoot = $parentRoot
      resourcePrefix = ""
      resourceMode = "parent"
      isMinimalMode = $false
    }
  }

  if (Test-Book2HtmlResourceRoot -Root $scriptRoot) {
    return [pscustomobject]@{
      siteRoot = $scriptRoot
      resourceRoot = $scriptRoot
      resourcePrefix = ""
      resourceMode = "sibling"
      isMinimalMode = $false
    }
  }

  if (Test-Book2HtmlResourceRoot -Root $dataRoot) {
    return [pscustomobject]@{
      siteRoot = $scriptRoot
      resourceRoot = $dataRoot
      resourcePrefix = "data/"
      resourceMode = "data"
      isMinimalMode = $true
    }
  }

  throw "没有找到运行资源。请在父目录、脚本同级目录或 data 目录中放置 css、js、images。"
}

$siteContext = Resolve-Book2HtmlSiteContext -RequestedSiteRoot $SiteRoot
$SiteRoot = $siteContext.siteRoot
$script:ResourceRoot = $siteContext.resourceRoot
$script:ResourcePrefix = $siteContext.resourcePrefix
$script:ResourceMode = $siteContext.resourceMode
$script:IsMinimalMode = $siteContext.isMinimalMode

$DefaultOutputPage = Join-Path $SiteRoot "bookmarks.html"
$SnapshotDirectory = Join-Path $PSScriptRoot "snapshots"
$script:LastOutputPage = $null

function Clear-BookmarkSnapshotCache {
  if (-not (Test-Path -LiteralPath $SnapshotDirectory)) {
    return
  }

  Get-ChildItem -LiteralPath $SnapshotDirectory -Filter "Bookmarks-*" -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

function ConvertFrom-JsonCompat {
  param([string]$Json)

  $command = Get-Command ConvertFrom-Json
  if ($command.Parameters.ContainsKey("Depth")) {
    return $Json | ConvertFrom-Json -Depth 100
  }

  return $Json | ConvertFrom-Json
}

function ConvertTo-JsonCompat {
  param([object]$Value)

  $command = Get-Command ConvertTo-Json
  if ($command.Parameters.ContainsKey("Depth")) {
    return $Value | ConvertTo-Json -Depth 20
  }

  return $Value | ConvertTo-Json
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

function Get-LocalAppDataPath {
  $candidates = @(
    $env:LOCALAPPDATA,
    [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),
    (Join-Path $env:USERPROFILE "AppData\Local")
  )

  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
    if (Test-Path -LiteralPath $expanded -PathType Container) {
      return $expanded
    }
  }

  return $env:LOCALAPPDATA
}

function Get-BookmarkFileCandidates {
  $localAppData = Get-LocalAppDataPath
  $profileRoots = @(
    @{ Browser = "Chrome"; Path = (Join-Path $localAppData "Google\Chrome\User Data") },
    @{ Browser = "Chrome Beta"; Path = (Join-Path $localAppData "Google\Chrome Beta\User Data") },
    @{ Browser = "Edge"; Path = (Join-Path $localAppData "Microsoft\Edge\User Data") },
    @{ Browser = "Brave"; Path = (Join-Path $localAppData "BraveSoftware\Brave-Browser\User Data") },
    @{ Browser = "Chromium"; Path = (Join-Path $localAppData "Chromium\User Data") }
  )

  $result = New-Object System.Collections.Generic.List[object]

  foreach ($profileRoot in $profileRoots) {
    if (-not (Test-Path -LiteralPath $profileRoot.Path)) {
      continue
    }

    Get-ChildItem -LiteralPath $profileRoot.Path -Directory -ErrorAction SilentlyContinue |
      ForEach-Object {
        $bookmarksFile = Join-Path $_.FullName "Bookmarks"
        if (Test-Path -LiteralPath $bookmarksFile) {
          $file = Get-Item -LiteralPath $bookmarksFile
          $result.Add([pscustomobject]@{
            browser = $profileRoot.Browser
            profile = $_.Name
            path = $bookmarksFile
            length = $file.Length
            lastWriteTime = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
          }) | Out-Null
        }
      }
  }

  return $result.ToArray()
}

function Resolve-BookmarksSourcePath {
  param([string]$BookmarksPath)

  if ([string]::IsNullOrWhiteSpace($BookmarksPath)) {
    throw "请选择或输入 Bookmarks 文件路径。"
  }

  $resolved = [Environment]::ExpandEnvironmentVariables($BookmarksPath).Trim([char]34)
  if (-not (Test-Path -LiteralPath $resolved)) {
    throw "Bookmarks 文件不存在：$resolved"
  }

  return (Resolve-Path -LiteralPath $resolved).Path
}

function Copy-BookmarksSnapshot {
  param([string]$BookmarksPath)

  $sourcePath = Resolve-BookmarksSourcePath -BookmarksPath $BookmarksPath
  New-Item -ItemType Directory -Force -Path $SnapshotDirectory | Out-Null

  $snapshotPath = Join-Path $SnapshotDirectory ("Bookmarks-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
  Copy-Item -LiteralPath $sourcePath -Destination $snapshotPath -Force

  return [pscustomobject]@{
    sourcePath = $sourcePath
    snapshotPath = $snapshotPath
  }
}

function Read-BookmarksFile {
  param([string]$BookmarksPath)

  $resolved = Resolve-BookmarksSourcePath -BookmarksPath $BookmarksPath

  $raw = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8
  $data = ConvertFrom-JsonCompat -Json $raw

  return [pscustomobject]@{
    path = $resolved
    data = $data
  }
}

function Get-BookmarkUrlCount {
  param([object]$Node)

  $count = 0
  foreach ($child in Get-ChildNodes -Node $Node) {
    if (Test-BookmarkUrl -Node $child) {
      $count++
      continue
    }

    if (Test-BookmarkFolder -Node $child) {
      $count += Get-BookmarkUrlCount -Node $child
    }
  }

  return $count
}

function Get-DirectBookmarkUrlCount {
  param([object]$Node)

  $count = 0
  foreach ($child in Get-ChildNodes -Node $Node) {
    if (Test-BookmarkUrl -Node $child) {
      $count++
    }
  }

  return $count
}

function Add-BookmarkFolder {
  param(
    [System.Collections.Generic.List[object]]$Folders,
    [object]$Node,
    [string[]]$PathParts
  )

  $folderName = [string](Get-PropertyValue -Node $Node -Name "name")
  if ([string]::IsNullOrWhiteSpace($folderName)) {
    $folderName = "未命名收藏夹"
  }

  $Folders.Add([pscustomobject]@{
    id = [string](Get-PropertyValue -Node $Node -Name "id")
    name = $folderName
    path = ($PathParts -join "/")
    directCount = Get-DirectBookmarkUrlCount -Node $Node
    totalCount = Get-BookmarkUrlCount -Node $Node
    node = $Node
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

function Get-SerializableFolders {
  param([object[]]$Folders)

  $result = New-Object System.Collections.Generic.List[object]
  foreach ($folder in $Folders) {
    $result.Add([pscustomobject]@{
      id = $folder.id
      name = $folder.name
      path = $folder.path
      directCount = $folder.directCount
      totalCount = $folder.totalCount
    }) | Out-Null
  }

  return $result.ToArray()
}

function ConvertTo-SerializableFolderTree {
  param(
    [object]$Node,
    [string[]]$PathParts
  )

  $folderName = [string](Get-PropertyValue -Node $Node -Name "name")
  if ([string]::IsNullOrWhiteSpace($folderName)) {
    $folderName = "未命名收藏夹"
  }

  $children = New-Object System.Collections.Generic.List[object]
  foreach ($child in Get-ChildNodes -Node $Node) {
    if (-not (Test-BookmarkFolder -Node $child)) {
      continue
    }

    $childName = [string](Get-PropertyValue -Node $child -Name "name")
    if ([string]::IsNullOrWhiteSpace($childName)) {
      $childName = "未命名收藏夹"
    }

    $children.Add((ConvertTo-SerializableFolderTree -Node $child -PathParts ($PathParts + $childName))) | Out-Null
  }

  return [pscustomobject]@{
    id = [string](Get-PropertyValue -Node $Node -Name "id")
    name = $folderName
    path = ($PathParts -join "/")
    directCount = Get-DirectBookmarkUrlCount -Node $Node
    totalCount = Get-BookmarkUrlCount -Node $Node
    childCount = $children.Count
    children = $children.ToArray()
  }
}

function Get-BookmarkFolderTree {
  param([object]$BookmarkData)

  $tree = New-Object System.Collections.Generic.List[object]
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

    $tree.Add((ConvertTo-SerializableFolderTree -Node $property.Value -PathParts @($rootName))) | Out-Null
  }

  return $tree.ToArray()
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
    throw "请选择收藏夹，或输入收藏夹 id / 名称 / 路径。"
  }

  $normalized = Normalize-FolderQuery -Query $Query
  $matches = @($Folders | Where-Object { $_.id -ieq $normalized })
  if ($matches.Count -eq 0) {
    $matches = @($Folders | Where-Object { $_.path -ieq $normalized })
  }
  if ($matches.Count -eq 0) {
    $matches = @($Folders | Where-Object { $_.name -ieq $normalized })
  }
  if ($matches.Count -eq 0) {
    $matches = @($Folders | Where-Object { $_.path -like "*$normalized*" })
  }

  if ($matches.Count -eq 0) {
    throw "没有找到收藏夹：$Query"
  }
  if ($matches.Count -gt 1) {
    $sample = ($matches | Select-Object -First 8 | ForEach-Object { "id=$($_.id) $($_.path)" }) -join "；"
    throw "找到多个收藏夹，请选中列表中的具体项或输入 id。匹配项：$sample"
  }

  return $matches[0]
}

function Select-BookmarkFolders {
  param(
    [object[]]$Folders,
    [object[]]$Queries
  )

  if ($null -eq $Queries -or @($Queries).Count -eq 0) {
    throw "请至少选择一个收藏夹。"
  }

  $selected = New-Object System.Collections.Generic.List[object]
  $seen = @{}
  foreach ($query in @($Queries)) {
    $queryText = [string]$query
    if ([string]::IsNullOrWhiteSpace($queryText)) {
      continue
    }

    $folder = Select-BookmarkFolder -Folders $Folders -Query $queryText
    $seenKey = $folder.id.ToLowerInvariant()
    if ($seen.ContainsKey($seenKey)) {
      continue
    }

    $seen[$seenKey] = $true
    $selected.Add($folder) | Out-Null
  }

  if ($selected.Count -eq 0) {
    throw "请至少选择一个收藏夹。"
  }

  return $selected.ToArray()
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
      name = $name
      url = $url
      description = Get-DisplayHost -Url $url
    }) | Out-Null
  }

  if ($items.Count -gt 0) {
    $title = "直接收藏"
    if ($RelativePath.Count -gt 0) {
      $title = $RelativePath -join " / "
    }

    $Sections.Add([pscustomobject]@{
      title = $title
      items = $items.ToArray()
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
  param(
    [string]$Url,
    [bool]$UseRemoteFavicons
  )

  if ($UseRemoteFavicons) {
    return "https://www.google.com/s2/favicons?sz=64&domain_url=$([Uri]::EscapeDataString($Url))"
  }

  return "$($script:ResourcePrefix)images/favicon.ico"
}

function ConvertTo-SafeBookmarkFileName {
  param([string]$Name)

  $safe = [string]$Name
  if ([string]::IsNullOrWhiteSpace($safe)) {
    $safe = "收藏夹"
  }

  $invalidPattern = "[{0}]" -f [Regex]::Escape((-join [System.IO.Path]::GetInvalidFileNameChars()))
  $safe = $safe -replace $invalidPattern, "_"
  $safe = $safe -replace "\s+", "_"
  $safe = $safe.Trim("._ ")

  if ([string]::IsNullOrWhiteSpace($safe)) {
    $safe = "收藏夹"
  }

  if ($safe.Length -gt 80) {
    $safe = $safe.Substring(0, 80).Trim("._ ")
  }

  return $safe
}

function Get-NextSequencedPath {
  param([string]$Path)

  $directory = Split-Path -Parent $Path
  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
  $extension = [System.IO.Path]::GetExtension($Path)

  for ($index = 2; $index -lt 10000; $index++) {
    $candidate = Join-Path $directory ("{0}_{1}{2}" -f $baseName, $index, $extension)
    if (-not (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }

  throw "无法找到可用的序号文件名。"
}

function Resolve-BookmarkOutputPath {
  param(
    [string]$FolderName,
    [string]$ConflictAction
  )

  $safeName = ConvertTo-SafeBookmarkFileName -Name $FolderName
  $targetPath = Join-Path $SiteRoot ("bookmarks_{0}.html" -f $safeName)

  if (-not (Test-Path -LiteralPath $targetPath)) {
    return [pscustomobject]@{
      conflict = $false
      path = $targetPath
      fileName = Split-Path -Leaf $targetPath
      overwritten = $false
    }
  }

  if ($ConflictAction -eq "overwrite") {
    return [pscustomobject]@{
      conflict = $false
      path = $targetPath
      fileName = Split-Path -Leaf $targetPath
      overwritten = $true
    }
  }

  $sequencedPath = Get-NextSequencedPath -Path $targetPath
  if ($ConflictAction -eq "sequence") {
    return [pscustomobject]@{
      conflict = $false
      path = $sequencedPath
      fileName = Split-Path -Leaf $sequencedPath
      overwritten = $false
    }
  }

  return [pscustomobject]@{
    conflict = $true
    existingPath = $targetPath
    existingFileName = Split-Path -Leaf $targetPath
    suggestedPath = $sequencedPath
    suggestedFileName = Split-Path -Leaf $sequencedPath
  }
}

function ConvertTo-JsString {
  param([string]$Value)

  return ((ConvertTo-JsonCompat -Value ([string]$Value)) -replace "</", "<\/")
}

function New-BookmarkNavScriptBlock {
  param([object[]]$Entries)

  $items = New-Object System.Collections.Generic.List[string]
  foreach ($entry in $Entries) {
    if ([string]::IsNullOrWhiteSpace([string]$entry.href) -or [string]::IsNullOrWhiteSpace([string]$entry.label)) {
      continue
    }

    $items.Add(("{{ href: {0}, label: {1} }}" -f (ConvertTo-JsString $entry.href), (ConvertTo-JsString $entry.label))) | Out-Null
  }

  $pagesLiteral = "[" + ($items -join ", ") + "]"

  return @"
  <script data-book2html-nav>
    (() => {
      const pages = $pagesLiteral;
      const list = document.querySelector(".header-menu ul");
      if (!list) return;

      const currentFile = decodeURIComponent((location.pathname.split("/").pop() || "index.html"));
      const existingHrefs = new Set([...list.querySelectorAll("a")].map((link) => link.getAttribute("href")));

      pages.forEach((page) => {
        if (!page.href || !page.label || existingHrefs.has(page.href)) return;

        const item = document.createElement("li");
        const link = document.createElement("a");

        if (page.href === currentFile) {
          item.className = "current-menu-item";
          link.setAttribute("aria-current", "page");
        }

        link.href = page.href;
        link.textContent = page.label;
        item.append(link);
        list.append(item);
        existingHrefs.add(page.href);
      });
    })();
  </script>
"@
}

function Get-BookmarkPageLabel {
  param(
    [string]$Path,
    [string]$Fallback
  )

  try {
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content -match "(?is)<title>\s*(?<label>.*?)\s+-\s*收藏导航\s*</title>") {
      return [System.Net.WebUtility]::HtmlDecode($Matches["label"]).Trim()
    }
  } catch {
  }

  if (-not [string]::IsNullOrWhiteSpace($Fallback)) {
    return $Fallback
  }

  $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
  if ($name -like "bookmarks_*") {
    return $name.Substring("bookmarks_".Length)
  }

  return $name
}

function Get-BookmarkPageEntries {
  param(
    [string]$CurrentOutputPage,
    [string]$CurrentLabel
  )

  $entries = New-Object System.Collections.Generic.List[object]
  $seen = @{}
  $currentResolved = $null
  if (-not [string]::IsNullOrWhiteSpace($CurrentOutputPage) -and (Test-Path -LiteralPath $CurrentOutputPage)) {
    $currentResolved = (Resolve-Path -LiteralPath $CurrentOutputPage).Path
  }

  Get-ChildItem -LiteralPath $SiteRoot -File -Filter "bookmarks_*.html" -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object {
      $label = Get-BookmarkPageLabel -Path $_.FullName -Fallback $null
      if ($currentResolved -and $_.FullName -ieq $currentResolved) {
        $label = $CurrentLabel
      }

      if (-not [string]::IsNullOrWhiteSpace($label)) {
        $seenKey = $_.Name.ToLowerInvariant()
        if (-not $seen.ContainsKey($seenKey)) {
          $seen[$seenKey] = $true
          $entries.Add([pscustomobject]@{
            href = $_.Name
            label = $label
          }) | Out-Null
        }
      }
    }

  return $entries.ToArray()
}

function Get-SiteNavigationEntries {
  $entries = New-Object System.Collections.Generic.List[object]
  $basePages = @(
    @{ href = "index.html"; label = "首页" },
    @{ href = "common.html"; label = "常用" },
    @{ href = "develop.html"; label = "开发" },
    @{ href = "tools.html"; label = "工具" }
  )

  foreach ($page in $basePages) {
    $fullPath = Join-Path $SiteRoot $page.href
    if (Test-Path -LiteralPath $fullPath) {
      $resolved = (Resolve-Path -LiteralPath $fullPath).Path
      $entries.Add([pscustomobject]@{
        href = (New-Object System.Uri($resolved)).AbsoluteUri
        path = $page.href
        label = $page.label
      }) | Out-Null
    }
  }

  foreach ($entry in @(Get-BookmarkPageEntries -CurrentOutputPage $null -CurrentLabel $null)) {
    $fullPath = Join-Path $SiteRoot $entry.href
    if (-not (Test-Path -LiteralPath $fullPath)) {
      continue
    }
    $resolved = (Resolve-Path -LiteralPath $fullPath).Path
    $entries.Add([pscustomobject]@{
      href = (New-Object System.Uri($resolved)).AbsoluteUri
      path = $entry.href
      label = $entry.label
    }) | Out-Null
  }

  return $entries.ToArray()
}

function Update-Book2HtmlNavigation {
  param(
    [string]$CurrentOutputPage,
    [string]$CurrentLabel,
    [bool]$AddCurrentToOtherPages,
    [bool]$CleanDeletedLinks
  )

  if (-not $AddCurrentToOtherPages -and -not $CleanDeletedLinks) {
    return 0
  }

  $entries = @(Get-BookmarkPageEntries -CurrentOutputPage $CurrentOutputPage -CurrentLabel $CurrentLabel)
  $managedBlock = ""
  if ($entries.Count -gt 0) {
    $managedBlock = New-BookmarkNavScriptBlock -Entries $entries
  }

  $updatedCount = 0
  $managedPattern = "(?is)\s*<script\s+data-book2html-nav\b[^>]*>.*?</script>"
  $siteShellPattern = '(<script\s+src="(?:data/)?js/site-shell\.js"></script>)'

  Get-ChildItem -LiteralPath $SiteRoot -File -Filter "*.html" -ErrorAction SilentlyContinue |
    ForEach-Object {
      $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
      $hasManagedBlock = [Regex]::IsMatch($content, $managedPattern)

      if ($AddCurrentToOtherPages -or $hasManagedBlock) {
        $newContent = $content
        $replacementBlock = $managedBlock -replace '\$', '$$$$'
        if ($hasManagedBlock) {
          $newContent = [Regex]::Replace($newContent, $managedPattern, "`r`n$replacementBlock")
        } elseif ($managedBlock -and [Regex]::IsMatch($newContent, $siteShellPattern)) {
          $newContent = [Regex]::Replace($newContent, $siteShellPattern, "`$1`r`n$replacementBlock")
        }

        if ($newContent -ne $content) {
          Set-Content -LiteralPath $_.FullName -Value $newContent -Encoding UTF8
          $updatedCount++
        }
      }
    }

  return $updatedCount
}

function Write-BookmarksPage {
  param(
    [object]$SelectedFolder,
    [object[]]$Sections,
    [string]$Path,
    [string]$SnapshotPath,
    [bool]$UseRemoteFavicons
  )

  $total = 0
  foreach ($section in $Sections) {
    $total += $section.items.Count
  }

  $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $title = $SelectedFolder.name
  if ([string]::IsNullOrWhiteSpace($title)) {
    $title = "收藏夹"
  }
  $outputFileName = Split-Path -Leaf $Path
  $assetPrefix = $script:ResourcePrefix

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
  Add-Line ("  <meta name=`"description`" content=`"Chrome 收藏夹导出：{0}`">" -f (Encode-Html $SelectedFolder.path))
  Add-Line ("  <title>{0} - 收藏导航</title>" -f (Encode-Html $title))
  Add-Line ("  <link rel=`"stylesheet`" href=`"{0}css/ops-coffee.css`" type=`"text/css`">" -f $assetPrefix)
  Add-Line ("  <link rel=`"shortcut icon`" href=`"{0}images/favicon.ico`">" -f $assetPrefix)
  Add-Line ("  <link rel=`"preload`" as=`"image`" href=`"{0}images/beijing.jpg`">" -f $assetPrefix)
  Add-Line "  <style>"
  Add-Line "    .bookmark-empty { margin: 0 10px; padding: 16px; text-align: left; color: var(--text-muted); border: 1px solid var(--card-border); border-radius: 15px; background: var(--card-bg); }"
  Add-Line "    .bookmark-info { float: right; position: relative; height: 52px; display: flex; align-items: center; margin-right: 8px; }"
  Add-Line "    .bookmark-info-toggle { width: 38px; min-width: 38px; height: 34px; border: 1px solid var(--control-border); border-radius: 10px; background: var(--control-bg); color: var(--header-text); cursor: pointer; font: inherit; font-weight: 700; padding: 0; }"
  Add-Line "    .bookmark-info-toggle:hover, .bookmark-info-toggle:focus-visible { background: var(--control-active-bg); outline: none; }"
  Add-Line "    .bookmark-info-panel { position: absolute; top: 48px; right: 0; z-index: 31; width: min(300px, 86vw); padding: 12px; border: 1px solid var(--card-border); border-radius: 10px; background: var(--panel-bg); color: var(--header-text); box-shadow: var(--card-shadow); text-align: left; backdrop-filter: var(--surface-blur); -webkit-backdrop-filter: var(--surface-blur); }"
  Add-Line "    .bookmark-info-panel[hidden] { display: none !important; }"
  Add-Line "    .bookmark-info-panel p { margin: 0; font-size: 12px; line-height: 1.6; color: var(--text-muted); word-break: break-all; }"
  Add-Line "    .bookmark-info-panel p + p { margin-top: 6px; }"
  Add-Line "  </style>"
  Add-Line "</head>"
  Add-Line "<body class=`"site-page`" data-page=`"bookmarks`">"
  Add-Line "  <div class=`"header`" data-site-header></div>"
  Add-Line "  <main id=`"content-wrapper`">"
  Add-Line "    <div class=`"container`">"

  if ($Sections.Count -eq 0) {
    Add-Line "      <p class=`"bookmark-empty`">这个收藏夹下面没有可导出的链接。</p>"
  } else {
    for ($sectionIndex = 0; $sectionIndex -lt $Sections.Count; $sectionIndex++) {
      $section = $Sections[$sectionIndex]
      $sectionId = "bookmarks-section-$sectionIndex"
      Add-Line ("      <section class=`"nav-cell clearfix`" aria-labelledby=`"{0}`">" -f $sectionId)
      Add-Line ("        <h2 class=`"nav-section-title`" id=`"{0}`">{1}</h2>" -f $sectionId, (Encode-Html $section.title))
      Add-Line "        <ul class=`"nav-list`">"

      foreach ($item in $section.items) {
        $itemName = Encode-Html $item.name
        $itemUrl = Encode-Html $item.url
        $itemDescription = Encode-Html $item.description
        $itemIcon = Encode-Html (Get-BookmarkIcon -Url $item.url -UseRemoteFavicons $UseRemoteFavicons)

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
  Add-Line ("  <script src=`"{0}js/site-shell.js`"></script>" -f $assetPrefix)
  $navBlock = New-BookmarkNavScriptBlock -Entries @([pscustomobject]@{ href = $outputFileName; label = $title })
  foreach ($line in ($navBlock -split "`r?`n")) {
    Add-Line $line
  }
  Add-Line ("  <script src=`"{0}js/site-preferences.js`"></script>" -f $assetPrefix)
  Add-Line "  <script>"
  Add-Line "    (() => {"
  Add-Line "      const headerContainer = document.querySelector(`"[data-site-header] .container`");"
  Add-Line "      if (!headerContainer) return;"
  Add-Line "      const root = document.createElement(`"div`");"
  Add-Line "      const toggle = document.createElement(`"button`");"
  Add-Line "      const panel = document.createElement(`"div`");"
  Add-Line "      const panelId = `"bookmark-info-panel`";"
  Add-Line "      root.className = `"bookmark-info`";"
  Add-Line "      toggle.type = `"button`";"
  Add-Line "      toggle.className = `"bookmark-info-toggle`";"
  Add-Line "      toggle.textContent = `"i`";"
  Add-Line "      toggle.setAttribute(`"aria-label`", `"页面信息`");"
  Add-Line "      toggle.setAttribute(`"aria-expanded`", `"false`");"
  Add-Line "      toggle.setAttribute(`"aria-controls`", panelId);"
  Add-Line "      panel.className = `"bookmark-info-panel`";"
  Add-Line "      panel.id = panelId;"
  Add-Line "      panel.hidden = true;"
  Add-Line "      const lines = ["
  Add-Line ("        `"文件夹：`" + {0}," -f (ConvertTo-JsString $title))
  Add-Line ("        `"来源：`" + {0}," -f (ConvertTo-JsString $SelectedFolder.path))
  Add-Line ("        `"链接数：{0}`"," -f $total)
  Add-Line ("        `"生成时间：`" + {0}" -f (ConvertTo-JsString $generatedAt))
  Add-Line "      ];"
  Add-Line "      lines.forEach((text) => {"
  Add-Line "        const item = document.createElement(`"p`");"
  Add-Line "        item.textContent = text;"
  Add-Line "        panel.append(item);"
  Add-Line "      });"
  Add-Line "      toggle.addEventListener(`"click`", () => {"
  Add-Line "        panel.hidden = !panel.hidden;"
  Add-Line "        toggle.setAttribute(`"aria-expanded`", String(!panel.hidden));"
  Add-Line "      });"
  Add-Line "      document.addEventListener(`"click`", (event) => {"
  Add-Line "        if (root.contains(event.target)) return;"
  Add-Line "        panel.hidden = true;"
  Add-Line "        toggle.setAttribute(`"aria-expanded`", `"false`");"
  Add-Line "      });"
  Add-Line "      root.append(toggle, panel);"
  Add-Line "      headerContainer.append(root);"
  Add-Line "    })();"
  Add-Line "  </script>"
  Add-Line ("  <script src=`"{0}js/liquid-glass.js`" defer></script>" -f $assetPrefix)
  Add-Line ("  <script src=`"{0}js/background-loader.js`"></script>" -f $assetPrefix)
  Add-Line "</body>"
  Add-Line "</html>"

  $outputDirectory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
  }

  Set-Content -LiteralPath $Path -Value $builder.ToString() -Encoding UTF8
  return $total
}

function Export-BookmarkFolder {
  param(
    [string]$BookmarksPath,
    [string]$SnapshotPath,
    [string]$FolderQuery,
    [object[]]$FolderQueries,
    [string]$PageName,
    [bool]$UseRemoteFavicons,
    [bool]$OpenAfterExport,
    [string]$ConflictAction,
    [bool]$AddToOtherPages,
    [bool]$CleanDeletedLinks
  )

  if (-not [string]::IsNullOrWhiteSpace($SnapshotPath) -and (Test-Path -LiteralPath $SnapshotPath)) {
    $snapshotPath = (Resolve-Path -LiteralPath $SnapshotPath).Path
  } else {
    $snapshot = Copy-BookmarksSnapshot -BookmarksPath $BookmarksPath
    $snapshotPath = $snapshot.snapshotPath
  }

  $readResult = Read-BookmarksFile -BookmarksPath $snapshotPath
  $folders = @(Get-BookmarkFolders -BookmarkData $readResult.data)
  $queries = New-Object System.Collections.Generic.List[string]
  if ($null -ne $FolderQueries) {
    foreach ($query in @($FolderQueries)) {
      $queryText = [string]$query
      if (-not [string]::IsNullOrWhiteSpace($queryText)) {
        $queries.Add($queryText) | Out-Null
      }
    }
  }
  if ($queries.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($FolderQuery)) {
    $queries.Add($FolderQuery) | Out-Null
  }

  $selectedFolders = @(Select-BookmarkFolders -Folders $folders -Queries ($queries.ToArray()))
  $selectedPaths = @($selectedFolders | ForEach-Object { $_.path })

  $pageLabel = ([string]$PageName).Trim()
  if ([string]::IsNullOrWhiteSpace($pageLabel)) {
    if ($selectedFolders.Count -eq 1) {
      $pageLabel = $selectedFolders[0].name
    } else {
      $pageLabel = "收藏夹组合"
    }
  }

  $outputResolution = Resolve-BookmarkOutputPath -FolderName $pageLabel -ConflictAction $ConflictAction
  if ($outputResolution.conflict) {
    return [pscustomobject]@{
      ok = $true
      conflict = $true
      folderId = ($selectedFolders | ForEach-Object { $_.id }) -join ","
      folderName = $pageLabel
      folderPath = $selectedPaths -join "；"
      folderIds = @($selectedFolders | ForEach-Object { $_.id })
      folderNames = @($selectedFolders | ForEach-Object { $_.name })
      folderPaths = $selectedPaths
      selectedFolderCount = $selectedFolders.Count
      pageName = $pageLabel
      existingPath = $outputResolution.existingPath
      existingFileName = $outputResolution.existingFileName
      suggestedPath = $outputResolution.suggestedPath
      suggestedFileName = $outputResolution.suggestedFileName
      snapshotPath = $snapshotPath
    }
  }

  $sections = New-Object System.Collections.Generic.List[object]
  $prefixSectionTitles = $selectedFolders.Count -gt 1
  foreach ($selectedFolder in $selectedFolders) {
    $relativePath = @()
    if ($prefixSectionTitles) {
      $relativePath = @($selectedFolder.name)
    }

    Add-BookmarkSections -Sections $sections -FolderNode $selectedFolder.node -RelativePath $relativePath
  }

  $pageFolder = [pscustomobject]@{
    id = ($selectedFolders | ForEach-Object { $_.id }) -join ","
    name = $pageLabel
    path = $selectedPaths -join "；"
  }

  $count = Write-BookmarksPage `
    -SelectedFolder $pageFolder `
    -Sections ($sections.ToArray()) `
    -Path $outputResolution.path `
    -SnapshotPath $snapshotPath `
    -UseRemoteFavicons $UseRemoteFavicons

  $script:LastOutputPage = $outputResolution.path
  $navigationUpdatedCount = Update-Book2HtmlNavigation `
    -CurrentOutputPage $outputResolution.path `
    -CurrentLabel $pageLabel `
    -AddCurrentToOtherPages $AddToOtherPages `
    -CleanDeletedLinks $CleanDeletedLinks

  if ($OpenAfterExport) {
    Start-Process -FilePath $outputResolution.path | Out-Null
  }

  return [pscustomobject]@{
    ok = $true
    conflict = $false
    count = $count
    folderId = ($selectedFolders | ForEach-Object { $_.id }) -join ","
    folderName = $pageLabel
    folderPath = $selectedPaths -join "；"
    folderIds = @($selectedFolders | ForEach-Object { $_.id })
    folderNames = @($selectedFolders | ForEach-Object { $_.name })
    folderPaths = $selectedPaths
    selectedFolderCount = $selectedFolders.Count
    pageName = $pageLabel
    outputPage = $outputResolution.path
    outputFileName = $outputResolution.fileName
    overwritten = $outputResolution.overwritten
    navigationUpdatedCount = $navigationUpdatedCount
    snapshotPath = $snapshotPath
  }
}

function Get-AppHtml {
  $html = @'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Book2HTML</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f5f7fb;
      --panel: #ffffff;
      --panel-2: #f8fafc;
      --text: #172033;
      --muted: #667085;
      --border: #d8dee9;
      --accent: #246bfe;
      --accent-2: #174bd6;
      --danger: #b42318;
      --success: #087443;
      --shadow: 0 14px 36px rgba(23, 32, 51, 0.08);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 14px/1.5 "Segoe UI", "Microsoft YaHei", Arial, sans-serif;
      letter-spacing: 0;
    }
    header {
      position: sticky;
      top: 0;
      z-index: 2;
      border-bottom: 1px solid var(--border);
      background: rgba(255, 255, 255, 0.88);
      backdrop-filter: blur(16px);
    }
    .topbar {
      width: min(1180px, calc(100vw - 32px));
      min-height: 58px;
      margin: 0 auto;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }
    .topbar-main {
      display: flex;
      align-items: center;
      gap: 18px;
      min-width: 0;
    }
    .site-nav {
      display: flex;
      align-items: center;
      gap: 6px;
      min-width: 0;
      overflow-x: auto;
      scrollbar-width: thin;
    }
    .site-nav-label {
      flex: none;
      display: inline-flex;
      align-items: center;
      min-height: 26px;
      padding: 3px 8px;
      border: 1px solid #d6e4ff;
      border-radius: 999px;
      background: #eef4ff;
      color: var(--accent);
      font-size: 12px;
      font-weight: 700;
      white-space: nowrap;
    }
    .site-nav a {
      display: inline-flex;
      align-items: center;
      min-height: 32px;
      padding: 5px 9px;
      border: 1px solid transparent;
      border-radius: 7px;
      color: var(--muted);
      text-decoration: none;
      white-space: nowrap;
    }
    .site-nav a:hover {
      color: var(--text);
      border-color: var(--border);
      background: var(--panel-2);
    }
    .topbar-actions {
      flex: none;
    }
    h1 { margin: 0; font-size: 18px; line-height: 1.2; }
    h1.minimal-mode {
      color: var(--danger);
    }
    .minimal-badge {
      display: inline-flex;
      align-items: center;
      min-height: 22px;
      margin-left: 8px;
      padding: 2px 7px;
      border: 1px solid rgba(180, 35, 24, 0.28);
      border-radius: 999px;
      background: #fff1f0;
      color: var(--danger);
      font-size: 12px;
      font-weight: 700;
      vertical-align: 2px;
      white-space: nowrap;
    }
    main {
      width: min(1180px, calc(100vw - 32px));
      margin: 24px auto 36px;
      display: grid;
      grid-template-columns: 390px minmax(0, 1fr);
      align-items: start;
      gap: 18px;
    }
    section {
      border: 1px solid var(--border);
      border-radius: 8px;
      background: var(--panel);
      box-shadow: var(--shadow);
    }
    .panel { padding: 16px; }
    .panel + .panel { margin-top: 14px; }
    .folder-panel {
      align-self: start;
      height: fit-content;
    }
    .section-title {
      margin: 0 0 12px;
      font-size: 14px;
      font-weight: 700;
    }
    label {
      display: block;
      margin: 12px 0 6px;
      color: var(--muted);
      font-size: 12px;
    }
    input, select, textarea {
      width: 100%;
      border: 1px solid var(--border);
      border-radius: 7px;
      background: #fff;
      color: var(--text);
      font: inherit;
      letter-spacing: 0;
    }
    input, select { min-height: 36px; padding: 7px 10px; }
    textarea {
      min-height: 170px;
      padding: 10px;
      resize: vertical;
      font-family: Consolas, "Courier New", monospace;
      font-size: 12px;
    }
    input:focus, select:focus, textarea:focus {
      outline: 2px solid rgba(36, 107, 254, 0.18);
      border-color: var(--accent);
    }
    .row { display: flex; gap: 8px; align-items: center; }
    .row > * { min-width: 0; }
    .row .grow { flex: 1; }
    button {
      min-height: 36px;
      border: 1px solid var(--border);
      border-radius: 7px;
      background: #fff;
      color: var(--text);
      cursor: pointer;
      font: inherit;
      padding: 7px 12px;
      white-space: nowrap;
    }
    button:hover { background: var(--panel-2); }
    button.button-loading {
      position: relative;
      padding-right: 34px;
    }
    button.button-loading::after {
      content: "";
      position: absolute;
      right: 12px;
      top: 50%;
      width: 13px;
      height: 13px;
      margin-top: -7px;
      border: 2px solid rgba(255, 255, 255, 0.58);
      border-top-color: #fff;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    button.primary {
      border-color: var(--accent);
      background: var(--accent);
      color: #fff;
    }
    button.primary:hover { background: var(--accent-2); }
    button.danger {
      color: var(--danger);
      border-color: rgba(180, 35, 24, 0.32);
    }
    button:disabled {
      cursor: not-allowed;
      opacity: 0.58;
    }
    .check {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-top: 12px;
      color: var(--text);
      font-size: 13px;
    }
    .check input { width: 16px; min-height: 16px; }
    .meta {
      margin-top: 10px;
      color: var(--muted);
      font-size: 12px;
      word-break: break-all;
    }
    .folder-toolbar {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 8px;
      margin-bottom: 10px;
    }
    .folder-breadcrumb {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      margin-bottom: 10px;
    }
    .breadcrumb-button {
      min-height: 28px;
      padding: 4px 8px;
      color: var(--muted);
      font-size: 12px;
    }
    .folder-list {
      max-height: min(560px, calc(100vh - 230px));
      overflow: auto;
      border-top: 1px solid var(--border);
    }
    .folder-item {
      width: 100%;
      display: grid;
      grid-template-columns: 24px minmax(0, 1fr) 28px;
      align-items: center;
      gap: 8px;
      border: 0;
      border-bottom: 1px solid var(--border);
      border-radius: 0;
      background: transparent;
      text-align: left;
      padding: 10px 12px;
    }
    .folder-item:hover { background: var(--panel-2); }
    .folder-item.active {
      background: #eef4ff;
      box-shadow: inset 3px 0 0 var(--accent);
    }
    .folder-item.dragging {
      opacity: 0.55;
    }
    .folder-check {
      width: 16px;
      min-height: 16px;
      margin: 0;
      cursor: pointer;
    }
    .folder-entry {
      min-width: 0;
      cursor: pointer;
    }
    .folder-arrow {
      display: flex;
      justify-content: center;
      color: var(--muted);
      font-size: 18px;
      line-height: 1;
    }
    .folder-name { font-weight: 700; }
    .folder-path {
      margin-top: 3px;
      color: var(--muted);
      font-size: 12px;
      word-break: break-all;
    }
    .selected-folder {
      margin-top: 10px;
      padding: 10px;
      border: 1px solid var(--border);
      border-radius: 7px;
      background: var(--panel-2);
      color: var(--muted);
      font-size: 12px;
      word-break: break-all;
    }
    .selected-list {
      display: grid;
      gap: 8px;
      margin-top: 10px;
    }
    .selected-item {
      display: grid;
      grid-template-columns: 30px minmax(0, 1fr) auto;
      align-items: center;
      gap: 8px;
      padding: 8px;
      border: 1px solid var(--border);
      border-radius: 7px;
      background: #fff;
    }
    .selected-item.dragging {
      border-color: var(--accent);
      background: #eef4ff;
      box-shadow: 0 8px 20px rgba(36, 107, 254, 0.12);
    }
    .selected-handle {
      min-height: 30px;
      padding: 0;
      cursor: grab;
      color: var(--muted);
      font-weight: 700;
      touch-action: none;
      user-select: none;
    }
    .selected-handle:active { cursor: grabbing; }
    .selected-title {
      color: var(--text);
      font-size: 13px;
      font-weight: 700;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .selected-path {
      margin-top: 2px;
      color: var(--muted);
      font-size: 12px;
      word-break: break-all;
    }
    .selected-remove {
      min-height: 30px;
      padding: 4px 8px;
      color: var(--danger);
    }
    .utility-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      align-items: center;
      gap: 8px;
      margin-top: 12px;
    }
    .help-tip {
      position: relative;
      width: 28px;
      min-width: 28px;
      min-height: 28px;
      padding: 0;
      border-radius: 50%;
      color: var(--muted);
      font-weight: 700;
      line-height: 1;
    }
    .help-tip::after {
      content: attr(data-tip);
      position: absolute;
      left: 50%;
      bottom: calc(100% + 8px);
      z-index: 5;
      width: min(280px, calc(100vw - 40px));
      padding: 8px 10px;
      border: 1px solid var(--border);
      border-radius: 7px;
      background: #172033;
      color: #fff;
      box-shadow: var(--shadow);
      font-size: 12px;
      font-weight: 400;
      line-height: 1.5;
      text-align: left;
      white-space: normal;
      transform: translateX(-50%);
      opacity: 0;
      pointer-events: none;
    }
    .help-tip:hover::after,
    .help-tip:focus-visible::after {
      opacity: 1;
    }
    .status {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 10px;
    }
    .pill {
      display: inline-flex;
      align-items: center;
      min-height: 24px;
      padding: 2px 8px;
      border-radius: 999px;
      background: var(--panel-2);
      color: var(--muted);
      font-size: 12px;
    }
    .pill.success { color: var(--success); background: #ecfdf3; }
    .pill.danger { color: var(--danger); background: #fff1f0; }
    @media (max-width: 900px) {
      main { grid-template-columns: 1fr; }
      .folder-list { max-height: calc(100vh - 240px); }
      .topbar { align-items: flex-start; flex-direction: column; padding: 12px 0; }
      .topbar-main { width: 100%; align-items: flex-start; flex-direction: column; gap: 8px; }
      .site-nav { width: 100%; }
    }
  </style>
</head>
<body>
  <header>
    <div class="topbar">
      <div class="topbar-main">
        <h1 id="appTitle">Book2HTML</h1>
        <span class="site-nav-label">导航</span>
        <nav class="site-nav" id="siteNav" aria-label="站点导航"></nav>
      </div>
      <div class="row topbar-actions">
        <button id="openOutputButton" type="button">打开生成页</button>
        <button id="stopButton" class="danger" type="button">停止服务</button>
      </div>
    </div>
  </header>

  <main>
    <div>
      <section class="panel">
        <h2 class="section-title">来源</h2>
        <label for="bookmarkFile">检测到的 Bookmarks 文件</label>
        <div class="row">
          <select id="bookmarkFile" class="grow"></select>
          <button id="refreshFilesButton" type="button">刷新</button>
        </div>

        <label for="manualPath">手动路径</label>
        <input id="manualPath" type="text" placeholder="也可以粘贴 Bookmarks 完整路径">

        <div class="row" style="margin-top: 12px;">
          <button id="loadFoldersButton" class="primary grow" type="button">读取收藏夹</button>
        </div>

        <div class="meta" id="siteMeta"></div>
      </section>

      <section class="panel">
        <h2 class="section-title">导出</h2>
        <label for="pageName">顶栏名 / 文件名</label>
        <input id="pageName" type="text" placeholder="默认使用收藏夹名；多选默认“收藏夹组合”">
        <div class="selected-folder" id="selectedFolderInfo">当前未选择收藏夹。请在右侧勾选一个或多个收藏夹。</div>
        <div class="selected-list" id="selectedFolderList"></div>

        <label class="check">
          <input id="remoteFavicons" type="checkbox" checked>
          使用远程 favicon
        </label>

        <label class="check">
          <input id="addToOtherPages" type="checkbox" checked>
          在其他页面加入本页跳转
        </label>

        <div class="utility-row">
          <button id="cleanDeletedLinksButton" type="button">清理已删除页面跳转</button>
          <button class="help-tip" type="button" aria-label="清理说明" data-tip="扫描站点里的 HTML，刷新 Book2HTML 管理的跳转块；已经不存在的 bookmarks_*.html 链接会从导航中移除。">?</button>
        </div>

        <label class="check">
          <input id="openAfterExport" type="checkbox" checked>
          生成后打开页面
        </label>

        <div class="row" style="margin-top: 14px;">
          <button id="exportButton" class="primary grow" type="button">生成 HTML</button>
        </div>
      </section>

      <section class="panel">
        <h2 class="section-title">日志</h2>
        <textarea id="log" readonly></textarea>
      </section>
    </div>

    <section class="panel folder-panel">
      <h2 class="section-title">收藏夹浏览</h2>
      <div class="folder-breadcrumb" id="folderBreadcrumb"></div>
      <div class="folder-toolbar">
        <input id="folderSearch" type="search" placeholder="筛选当前层级">
        <button id="clearSearchButton" type="button">清空</button>
      </div>
      <div class="folder-list" id="folderList"></div>
    </section>
  </main>

  <script>
    const $ = (id) => document.getElementById(id);
    const state = {
      files: [],
      folderTree: [],
      folderById: new Map(),
      currentFolderId: "",
      selectedFolderIds: [],
      snapshotPath: "",
      pageNameTouched: false,
      draggedFolderId: "",
      isLoadingFolders: false
    };

    const log = (message, type = "info") => {
      const time = new Date().toLocaleTimeString();
      $("log").value += `[${time}] ${message}\n`;
      $("log").scrollTop = $("log").scrollHeight;
    };

    const api = async (path, options = {}) => {
      const response = await fetch(path, {
        headers: { "Content-Type": "application/json" },
        ...options
      });
      const text = await response.text();
      const data = text ? JSON.parse(text) : {};
      if (!response.ok || data.ok === false) {
        throw new Error(data.error || `HTTP ${response.status}`);
      }
      return data;
    };

    const getSelectedBookmarksPath = () => {
      const manual = $("manualPath").value.trim();
      if (manual) return manual;
      return $("bookmarkFile").value;
    };

    const renderSiteNav = (pages) => {
      const nav = $("siteNav");
      nav.innerHTML = "";
      (pages || []).forEach((page) => {
        const link = document.createElement("a");
        link.href = page.href;
        link.dataset.sitePath = page.path;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.textContent = page.label;
        link.addEventListener("click", async (event) => {
          event.preventDefault();
          try {
            await api("/api/open-site", {
              method: "POST",
              body: JSON.stringify({ path: page.path })
            });
          } catch (error) {
            log(error.message, "error");
          }
        });
        nav.append(link);
      });
    };

    const refreshSiteState = async () => {
      const data = await api("/api/state");
      const title = $("appTitle");
      title.classList.toggle("minimal-mode", Boolean(data.isMinimalMode));
      title.textContent = "Book2HTML";
      if (data.isMinimalMode) {
        const badge = document.createElement("span");
        badge.className = "minimal-badge";
        badge.textContent = "极简模式";
        title.append(badge);
      }
      $("siteMeta").textContent = `站点目录：${data.siteRoot} · 资源：${data.resourceMode}`;
      renderSiteNav(data.sitePages);
    };

    const loadFiles = async () => {
      $("bookmarkFile").innerHTML = "";
      state.files = await api("/api/bookmark-files");
      if (state.files.length === 0) {
        const option = document.createElement("option");
        option.value = "";
        option.textContent = "未自动找到，请手动输入路径";
        $("bookmarkFile").append(option);
        log("未自动找到 Bookmarks 文件，可以手动粘贴路径。");
        return;
      }

      state.files.forEach((file) => {
        const option = document.createElement("option");
        option.value = file.path;
        option.textContent = `${file.browser} / ${file.profile} - ${file.path}`;
        $("bookmarkFile").append(option);
      });
      log(`找到 ${state.files.length} 个 Bookmarks 文件。`);
      await loadFolders();
    };

    const rebuildFolderIndex = () => {
      state.folderById = new Map();
      const walk = (nodes) => {
        nodes.forEach((folder) => {
          state.folderById.set(folder.id, folder);
          walk(folder.children || []);
        });
      };
      walk(state.folderTree);
    };

    const getSelectedFolders = () => state.selectedFolderIds
      .map((folderId) => state.folderById.get(folderId))
      .filter(Boolean);

    const isFolderSelected = (folderId) => state.selectedFolderIds.includes(folderId);

    const getCurrentChildren = () => {
      if (!state.currentFolderId) {
        return state.folderTree;
      }
      const current = state.folderById.get(state.currentFolderId);
      return current ? (current.children || []) : state.folderTree;
    };

    const findPathToFolder = (folderId) => {
      if (!folderId) return [];

      const walk = (nodes, trail) => {
        for (const folder of nodes) {
          const nextTrail = [...trail, folder];
          if (folder.id === folderId) return nextTrail;
          const found = walk(folder.children || [], nextTrail);
          if (found) return found;
        }
        return null;
      };

      return walk(state.folderTree, []) || [];
    };

    const findDefaultStartFolderId = () => {
      const preferred = state.folderTree.find((folder) => {
        const name = String(folder.name || "").toLowerCase();
        const path = String(folder.path || "").toLowerCase();
        return folder.id === "1" ||
          name === "书签栏" ||
          name === "bookmarks bar" ||
          path === "书签栏" ||
          path === "bookmarks bar";
      });

      return preferred ? preferred.id : "";
    };

    const getDefaultPageName = () => {
      const selected = getSelectedFolders();
      if (selected.length === 1) return selected[0].name;
      if (selected.length > 1) return "收藏夹组合";
      return "";
    };

    const syncPageName = () => {
      if (state.pageNameTouched) return;
      $("pageName").value = getDefaultPageName();
    };

    const reorderSelectedFolderByPointer = (draggingId, clientY) => {
      if (!draggingId) return;
      const items = [...$("selectedFolderList").querySelectorAll(".selected-item")];
      const target = items.find((item) => {
        if (item.dataset.folderId === draggingId) return false;
        const rect = item.getBoundingClientRect();
        return clientY >= rect.top && clientY <= rect.bottom;
      });
      if (!target) return;

      const rect = target.getBoundingClientRect();
      moveSelectedFolder(draggingId, target.dataset.folderId, clientY > rect.top + rect.height * 0.4);
    };

    const updateSelectedFolderInfo = () => {
      const selected = getSelectedFolders();
      const selectedList = $("selectedFolderList");
      selectedList.innerHTML = "";

      if (selected.length === 0) {
        $("selectedFolderInfo").textContent = "当前未选择收藏夹。请在右侧勾选一个或多个收藏夹。";
        return;
      }

      const total = selected.reduce((sum, folder) => sum + Number(folder.totalCount || 0), 0);
      $("selectedFolderInfo").textContent = `已选择 ${selected.length} 个收藏夹 · 合计 ${total} 个链接。拖动下方条目可调整导出顺序。`;

      selected.forEach((folder) => {
        const item = document.createElement("div");
        item.className = `selected-item ${state.draggedFolderId === folder.id ? "dragging" : ""}`;
        item.dataset.folderId = folder.id;
        item.innerHTML = `
          <button class="selected-handle" type="button" aria-label="拖动排序">☰</button>
          <div>
            <div class="selected-title">${escapeHtml(folder.name)} <span class="pill">${folder.totalCount} 个链接</span></div>
            <div class="selected-path">${escapeHtml(folder.path)}</div>
          </div>
          <button class="selected-remove" type="button" aria-label="移除 ${escapeHtml(folder.name)}">移除</button>
        `;
        const handle = item.querySelector(".selected-handle");
        handle.addEventListener("pointerdown", (event) => {
          event.preventDefault();
          state.draggedFolderId = folder.id;
          updateSelectedFolderInfo();
        });
        item.querySelector(".selected-remove").addEventListener("click", () => selectFolder(folder, false));
        selectedList.append(item);
      });
    };

    const renderBreadcrumb = () => {
      const rootButton = document.createElement("button");
      const breadcrumb = $("folderBreadcrumb");
      breadcrumb.innerHTML = "";
      rootButton.type = "button";
      rootButton.className = "breadcrumb-button";
      rootButton.textContent = "根目录";
      rootButton.addEventListener("click", () => {
        state.currentFolderId = "";
        $("folderSearch").value = "";
        renderFolders();
      });
      breadcrumb.append(rootButton);

      findPathToFolder(state.currentFolderId).forEach((folder) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "breadcrumb-button";
        button.textContent = folder.name;
        button.addEventListener("click", () => {
          state.currentFolderId = folder.id;
          $("folderSearch").value = "";
          renderFolders();
        });
        breadcrumb.append(button);
      });
    };

    const selectFolder = (folder, checked) => {
      const exists = state.selectedFolderIds.includes(folder.id);
      if (checked && !exists) {
        state.selectedFolderIds = [...state.selectedFolderIds, folder.id];
        log(`已加入组合：${folder.path}`);
      } else if (!checked && exists) {
        state.selectedFolderIds = state.selectedFolderIds.filter((folderId) => folderId !== folder.id);
        log(`已移除：${folder.path}`);
      }
      syncPageName();
      updateSelectedFolderInfo();
      renderFolders();
    };

    const moveSelectedFolder = (draggingId, targetId, placeAfter = false) => {
      if (!draggingId || !targetId || draggingId === targetId) return;
      const next = state.selectedFolderIds.filter((folderId) => folderId !== draggingId);
      const targetIndex = next.indexOf(targetId);
      if (targetIndex < 0) return;
      next.splice(targetIndex + (placeAfter ? 1 : 0), 0, draggingId);
      state.selectedFolderIds = next;
      updateSelectedFolderInfo();
    };

    const enterFolder = (folder) => {
      if (!folder.children || folder.children.length === 0) {
        log(`没有下一级：${folder.path}`);
        return;
      }

      state.currentFolderId = folder.id;
      $("folderSearch").value = "";
      renderFolders();
    };

    const renderFolders = () => {
      const query = $("folderSearch").value.trim().toLowerCase();
      const list = $("folderList");
      list.innerHTML = "";
      renderBreadcrumb();
      updateSelectedFolderInfo();

      const currentChildren = getCurrentChildren();
      const visible = currentChildren.filter((folder) => {
        if (!query) return true;
        return [folder.id, folder.name, folder.path].some((value) =>
          String(value || "").toLowerCase().includes(query)
        );
      });

      if (visible.length === 0) {
        const empty = document.createElement("div");
        empty.className = "folder-path";
        empty.style.padding = "14px";
        empty.textContent = "没有匹配的收藏夹。";
        list.append(empty);
        return;
      }

      visible.forEach((folder) => {
        const selected = isFolderSelected(folder.id);
        const row = document.createElement("div");
        row.className = `folder-item ${selected ? "active" : ""}`;
        row.innerHTML = `
          <input class="folder-check" type="checkbox" ${selected ? "checked" : ""} aria-label="选择 ${escapeHtml(folder.name)}">
          <div class="folder-entry" role="button" tabindex="0">
            <div class="folder-name">${escapeHtml(folder.name)} <span class="pill">id=${escapeHtml(folder.id)}</span> <span class="pill">${folder.totalCount} 个链接</span></div>
            <div class="folder-path">${escapeHtml(folder.path)}</div>
          </div>
          <div class="folder-arrow" aria-hidden="true">${folder.children && folder.children.length ? "&gt;" : ""}</div>
        `;
        row.addEventListener("click", () => enterFolder(folder));
        row.querySelector(".folder-check").addEventListener("click", (event) => {
          event.stopPropagation();
          selectFolder(folder, event.currentTarget.checked);
        });
        row.querySelector(".folder-entry").addEventListener("keydown", (event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            enterFolder(folder);
          }
        });
        list.append(row);
      });
    };

    const escapeHtml = (value) => String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

    const setFolderLoading = (isLoading) => {
      state.isLoadingFolders = isLoading;
      const button = $("loadFoldersButton");
      button.disabled = isLoading;
      button.classList.toggle("button-loading", isLoading);
      button.textContent = isLoading ? "读取中" : "读取收藏夹";
    };

    const loadFolders = async () => {
      if (state.isLoadingFolders) {
        return;
      }

      const bookmarksPath = getSelectedBookmarksPath();
      if (!bookmarksPath) {
        log("请先选择或输入 Bookmarks 文件路径。", "error");
        return;
      }

      setFolderLoading(true);
      try {
        log("正在读取收藏夹...");
        const data = await api("/api/folders", {
          method: "POST",
          body: JSON.stringify({ bookmarksPath })
        });
        state.folderTree = data.folderTree;
        state.snapshotPath = data.snapshotPath;
        state.selectedFolderIds = [];
        state.pageNameTouched = false;
        $("pageName").value = "";
        rebuildFolderIndex();
        state.currentFolderId = findDefaultStartFolderId();
        renderFolders();
        if (state.currentFolderId) {
          const startFolder = state.folderById.get(state.currentFolderId);
          if (startFolder) {
            log(`已默认打开：${startFolder.path}`);
          }
        }
        log(`解析完成：${data.folderCount} 个收藏夹。`, "success");
      } finally {
        setFolderLoading(false);
      }
    };

    const exportBookmarks = async (conflictAction = "") => {
      const bookmarksPath = getSelectedBookmarksPath();
      const folderQueries = [...state.selectedFolderIds];
      const pageName = $("pageName").value.trim() || getDefaultPageName();
      if (!bookmarksPath) {
        log("请先选择或输入 Bookmarks 文件路径。", "error");
        return;
      }
      if (folderQueries.length === 0) {
        log("请先在右侧勾选一个或多个收藏夹。", "error");
        return;
      }
      if (!pageName) {
        log("请填写顶栏名 / 文件名。", "error");
        return;
      }
      if (!state.snapshotPath) {
        log("请先读取收藏夹。", "error");
        return;
      }

      $("exportButton").disabled = true;
      log("正在生成 HTML...");
      try {
        const data = await api("/api/export", {
          method: "POST",
          body: JSON.stringify({
            bookmarksPath,
            snapshotPath: state.snapshotPath,
            folderQueries,
            pageName,
            useRemoteFavicons: $("remoteFavicons").checked,
            openAfterExport: $("openAfterExport").checked,
            addToOtherPages: $("addToOtherPages").checked,
            conflictAction
          })
        });

        if (data.conflict) {
          const overwrite = window.confirm(`文件已存在：${data.existingFileName}\n\n确定：覆盖现有文件\n取消：自动加序号生成 ${data.suggestedFileName}`);
          await exportBookmarks(overwrite ? "overwrite" : "sequence");
          return;
        }

        log(`生成完成：${data.count} 个链接 -> ${data.outputPage}`, "success");
        if (data.navigationUpdatedCount > 0) {
          log(`已更新 ${data.navigationUpdatedCount} 个页面的跳转。`, "success");
        }
        await refreshSiteState();
      } finally {
        $("exportButton").disabled = false;
      }
    };

    const cleanDeletedLinks = async () => {
      const button = $("cleanDeletedLinksButton");
      button.disabled = true;
      log("正在清理已删除页面跳转...");
      try {
        const data = await api("/api/clean-deleted-links", { method: "POST", body: "{}" });
        if (data.navigationUpdatedCount > 0) {
          log(`已清理并更新 ${data.navigationUpdatedCount} 个页面的跳转。`, "success");
        } else {
          log("没有需要清理的页面跳转。", "success");
        }
        await refreshSiteState();
      } finally {
        button.disabled = false;
      }
    };

    const openOutput = async () => {
      await api("/api/open-output", { method: "POST", body: "{}" });
      log("已请求打开生成页面。", "success");
    };

    const stopServer = async () => {
      await api("/api/stop", { method: "POST", body: "{}" });
      log("服务已停止，可以关闭这个页面。", "success");
    };

    $("refreshFilesButton").addEventListener("click", () => loadFiles().catch((error) => log(error.message, "error")));
    $("loadFoldersButton").addEventListener("click", () => loadFolders().catch((error) => log(error.message, "error")));
    $("bookmarkFile").addEventListener("change", () => {
      $("manualPath").value = "";
      loadFolders().catch((error) => log(error.message, "error"));
    });
    $("exportButton").addEventListener("click", () => exportBookmarks().catch((error) => log(error.message, "error")));
    $("cleanDeletedLinksButton").addEventListener("click", () => cleanDeletedLinks().catch((error) => log(error.message, "error")));
    $("openOutputButton").addEventListener("click", () => openOutput().catch((error) => log(error.message, "error")));
    $("stopButton").addEventListener("click", () => stopServer().catch((error) => log(error.message, "error")));
    $("folderSearch").addEventListener("input", renderFolders);
    $("pageName").addEventListener("input", () => {
      state.pageNameTouched = $("pageName").value.trim().length > 0;
    });
    document.addEventListener("pointermove", (event) => {
      if (!state.draggedFolderId) return;
      event.preventDefault();
      reorderSelectedFolderByPointer(state.draggedFolderId, event.clientY);
    });
    document.addEventListener("pointerup", () => {
      if (!state.draggedFolderId) return;
      state.draggedFolderId = "";
      updateSelectedFolderInfo();
    });
    document.addEventListener("pointercancel", () => {
      if (!state.draggedFolderId) return;
      state.draggedFolderId = "";
      updateSelectedFolderInfo();
    });
    $("clearSearchButton").addEventListener("click", () => {
      $("folderSearch").value = "";
      renderFolders();
    });

    refreshSiteState()
      .then(loadFiles)
      .catch((error) => log(error.message, "error"));
  </script>
</body>
</html>
'@

  return $html
}

function Read-JsonBody {
  param([System.Net.HttpListenerRequest]$Request)

  $encoding = [System.Text.Encoding]::UTF8
  if ($Request.ContentType -match "charset\s*=" -and $null -ne $Request.ContentEncoding) {
    $encoding = $Request.ContentEncoding
  }

  $reader = New-Object System.IO.StreamReader($Request.InputStream, $encoding, $true)
  $raw = $reader.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [pscustomobject]@{}
  }

  return ConvertFrom-JsonCompat -Json $raw
}

function Send-Response {
  param(
    [System.Net.HttpListenerContext]$Context,
    [int]$StatusCode,
    [string]$ContentType,
    [string]$Body
  )

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = "$ContentType; charset=utf-8"
  $Context.Response.ContentLength64 = $bytes.Length
  $Context.Response.Headers["Cache-Control"] = "no-store"
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Context.Response.OutputStream.Close()
}

function Get-StaticContentType {
  param([string]$Path)

  switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    ".html" { return "text/html" }
    ".htm" { return "text/html" }
    ".css" { return "text/css" }
    ".js" { return "application/javascript" }
    ".json" { return "application/json" }
    ".png" { return "image/png" }
    ".jpg" { return "image/jpeg" }
    ".jpeg" { return "image/jpeg" }
    ".gif" { return "image/gif" }
    ".svg" { return "image/svg+xml" }
    ".ico" { return "image/x-icon" }
    ".webp" { return "image/webp" }
    default { return "application/octet-stream" }
  }
}

function Send-SiteFile {
  param(
    [System.Net.HttpListenerContext]$Context,
    [string]$RelativePath
  )

  $decodedPath = [Uri]::UnescapeDataString($RelativePath).TrimStart("/")
  if ([string]::IsNullOrWhiteSpace($decodedPath)) {
    $decodedPath = "index.html"
  }

  $root = $SiteRoot
  $resourceRoots = @("css/", "js/", "images/")
  foreach ($resourcePath in $resourceRoots) {
    if ($decodedPath.StartsWith($resourcePath, [System.StringComparison]::OrdinalIgnoreCase)) {
      $root = $script:ResourceRoot
      break
    }
  }

  if ($decodedPath.StartsWith("data/", [System.StringComparison]::OrdinalIgnoreCase)) {
    $root = (Resolve-Path -LiteralPath $PSScriptRoot).Path
  }

  $candidate = Join-Path $root ($decodedPath -replace "/", "\")
  if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
    Send-Error -Context $Context -StatusCode 404 -Message "文件不存在：$decodedPath"
    return
  }

  $resolved = (Resolve-Path -LiteralPath $candidate).Path
  $rootPath = ([string]$root).TrimEnd("\") + "\"
  if (-not $resolved.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    Send-Error -Context $Context -StatusCode 403 -Message "拒绝访问资源目录外文件。"
    return
  }

  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  $Context.Response.StatusCode = 200
  $Context.Response.ContentType = "$(Get-StaticContentType -Path $resolved); charset=utf-8"
  $Context.Response.ContentLength64 = $bytes.Length
  $Context.Response.Headers["Cache-Control"] = "no-store"
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Context.Response.OutputStream.Close()
}

function Resolve-SiteRelativeFile {
  param([string]$RelativePath)

  $decodedPath = [Uri]::UnescapeDataString($RelativePath).TrimStart("/")
  if ([string]::IsNullOrWhiteSpace($decodedPath)) {
    $decodedPath = "index.html"
  }

  $candidate = Join-Path $SiteRoot ($decodedPath -replace "/", "\")
  if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
    throw "文件不存在：$decodedPath"
  }

  $resolved = (Resolve-Path -LiteralPath $candidate).Path
  $rootPath = ([string]$SiteRoot).TrimEnd("\") + "\"
  if (-not $resolved.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "拒绝访问站点目录外文件。"
  }

  return $resolved
}

function Send-Json {
  param(
    [System.Net.HttpListenerContext]$Context,
    [object]$Data,
    [int]$StatusCode = 200
  )

  Send-Response -Context $Context -StatusCode $StatusCode -ContentType "application/json" -Body (ConvertTo-JsonCompat -Value $Data)
}

function Send-Error {
  param(
    [System.Net.HttpListenerContext]$Context,
    [string]$Message,
    [int]$StatusCode = 500
  )

  Send-Json -Context $Context -StatusCode $StatusCode -Data ([pscustomobject]@{
    ok = $false
    error = $Message
  })
}

function Handle-Request {
  param([System.Net.HttpListenerContext]$Context)

  $request = $Context.Request
  $path = $request.Url.AbsolutePath.TrimEnd("/")
  if ($path -eq "") {
    $path = "/"
  }

  if ($request.HttpMethod -eq "GET" -and $path -eq "/") {
    Send-Response -Context $Context -StatusCode 200 -ContentType "text/html" -Body (Get-AppHtml)
    return
  }

  if ($request.HttpMethod -eq "GET" -and $path.StartsWith("/site/", [System.StringComparison]::OrdinalIgnoreCase)) {
    Send-SiteFile -Context $Context -RelativePath $request.Url.AbsolutePath.Substring("/site/".Length)
    return
  }

  if ($request.HttpMethod -eq "GET" -and $path -eq "/api/state") {
    Send-Json -Context $Context -Data ([pscustomobject]@{
      ok = $true
      siteRoot = [string]$SiteRoot
      outputDirectory = [string]$SiteRoot
      defaultOutputPage = $DefaultOutputPage
      lastOutputPage = $script:LastOutputPage
      snapshotDirectory = $SnapshotDirectory
      resourceRoot = $script:ResourceRoot
      resourceMode = $script:ResourceMode
      isMinimalMode = $script:IsMinimalMode
      sitePages = Get-SiteNavigationEntries
    })
    return
  }

  if ($request.HttpMethod -eq "GET" -and $path -eq "/api/bookmark-files") {
    Send-Json -Context $Context -Data (Get-BookmarkFileCandidates)
    return
  }

  if ($request.HttpMethod -eq "POST" -and $path -eq "/api/folders") {
    $body = Read-JsonBody -Request $request
    $snapshot = Copy-BookmarksSnapshot -BookmarksPath ([string]$body.bookmarksPath)
    $readResult = Read-BookmarksFile -BookmarksPath $snapshot.snapshotPath
    $folders = @(Get-BookmarkFolders -BookmarkData $readResult.data)
    Send-Json -Context $Context -Data ([pscustomobject]@{
      ok = $true
      bookmarksPath = $snapshot.sourcePath
      snapshotPath = $snapshot.snapshotPath
      folderCount = $folders.Count
      folderTree = Get-BookmarkFolderTree -BookmarkData $readResult.data
      folders = Get-SerializableFolders -Folders $folders
    })
    return
  }

  if ($request.HttpMethod -eq "POST" -and $path -eq "/api/export") {
    $body = Read-JsonBody -Request $request
    $result = Export-BookmarkFolder `
      -BookmarksPath ([string]$body.bookmarksPath) `
      -SnapshotPath ([string]$body.snapshotPath) `
      -FolderQuery ([string]$body.folderQuery) `
      -FolderQueries @($body.folderQueries) `
      -PageName ([string]$body.pageName) `
      -UseRemoteFavicons ([bool]$body.useRemoteFavicons) `
      -OpenAfterExport ([bool]$body.openAfterExport) `
      -ConflictAction ([string]$body.conflictAction) `
      -AddToOtherPages ([bool]$body.addToOtherPages) `
      -CleanDeletedLinks $false
    Send-Json -Context $Context -Data $result
    return
  }

  if ($request.HttpMethod -eq "POST" -and $path -eq "/api/clean-deleted-links") {
    $updatedCount = Update-Book2HtmlNavigation `
      -CurrentOutputPage $null `
      -CurrentLabel $null `
      -AddCurrentToOtherPages $false `
      -CleanDeletedLinks $true
    Send-Json -Context $Context -Data ([pscustomobject]@{
      ok = $true
      navigationUpdatedCount = $updatedCount
    })
    return
  }

  if ($request.HttpMethod -eq "POST" -and $path -eq "/api/open-output") {
    $pathToOpen = $script:LastOutputPage
    if ([string]::IsNullOrWhiteSpace($pathToOpen) -or -not (Test-Path -LiteralPath $pathToOpen)) {
      $latestGeneratedPage = Get-ChildItem -LiteralPath $SiteRoot -File -Filter "bookmarks_*.html" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
      if ($latestGeneratedPage) {
        $pathToOpen = $latestGeneratedPage.FullName
      } elseif (Test-Path -LiteralPath $DefaultOutputPage) {
        $pathToOpen = $DefaultOutputPage
      } else {
        throw "还没有生成 HTML。"
      }
    }
    Start-Process -FilePath $pathToOpen | Out-Null
    Send-Json -Context $Context -Data ([pscustomobject]@{ ok = $true })
    return
  }

  if ($request.HttpMethod -eq "POST" -and $path -eq "/api/open-site") {
    $body = Read-JsonBody -Request $request
    $pathToOpen = Resolve-SiteRelativeFile -RelativePath ([string]$body.path)
    Start-Process -FilePath $pathToOpen | Out-Null
    Send-Json -Context $Context -Data ([pscustomobject]@{
      ok = $true
      path = $pathToOpen
      href = (New-Object System.Uri($pathToOpen)).AbsoluteUri
    })
    return
  }

  if ($request.HttpMethod -eq "POST" -and $path -eq "/api/stop") {
    $script:StopRequested = $true
    Send-Json -Context $Context -Data ([pscustomobject]@{ ok = $true })
    return
  }

  Send-Error -Context $Context -StatusCode 404 -Message "未找到接口：$($request.HttpMethod) $path"
}

function Start-LocalServer {
  param([int]$RequestedPort)

  for ($candidate = $RequestedPort; $candidate -lt ($RequestedPort + 40); $candidate++) {
    $listener = New-Object System.Net.HttpListener
    $prefix = "http://127.0.0.1:$candidate/"
    $listener.Prefixes.Add($prefix)

    try {
      $listener.Start()
      return [pscustomobject]@{
        listener = $listener
        port = $candidate
        url = $prefix
      }
    } catch {
      try {
        $listener.Close()
      } catch {
      }
    }
  }

  throw "无法启动本地服务。请确认端口 $RequestedPort 到 $($RequestedPort + 39) 没有被占用，或尝试以管理员身份运行。"
}

Clear-BookmarkSnapshotCache
$server = Start-LocalServer -RequestedPort $Port
Write-Host "Book2HTML server started: $($server.url)"
Write-Host "Site root: $SiteRoot"
Write-Host "Output pattern: bookmarks_<folder-name>.html"
Write-Host "Press Ctrl+C to stop."

if (-not $NoBrowser) {
  Start-Process $server.url | Out-Null
}

try {
  while ($server.listener.IsListening -and -not $script:StopRequested) {
    $context = $server.listener.GetContext()
    try {
      Handle-Request -Context $context
    } catch {
      try {
        Send-Error -Context $context -Message $_.Exception.Message
      } catch {
      }
    }
  }
} finally {
  if ($server.listener.IsListening) {
    $server.listener.Stop()
  }
  $server.listener.Close()
  Write-Host "Book2HTML server stopped."
}
