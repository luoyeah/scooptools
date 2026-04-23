<#
.SYNOPSIS
    提前将安装包复制到 Scoop 缓存目录

.DESCRIPTION
    将安装包复制到 Scoop 缓存目录，然后使用 Scoop 安装。
    支持处理 file:// URLs，确保安装正常工作。

.PARAMETER ManifestFile
    清单文件路径 (.json)，可以是相对路径或绝对路径

.EXAMPLE
    .\scoopi.ps1 .\myapp.json

#>

param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="清单文件路径")]
    [string]$ManifestFile
)
# 启用严格模式确保变量在使用前被初始化
# Set-StrictMode -Version Latest

# 遇到错误时立即停止执行
$ErrorActionPreference = "Stop"

# 
. "$PSScriptRoot/stub.ps1"
. "$PSScriptRoot/lib.ps1"


# 检查清单文件是否存在
if (-not (Test-Path $ManifestFile)) {
    throw "清单文件未找到: $ManifestFile"
}

# 转换为绝对路径
$ManifestFile = Convert-Path -Path $ManifestFile

# 获取清单文件所在文件夹
$manifest_dir = Split-Path -Parent $ManifestFile

# 解析 JSON 内容
$manifest = Parse-Json -Path $ManifestFile

if ($null -eq $manifest) {
    throw "清单解析失败"
}

# 获取应用名称和版本
$appName = [System.IO.Path]::GetFileNameWithoutExtension($ManifestFile)
$version = if ($manifest.PSObject.Properties['version']) {
    $manifest.version
}
else {
    "0"
}

$architecture = Get-DefaultArchitecture

# 获取所有链接
$urls = @(script:url $manifest $architecture)

foreach($url in $urls){
    # 缓存文件名称
    $cache_file = cache_path $appName $version $url

    # url对于本地名称
    $local_file = UriToFilePath -Uri $url -BaseDir $manifest_dir

    if(-not (Test-Path $local_file)){
        Write-Host "Url file not exist: $local_file"
    }else{
        if(!(Test-Path $cache_file)){
            Write-Host "Copy $local_file -> $cache_file"
            Copy-Item -Path $local_file -Destination $cache_file -Force
        }else{
            Write-Host "File Exist $cache_file"
        }
    }
}

& scoop install -u $ManifestFile
