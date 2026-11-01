<#
  LYEJ.CN 数据管线 —— 京东联盟商品抓取 + 转链 + 生成站点 JSON
  运行环境: PowerShell 5.1+ (Windows 本机 / GitHub Actions windows-latest 通用)
  密钥来源(优先级): 环境变量 JD_APP_KEY_A/SECRET_A, JD_APP_KEY_B/SECRET_B > automation/local.secrets.ps1
  输出: data/products.json (站点唯一数据源), data/linkcache.json (转链缓存)
#>
param(
    [string]$RootDir = ""
)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- paths ----------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($RootDir -eq "") { $RootDir = Split-Path -Parent $ScriptDir }
$DataDir = Join-Path $RootDir "data"
$LogFile = Join-Path $ScriptDir "last_run.log"
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

function Write-Log {
    param([string]$Msg)
    $line = ("[{0}] {1}" -f ([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, "China Standard Time")).ToString("MM-dd HH:mm:ss"), $Msg)
    Write-Output $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# ---------- secrets ----------
# local.secrets.ps1 不入库(.gitignore)，内容形如:
#   $env:JD_APP_KEY_A=".."; $env:JD_APP_SECRET_A=".."
$LocalSecrets = Join-Path $ScriptDir "local.secrets.ps1"
if (Test-Path $LocalSecrets) { . $LocalSecrets }

# ---------- config ----------
$Config = Get-Content (Join-Path $ScriptDir "config.json") -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-AppKeys {
    $list = @()
    foreach ($k in $Config.appKeys) {
        $envPair = $Config.envKeys.$($k.name)
        $key = [Environment]::GetEnvironmentVariable($envPair.key)
        $sec = [Environment]::GetEnvironmentVariable($envPair.secret)
        if (-not $key -and $k.key) { $key = $k.key; $sec = $k.secret }
        if ($key -and $sec) { $list += @{ name = $k.name; key = $key; secret = $sec } }
    }
    return ,$list
}

# ---------- jd api core ----------
function ConvertTo-JsonAscii {
    param([string]$s)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        if ([int]$ch -gt 127) { $sb.Append("\u" + ([int]$ch).ToString("x4")) | Out-Null }
        else { $sb.Append($ch) | Out-Null }
    }
    $sb.ToString()
}

function Get-BeijingNow {
    [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, "China Standard Time")
}

function New-Sign {
    param($params, [string]$secret)
    $sb = New-Object System.Text.StringBuilder
    $sb.Append($secret) | Out-Null
    foreach ($k in ($params.Keys | Sort-Object)) { $sb.Append($k).Append([string]$params[$k]) | Out-Null }
    $sb.Append($secret) | Out-Null
    $md5 = [System.Security.Cryptography.MD5]::Create()
    return ([System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sb.ToString())))).Replace("-", "")
}

$Script:ApiCalls = 0
$Script:CurrentKeyIdx = 0

# 返回 hashtable: { ok, result(解析后的 inner JSON 对象或 null), raw, error }
function Invoke-Jd {
    param([string]$Method, [string]$BizJson)
    $keys = $Script:AppKeys
    $maxTry = [Math]::Min(2, $keys.Count)   # 每次调用最多在 2 个 key 间切换
    $raw = $null
    for ($attempt = 0; $attempt -lt $maxTry; $attempt++) {
        $idx = ($Script:CurrentKeyIdx + $attempt) % $keys.Count
        $ak = $keys[$idx]
        $params = @{
            "method" = $Method; "app_key" = $ak.key; "format" = "json"; "v" = "1.0"
            "sign_method" = "md5"; "timestamp" = (Get-BeijingNow).ToString("yyyy-MM-dd HH:mm:ss")
            "360buy_param_json" = (ConvertTo-JsonAscii $BizJson)
        }
        $params["sign"] = New-Sign $params $ak.secret
        $qs = @()
        foreach ($k in $params.Keys) { $qs += [Uri]::EscapeDataString($k) + "=" + [Uri]::EscapeDataString([string]$params[$k]) }
        $Script:ApiCalls++
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Encoding = [System.Text.Encoding]::UTF8
            $wc.Headers.Add("User-Agent", "lyej-pipeline/1.0")
            $raw = $wc.DownloadString("https://api.jd.com/routerjson?" + ($qs -join "&"))
        } catch {
            Write-Log ("HTTP error [{0}]: {1}" -f $ak.name, $_.Exception.Message)
            continue
        }
        if ($raw -match '"code":"?2000"?' -and $raw -match "上限|Limited") {
            Write-Log ("key {0}: 商品接口当日配额用尽，切换/终止" -f $ak.name)
            continue   # 配额问题，尝试下一个 key
        }
        $Script:CurrentKeyIdx = $idx   # 成功的 key 优先复用
        break
    }
    if (-not $raw) { return @{ ok = $false; result = $null; raw = ""; error = "all-keys-failed" } }

    # 解析 response
    try {
        $resp = $raw | ConvertFrom-Json
    } catch {
        return @{ ok = $false; result = $null; raw = $raw; error = "json-parse" }
    }
    if ($resp.PSObject.Properties["error_response"]) {
        return @{ ok = $false; result = $null; raw = $raw; error = ("gateway:" + $resp.error_response.code) }
    }
    $inner = $null
    foreach ($p in $resp.PSObject.Properties) {
        if ($p.Name -like "*_responce") { $inner = $p.Value; break }
    }
    if (-not $inner) { return @{ ok = $false; result = $null; raw = $raw; error = "no-inner" } }
    if ("$($inner.code)" -ne "0") { return @{ ok = $false; result = $null; raw = $raw; error = ("inner:" + $inner.code) } }
    if ($inner.PSObject.Properties["result"] -and $inner.result) {
        try { return @{ ok = $true; result = ($inner.result | ConvertFrom-Json); raw = $raw; error = "" } }
        catch { return @{ ok = $true; result = $inner.result; raw = $raw; error = "" } }
    }
    return @{ ok = $true; result = $inner; raw = $raw; error = "" }
}

# ---------- helpers ----------
function Get-Prop {
    param($obj, [string]$Name, $Default = $null)
    if ($null -eq $obj) { return $Default }
    $p = $obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $Default
}

function To-Double {
    param($v, [double]$Default = 0)
    if ($null -eq $v) { return $Default }
    $d = 0
    if ([double]::TryParse([string]$v, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return $Default
}

function Get-ShortName {
    param([string]$name, [string]$brand)
    $s = $name
    $s = $s -replace "（[^）]{0,12}）", " "          # 全角括号品牌段
    $s = $s -replace "\([^)]{0,12}\)", " "
    $s = $s -replace "\s+", " "
    $s = $s.Trim()
    if ($brand -and $s.StartsWith($brand)) { $s = $s.Substring($brand.Length).Trim() }
    if ($s.Length -gt 24) { $s = $s.Substring(0, 24) }
    return $s
}

$SceneRegex = @{
    "降噪"  = "降噪|ANC"
    "骨传导" = "骨传导"
    "开放式" = "开放式|OWS|夹耳|挂耳式"
    "游戏"  = "游戏|电竞|低延迟"
    "运动"  = "运动|跑步|防水|IPX"
    "头戴式" = "头戴|耳罩式"
    "睡眠"  = "睡眠|侧睡"
    "通话"  = "通话|会议|商务"
}
function Get-Scenes {
    param([string]$name, [string]$kwTag)
    $tags = @()
    if ($kwTag -and $kwTag -ne "爆款") { $tags += $kwTag }
    foreach ($k in $SceneRegex.Keys) {
        if ($name -match $SceneRegex[$k] -and $tags -notcontains $k) { $tags += $k }
    }
    if ($tags.Count -eq 0) { $tags += "通用" }
    return $tags
}

# ---------- link cache ----------
$CachePath = Join-Path $DataDir "linkcache.json"
$LinkCache = New-Object PSObject
if (Test-Path $CachePath) {
    try { $LinkCache = Get-Content $CachePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $LinkCache = New-Object PSObject }
}
$ManualLinks = @{}
$ManualPath = Join-Path $DataDir "manual-links.json"
if (Test-Path $ManualPath) {
    try { $ManualLinks = Get-Content $ManualPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

$Script:SocialBlocked = $false
$Script:WebsiteSiteId = $Config.channels.websiteSiteId
if ($env:JD_SITE_ID_WEBSITE) { $Script:WebsiteSiteId = $env:JD_SITE_ID_WEBSITE }

# 返回 @{ link, strategy }
function Get-PromoLink {
    param([string]$materialId)
    # 0) 手工维护链接优先
    $m = Get-Prop $ManualLinks $materialId
    if ($m) { return @{ link = $m; strategy = "manual" } }
    # 1) 缓存有效
    $c = Get-Prop $LinkCache $materialId
    if ($c -and $c.link) {
        $ageDays = 999
        try { $ageDays = ((Get-Date) - ([datetime]::Parse($c.date))).TotalDays } catch {}
        if ($ageDays -lt $Config.linkCacheDays) { return @{ link = $c.link; strategy = "cache" } }
    }
    # 2) 网站/APP 渠道 (common.get)
    if ($Script:WebsiteSiteId) {
        $r = Invoke-Jd "jd.union.open.promotion.common.get" ('{"promotionCodeReq":{"materialId":"' + $materialId + '","siteId":' + $Script:WebsiteSiteId + '}}')
        if ($r.ok -and $r.result -and "$($r.result.code)" -eq "200" -and $r.result.data -and $r.result.data.shortURL) {
            return @{ link = $r.result.data.shortURL; strategy = "website" }
        }
    }
    # 3) 社媒渠道 (bysubunionid, 需权限)
    if ($Config.channels.socialPositionId -and -not $Script:SocialBlocked) {
        $r = Invoke-Jd "jd.union.open.promotion.bysubunionid.get" ('{"promotionCodeReq":{"materialId":"' + $materialId + '","positionId":' + $Config.channels.socialPositionId + '}}')
        if ($r.ok -and $r.result -and "$($r.result.code)" -eq "200" -and $r.result.data -and $r.result.data.shortURL) {
            return @{ link = $r.result.data.shortURL; strategy = "social" }
        }
        if ("$($r.error)" -match "403" -or ($r.result -and "$($r.result.code)" -eq "403")) { $Script:SocialBlocked = $true }
    }
    return @{ link = ""; strategy = "none" }
}

function Save-LinkCache {
    $out = @{}
    foreach ($p in $LinkCache.PSObject.Properties) { $out[$p.Name] = $p.Value }
    $json = $out | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($CachePath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------- fetch goods ----------
$Script:AppKeys = Get-AppKeys
if ($Script:AppKeys.Count -eq 0) {
    Write-Log "FATAL: 未配置任何 appKey（环境变量或 local.secrets.ps1）"
    exit 1
}
Write-Log ("可用 appKey: " + (($Script:AppKeys | ForEach-Object { $_.name }) -join ", "))

$Script:allItems = @()   # 原始商品
$Script:seen = @{}       # skuId 去重
$Script:quotaHit = $false

function Fetch-Keyword {
    param([string]$kw, [int]$pages, [string]$tag)
    for ($p = 1; $p -le $pages; $p++) {
        if ($Script:ApiCalls -ge $Config.maxApiCallsPerRun) { Write-Log "达到单次运行调用上限，停止抓取"; return }
        $biz = '{"goodsReqDTO":{"keyword":"' + $kw + '","pageIndex":' + $p + ',"pageSize":30,"sortName":"inOrderCount30Days","sort":"desc"}}'
        $r = Invoke-Jd "jd.union.open.goods.query" $biz
        if (-not $r.ok) {
            if ("$($r.error)" -match "2000") { $Script:quotaHit = $true; Write-Log ("配额受限 [{0}] p{1}" -f $kw, $p); return }
            Write-Log ("查询失败 [{0}] p{1}: {2}" -f $kw, $p, $r.error)
            continue
        }
        $qr = $r.result
        if ("$($qr.code)" -ne "200") { Write-Log ("业务失败 [{0}] p{1}: code={2} msg={3}" -f $kw, $p, $qr.code, $qr.message); continue }
        $n = 0
        foreach ($g in @($qr.data)) {
            $sid = [string](Get-Prop $g "skuId")
            if (-not $sid -or $Script:seen.ContainsKey($sid)) { continue }
            $Script:seen[$sid] = $true
            $Script:allItems += @{ item = $g; kwTag = $tag }
            $n++
        }
        Write-Log ("[{0}] p{1} -> +{2} (累计{3})" -f $kw, $p, $n, $Script:allItems.Count)
    }
}

foreach ($vk in $Config.verticalKeywords) { Fetch-Keyword -kw $vk.kw -pages $vk.pages -tag $vk.tag }
$verticalCount = $Script:allItems.Count

$bundles = @()
$bundleSeenBegins = $allItems.Count
foreach ($bk in $Config.bundleKeywords) { Fetch-Keyword -kw $bk.kw -pages $bk.pages -tag "凑单" }
# 凑单区商品单独收集
$bundlesRaw = @()
if ($Script:allItems.Count -gt $bundleSeenBegins) { $bundlesRaw = $Script:allItems[$bundleSeenBegins..($Script:allItems.Count - 1)] }

if ($Script:quotaHit) { Write-Log "!! 本轮遇到配额限制，仅使用已抓到的数据" }

# ---------- normalize + filter ----------
$F = $Config.filters
$products = @()
foreach ($row in $Script:allItems) {
    $g = $row.item
    $name = [string](Get-Prop $g "skuName")
    if (-not $name) { continue }
    if ($name -match $F.excludeNameRegex) { continue }

    $priceInfo = Get-Prop $g "priceInfo"
    $price = To-Double (Get-Prop $priceInfo "price") 0
    $lowest = To-Double (Get-Prop $priceInfo "lowestPrice") $price
    $lowestType = To-Double (Get-Prop $priceInfo "lowestPriceType") 0
    if ($price -lt $F.minPrice) { continue }

    $commInfo = Get-Prop $g "commissionInfo"
    $commShare = To-Double (Get-Prop $commInfo "commissionShare") 0
    $commYuan = To-Double (Get-Prop $commInfo "commission") 0
    if ($commShare -lt $F.minCommissionShare -and $commYuan -lt $F.minCommissionYuan) { continue }

    # 到手价: lowestPriceType=1 时 lowestPrice 即券后价
    $priceAfter = if ($lowestType -eq 1 -and $lowest -gt 0) { $lowest } else { $price }

    # 优惠券
    $couponQuota = 0; $couponCut = 0; $couponUrl = ""
    $couponInfo = Get-Prop $g "couponInfo"
    $cList = Get-Prop $couponInfo "couponList"
    if ($cList) {
        $best = $null
        foreach ($c in @($cList)) {
            $cut = To-Double (Get-Prop $c "couponPrice") 0
            if ($cut -gt $couponCut) { $best = $c; $couponCut = $cut }
        }
        if ($best) {
            $couponQuota = To-Double (Get-Prop $best "couponQuota") 0
            $couponUrl = [string](Get-Prop $best "link")
        }
        if ($lowestType -ne 1 -and $couponCut -gt 0) { $priceAfter = [Math]::Max(0, $price - $couponCut) }
    }

    # 好评率
    $goodRate = 0
    $gc = Get-Prop $g "goodCommentsInfo"
    $goodRate = To-Double (Get-Prop $gc "goodCommentsShare") 0
    if ($goodRate -eq 0) { $goodRate = To-Double (Get-Prop $g "inOrderCount30DaysGoodCommentsShare") 0 }
    if ($goodRate -gt 0 -and $goodRate -lt $F.minGoodComments) { continue }

    $sales30d = To-Double (Get-Prop $g "inOrderCount30Days") 0
    if ($sales30d -gt 0 -and $sales30d -lt $F.minSales30d) { continue }

    $brand = [string](Get-Prop $g "brandName")
    if (-not $brand) {
        foreach ($b in $F.brandsBoost) { if ($name -match [regex]::Escape($b)) { $brand = $b; break } }
    }
    $shopInfo = Get-Prop $g "shopInfo"
    $shopName = [string](Get-Prop $shopInfo "shopName")
    $isSelf = ($shopName -match "京东自营")

    $img = ""
    $imgInfo = Get-Prop $g "imageInfo"
    $imgList = Get-Prop $imgInfo "imageList"
    if ($imgList -and @($imgList).Count -gt 0) { $img = [string](Get-Prop @($imgList)[0] "url") }

    $priceFinal = $priceAfter
    $score = $sales30d * 0.05
    if ($F.brandsBoost -contains $brand) { $score += 30 }
    if ($isSelf) { $score += 15 }
    $score += $commYuan * 2

    $products += [ordered]@{
        skuId = [string](Get-Prop $g "skuId")
        name = $name
        shortName = (Get-ShortName $name $brand)
        brand = $brand
        image = $img
        price = [Math]::Round($price, 2)
        priceAfter = [Math]::Round($priceFinal, 2)
        couponQuota = [Math]::Round($couponQuota, 0)
        couponCut = [Math]::Round($couponCut, 0)
        commissionShare = $commShare
        commission = [Math]::Round($commYuan, 2)
        sales30d = $sales30d
        goodRate = $goodRate
        shopName = $shopName
        selfRun = [bool]$isSelf
        kwTag = $row.kwTag
        scenes = (Get-Scenes $name $row.kwTag)
        score = [Math]::Round($score, 1)
        link = ""
        linkStrategy = ""
    }
}
Write-Log ("垂直商品通过筛选: {0}/{1}" -f $products.Count, $verticalCount)

# ---------- 转链（先垂直后凑单，节约调用） ----------
$needLink = @($products | Sort-Object -Property @{Expression="score";Descending=$true})
$linked = 0
foreach ($p in $needLink) {
    if ($Script:ApiCalls -ge $Config.maxApiCallsPerRun) { Write-Log "转链前达到调用上限，其余商品用兜底链接"; break }
    $r = Get-PromoLink -materialId $p.skuId
    if ($r.link) {
        $p.link = $r.link
        $p.linkStrategy = $r.strategy
        if ($r.strategy -ne "cache" -and $r.strategy -ne "manual") {
            $LinkCache | Add-Member -MemberType NoteProperty -Name $p.skuId -Value @{ link = $r.link; date = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); strategy = $r.strategy } -Force
        }
        $linked++
    }
}
Write-Log ("转链成功: {0}/{1} (调用累计{2})" -f $linked, $needLink.Count, $Script:ApiCalls)

# ---------- 分价位榜单 ----------
$bandOut = @()
foreach ($band in $Config.bands) {
    $pool = @($products | Where-Object { $_.priceAfter -ge $band.min -and $_.priceAfter -lt $band.max } | Sort-Object -Property @{Expression="score";Descending=$true})
    $sel = @()
    foreach ($p in $pool) { if ($sel.Count -lt $band.cap) { $sel += $p } }
    $bandOut += [ordered]@{ id = $band.id; label = $band.label; min = $band.min; max = $band.max; skus = @($sel | ForEach-Object { $_.skuId }) }
}

# ---------- 凑单区 ----------
$bundleOut = @()
$bundleById = @{}
foreach ($row in $bundlesRaw) {
    $g = $row.item
    $name = [string](Get-Prop $g "skuName")
    if (-not $name -or $name -match $F.excludeNameRegex) { continue }
    $priceInfo = Get-Prop $g "priceInfo"
    $price = To-Double (Get-Prop $priceInfo "price") 0
    if ($price -lt 19) { continue }
    $commInfo = Get-Prop $g "commissionInfo"
    $commYuan = To-Double (Get-Prop $commInfo "commission") 0
    if ($commYuan -lt 0.5) { continue }
    $sid = [string](Get-Prop $g "skuId")
    if ($bundleById.ContainsKey($sid)) { continue }
    $imgInfo = Get-Prop $g "imageInfo"
    $imgList = Get-Prop $imgInfo "imageList"
    $img = ""
    if ($imgList -and @($imgList).Count -gt 0) { $img = [string](Get-Prop @($imgList)[0] "url") }
    $bundleById[$sid] = $true
    $lr = Get-PromoLink -materialId $sid
    $bundleOut += [ordered]@{
        skuId = $sid; name = (Get-ShortName $name ""); image = $img
        price = [Math]::Round($price, 2); sales30d = (To-Double (Get-Prop $g "inOrderCount30Days") 0)
        link = $lr.link; linkStrategy = $lr.strategy
    }
    if ($bundleOut.Count -ge 9) { break }
}

# ---------- 活动链接 ----------
$actOut = @()
foreach ($a in $Config.activities) {
    $strategy = ""
    if ($a.PSObject.Properties["fixed"] -and $a.fixed) {
        # 已转好的固定链接（手工转的红包/专场页），直接使用
        $link = [string]$a.url
        $strategy = "fixed"
    } else {
        $r = Get-PromoLink -materialId $a.url
        $link = $r.link
        $strategy = $r.strategy
        if (-not $link) { $link = $Config.channels.homepageFallbackLink; $strategy = "fallback" }
    }
    $actOut += [ordered]@{ id = $a.id; title = $a.title; desc = $a.desc; url = $a.url; link = $link; strategy = $strategy }
}

# ---------- 场景索引 ----------
$sceneOut = [ordered]@{}
foreach ($p in $products) {
    foreach ($s in $p.scenes) {
        if (-not $sceneOut.Contains($s)) { $sceneOut[$s] = @() }
        if ($sceneOut[$s].Count -lt 10) { $arr = @($sceneOut[$s]); $arr += $p.skuId; $sceneOut[$s] = $arr }
    }
}

Save-LinkCache

# ---------- 写 products.json ----------
$productList = @($needLink | ForEach-Object {
    [ordered]@{
        skuId = $_.skuId; name = $_.name; shortName = $_.shortName; brand = $_.brand
        image = $_.image; price = $_.price; priceAfter = $_.priceAfter
        couponQuota = $_.couponQuota; couponCut = $_.couponCut
        commissionShare = $_.commissionShare; commission = $_.commission
        sales30d = $_.sales30d; goodRate = $_.goodRate; shopName = $_.shopName; selfRun = $_.selfRun
        scenes = $_.scenes; link = $_.link; linkStrategy = $_.linkStrategy
    }
})
$outObj = [ordered]@{
    updatedAt = (Get-BeijingNow).ToString("yyyy-MM-dd HH:mm:ss")
    source = "jd-union-api"
    quotaHit = [bool]$Script:quotaHit
    apiCalls = $Script:ApiCalls
    stats = [ordered]@{ fetched = $verticalCount; passed = $products.Count; linked = $linked }
    bands = $bandOut
    scenes = $sceneOut
    activities = $actOut
    bundles = $bundleOut
    products = $productList
}
$json = $outObj | ConvertTo-Json -Depth 8
$OutPath = Join-Path $DataDir "products.json"
[System.IO.File]::WriteAllText($OutPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Log ("已写出 {0} ({1} KB)" -f $OutPath, [int]((Get-Item $OutPath).Length / 1KB))
Write-Log ("完成: 抓取{0} 通过{1} 转链{2} 凑单{3} API调用{4}" -f $verticalCount, $products.Count, $linked, $bundleOut.Count, $Script:ApiCalls)
