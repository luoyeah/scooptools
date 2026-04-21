<#
.SYNOPSIS
    修复 Scoop 清单并安装

.DESCRIPTION
    此脚本用于修复清单中的相对路径，将其复制到 Scoop 缓存目录，然后使用 Scoop 安装。
    支持处理 file:// URLs 和相对路径，确保安装正常工作。

.PARAMETER ManifestFile
    清单文件路径 (.json)，可以是相对路径或绝对路径

.PARAMETER Help
    显示帮助信息

.EXAMPLE
    .\scoopi.ps1 .\myapp.json

.EXAMPLE
    .\scoopi.ps1 -Help
#>

param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="清单文件路径")]
    [string]$ManifestFile,

    [Parameter(Position=1)]
    [switch]$Help
)

# 显示帮助信息
if ($Help) {
    Get-Help -Name $MyInvocation.PSCommandPath -Detailed
    exit 0
}

# 启用严格模式确保变量在使用前被初始化
Set-StrictMode -Version Latest

# 遇到错误时立即停止执行
$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
    解析 JSON 文件

.PARAMETER Path
    JSON 文件路径

.RETURN
    JSON 对象，解析失败返回 $null
#>
function Parse-Json {
    param([string]$Path)
    
    # 检查文件是否存在
    if (-not (Test-Path $Path)) {
        Write-Error "文件未找到: $Path"
        return $null
    }
    
    try {
        # 读取文件内容并转换为 JSON 对象
        Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Error "JSON 解析失败: $_"
        return $null
    }
}

<#
.SYNOPSIS
    获取缓存目录路径

.PARAMETER App
    应用名称

.PARAMETER Version
    版本号

.PARAMETER Url
    下载 URL

.RETURN
    缓存文件路径
#>
function Get-CachePath {
    param(
        [string]$App,
        [string]$Version,
        [string]$Url
    )
    
    # 确定缓存目录位置，优先使用 SCOOP_CACHE，否则使用 SCOOP 下的 cache 目录
    $cacheDir = if ($env:SCOOP_CACHE) {
        $env:SCOOP_CACHE
    }
    elseif ($env:SCOOP) {
        Join-Path $env:SCOOP "cache"
    }
    else {
        throw "SCOOP 或 SCOOP_CACHE 环境变量未设置"
    }
    
    # 将 URL 转换为文件名，替换非法字符为下划线
    $underscoredUrl = $Url -replace '[^\w\.\-]+', '_'
    $filePath = Join-Path $cacheDir "$App#$Version#$underscoredUrl"
    
    # 如果文件已存在，直接返回路径
    if (Test-Path $filePath) {
        return $filePath
    }
    
    # 计算 URL 的 SHA256 哈希前7位作为文件名
    $urlStream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($Url))
    $sha = (Get-FileHash -Algorithm SHA256 -InputStream $urlStream).Hash.ToLower().Substring(0, 7)
    $extension = [System.IO.Path]::GetExtension($Url)
    $filePath = $filePath -replace [regex]::Escape($underscoredUrl), "$sha$extension"
    
    return $filePath
}

<#
.SYNOPSIS
    将文件复制到 Scoop 缓存目录

.PARAMETER SourcePath
    源文件路径

.PARAMETER AppName
    应用名称

.PARAMETER Version
    版本号

.RETURN
    复制成功返回 $true，失败返回 $false
#>
function Copy-ToCache {
    param(
        [string]$SourcePath,
        [string]$AppName,
        [string]$Version,
        [string]$Url
    )
    
    # 检查源文件是否存在
    if (-not (Test-Path $SourcePath)) {
        Write-Warning "源文件未找到: $SourcePath"
        return $false
    }
    
    $cachePath = Get-CachePath -App $AppName -Version $Version -Url $url
    
    # 如果缓存文件已存在，跳过复制
    if (Test-Path $cachePath) {
        Write-Verbose "缓存文件已存在: $cachePath"
        return $true
    }
    
    # 创建缓存目录（如不存在）
    $cacheDir = Split-Path $cachePath -Parent
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    
    # 复制文件到缓存目录
    Copy-Item -Path $SourcePath -Destination $cachePath -Force
    Write-Host "已复制到缓存: $SourcePath -> $cachePath" -ForegroundColor Cyan
    
    return $true
}

<#
.SYNOPSIS
    将相对路径转换为绝对 file:// URL

.PARAMETER UrlValue
    URL 值或相对路径

.PARAMETER BasePath
    基准路径

.RETURN
    绝对 file:// URL
#>
function ConvertTo-AbsoluteUrl {
    param(
        [string]$UrlValue,
        [string]$BasePath
    )
    
    # 空值直接返回
    if ([string]::IsNullOrWhiteSpace($UrlValue)) {
        return $UrlValue
    }
    
    # 如果已是绝对路径或 URL，直接返回
    if ([System.IO.Path]::IsPathRooted($UrlValue) -or
        $UrlValue -match '^(http|https|ftp|file)://') {
        return $UrlValue
    }
    
    # 分离路径和片段（如有）
    $pathPart = $UrlValue
    $fragmentPart = $null
    
    if ($UrlValue -match '^(.+)(#.+)$') {
        $pathPart = $matches[1]
        $fragmentPart = $matches[2]
    }
    
    # 拼接为绝对路径
    $absolutePath = Join-Path $BasePath $pathPart
    $absolutePath = [System.IO.Path]::GetFullPath($absolutePath)
    
    # 检查文件是否存在
    if (-not (Test-Path $absolutePath)) {
        throw "文件未找到: $absolutePath"
    }
    
    # 重新拼接片段（如有）
    if ($fragmentPart) {
        $absolutePath = $absolutePath + $fragmentPart
    }
    
    return "file:///" + $absolutePath
}

<#
.SYNOPSIS
    创建临时清单文件（用于处理相对路径）

.PARAMETER InputFile
    输入清单文件路径

.PARAMETER JsonObject
    JSON 对象

.RETURN
    临时清单文件路径，无需处理返回 $null
#>
function Get-TempManifest {
    param(
        [string]$InputFile,
        [object]$JsonObject
    )
    
    # 检查 JSON 对象是否有 url 字段
    if (-not $JsonObject.PSObject.Properties['url']) {
        return $null
    }
    
    $urlValue = $JsonObject.url
    if ([string]::IsNullOrEmpty($urlValue)) {
        return $null
    }
    
    # 获取清单文件所在目录作为基准路径
    $basePath = Split-Path $InputFile -Parent
    
    # 如果是远程 URL，无需处理
    if ($urlValue -match '^(http|https|ftp)://') {
        return $null
    }
    
    # 将相对路径转换为绝对路径
    if (-not [System.IO.Path]::IsPathRooted($urlValue)) {
        $JsonObject.url = ConvertTo-AbsoluteUrl -UrlValue $urlValue -BasePath $basePath
    }
    else {
        return $null
    }
    
    # 创建临时目录
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "scoop_manifest_temp"
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    
    # 生成临时清单文件路径
    $fileName = [System.IO.Path]::GetFileName($InputFile)
    $outputFile = Join-Path $tempDir $fileName
    
    # 将修改后的 JSON 写入临时文件
    $JsonObject | ConvertTo-Json -Depth 20 | Out-File -FilePath $outputFile -Encoding UTF8 -Force
    
    Write-Host "已创建临时清单: $outputFile" -ForegroundColor Green
    
    return $outputFile
}

<#
.SYNOPSIS
    删除临时清单文件

.PARAMETER Path
    临时清单文件路径
#>
function Remove-TempManifest {
    param([string]$Path)
    
    if ($Path -and (Test-Path $Path)) {
        Remove-Item -Path $Path -Force
        Write-Verbose "已删除临时清单: $Path"
    }
}

function Copy-LocalFileToCache {
    param(
        [object]$JsonObject,
        [string]$AppName,
        [string]$Version
    )
    
    if ($JsonObject -and $JsonObject.PSObject.Properties['url'] -and $JsonObject.url -match '^file:///.+') {
        $localPath = $JsonObject.url -replace '^file:///', ''
        $localPath = $localPath -replace '#.+$', ''
        $localPath = [System.IO.Path]::GetFullPath($localPath)
        
        if (Test-Path $localPath) {
            Copy-ToCache -SourcePath $localPath -AppName $AppName -Version $Version -Url $JsonObject.url
        }
    }
}

<#
.SYNOPSIS
    使用 Scoop 安装清单

.PARAMETER ManifestPath
    清单文件路径
#>
function Install-Manifest {
    param([string]$ManifestPath)
    
    Write-Host "正在安装: $ManifestPath" -ForegroundColor Green
    
    & scoop install -u $ManifestPath
    
    # 检查安装是否成功
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        throw "Scoop 安装失败，退出代码: $LASTEXITCODE"
    }
    
    Write-Host "安装完成" -ForegroundColor Green
}

try {
    # 解析清单文件路径
    $manifestFile = Convert-Path -Path $ManifestFile
    
    # 检查清单文件是否存在
    if (-not (Test-Path $manifestFile)) {
        throw "清单文件未找到: $ManifestFile"
    }
    
    # 解析 JSON 内容
    $jsonObject = Parse-Json -Path $manifestFile
    
    if ($null -eq $jsonObject) {
        throw "清单解析失败"
    }
    
    # 获取应用名称和版本
    $appName = [System.IO.Path]::GetFileNameWithoutExtension($manifestFile)
    $version = if ($jsonObject.PSObject.Properties['version']) {
        $jsonObject.version
    }
    else {
        "0"
    }
    
    Copy-LocalFileToCache -JsonObject $jsonObject -AppName $appName -Version $version
    
    # 创建临时清单（处理相对路径）
    $tempManifest = Get-TempManifest -InputFile $manifestFile -JsonObject $jsonObject

    # 如果创建了临时清单，从临时清单获取需要复制的本地文件路径
    if ($tempManifest) {
        $tempJsonObject = Parse-Json -Path $tempManifest
        Copy-LocalFileToCache -JsonObject $tempJsonObject -AppName $appName -Version $version
    }

    # 确定安装时使用的清单路径
    $installPath = if ($tempManifest) { $tempManifest } else { $manifestFile }
    
    # 执行安装
    Install-Manifest -ManifestPath $installPath
}
finally {
    # 清理临时清单文件
    if ($tempManifest) {
        # Remove-TempManifest -Path $tempManifest
    }
}