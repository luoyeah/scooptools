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


# ----------------从scoop复制代码------------------------------------------------
$configHome = $env:XDG_CONFIG_HOME, "$env:USERPROFILE\.config" | Select-Object -First 1
$configFile = "$configHome\scoop\config.json"

function load_cfg($file) {
    if(!(Test-Path $file)) {
        return $null
    }

    try {
        # ReadAllLines will detect the encoding of the file automatically
        # Ref: https://docs.microsoft.com/en-us/dotnet/api/system.io.file.readalllines?view=netframework-4.5
        $content = [System.IO.File]::ReadAllLines($file)
        return ($content | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        Write-Host "ERROR loading $file`: $($_.exception.message)"
    }
}

$scoopConfig = load_cfg $configFile


function get_config($name, $default) {
    $name = $name.ToLowerInvariant()
    if ($null -eq $scoopConfig.$name -and $null -ne $default) {
        return $default
    }
    return $scoopConfig.$name
}

function Get-DefaultArchitecture {
    $arch = get_config DEFAULT_ARCHITECTURE
    $system = if (${env:ProgramFiles(Arm)}) {
        'arm64'
    }
    elseif ([System.Environment]::Is64BitOperatingSystem) {
        '64bit'
    }
    else {
        '32bit'
    }
    if ($null -eq $arch) {
        $arch = $system
    }
    else {
        try {
            $arch = Format-ArchitectureString $arch
        }
        catch {
            warn 'Invalid default architecture configured. Determining default system architecture'
            $arch = $system
        }
    }
    return $arch
}
function Get-AbsolutePath {
    <#
    .SYNOPSIS
        Get absolute path
    .DESCRIPTION
        Get absolute path, even if not existed
    .PARAMETER Path
        Path to manipulate
    .OUTPUTS
        System.String
            Absolute path, may or maynot existed
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $Path
    )
    process {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }
}
function cache_path($app, $version, $url) {
    $cachedir = $env:SCOOP_CACHE, (get_config CACHE_PATH), "$scoopdir\cache" | Where-Object { $_ } | Select-Object -First 1 | Get-AbsolutePath

    $underscoredUrl = $url -replace '[^\w\.\-]+', '_'
    $filePath = Join-Path $cachedir "$app#$version#$underscoredUrl"

    # NOTE: Scoop cache files migration. Remove this 6 months after the feature ships.
    if (Test-Path $filePath) {
        return $filePath
    }

    $urlStream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($url))
    $sha = (Get-FileHash -Algorithm SHA256 -InputStream $urlStream).Hash.ToLower().Substring(0, 7)
    $extension = [System.IO.Path]::GetExtension($url)
    $filePath = $filePath -replace "$underscoredUrl", "$sha$extension"

    return $filePath
}

function arch_specific($prop, $manifest, $architecture) {
    if ($manifest.architecture) {
        $val = $manifest.architecture.$architecture.$prop
        if ($val) { return $val } # else fallback to generic prop
    }

    if ($manifest.$prop) { return $manifest.$prop }
}
function url($manifest, $arch) { arch_specific 'url' $manifest $arch }



# ----------------从scoop复制代码 结束------------------------------------------------


# 将 file:// 格式的 URI 转换为本地文件路径
function UriToFilePath($Uri, $BaseDir) {

    # 检查是否为 file:// 协议
    if ($Uri -notmatch '^file://') {
        return $null
    }

    # 移除 file:// 前缀
    $path = $Uri -replace '^file://', ''
    # 移除可能存在的前导斜杠（Unix 风格路径）
    if ($path -match '^/') { $path = $path -replace '^/', '' }

    # 解码 URL 编码的字符（如 %20 转换为空格）
    $path = [System.Uri]::UnescapeDataString($path)
    # 移除 fragment（# 后面的部分）
    $path = $path.Split('#')[0]

    # 判断是否为绝对路径（Windows 盘符如 C: 或 Unix 绝对路径 /）
    $isAbsolute = $path -match '^[A-Za-z]:' -or $path -match '^\\'

    # Windows 路径处理：/C:/ -> C:
    if ($IsWindows -or (-not (Test-Path variable:IsWindows))) {
        if ($path -match '^/[A-Za-z]:') {
            $path = $path.Substring(1)
            $isAbsolute = $true
        }
    }

    # 如果提供了 BaseDir 且路径是相对路径，则拼接或解析
    if ($BaseDir -and -not $isAbsolute) {
        if ($path -match '^\.\.?[/\\]') {
            # 相对路径以 . 或 .. 开头，解析为绝对路径
            return [System.IO.Path]::GetFullPath((Join-Path $BaseDir $path))
        }
        # 普通相对路径，直接拼接
        $path = Join-Path $BaseDir $path
    }

    # 统一路径分隔符为 Windows 反斜杠
    $path = $path.Replace('/', '\')

    return $path
}

function ParseJson($path) {
    # 检查文件是否存在
    if (-not (Test-Path $path)) {
        Write-Error "文件未找到: $Path"
        return $null
    }
    
    try {
        # 读取文件内容并转换为 JSON 对象
        Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Error "JSON 解析失败: $_"
        return $null
    }
}

function Main($ManifestFile){

    # 检查清单文件是否存在
    if (-not (Test-Path $ManifestFile)) {
        throw "清单文件未找到: $ManifestFile"
    }

    # 转换为绝对路径
    $ManifestFile = Convert-Path -Path $ManifestFile

    # 获取清单文件所在文件夹
    $manifest_dir = Split-Path -Parent $ManifestFile

    # 解析 JSON 内容
    $manifest = ParseJson -Path $ManifestFile

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
        $local_file = UriToFilePath $url $manifest_dir

        # 判断是否解析成功
        if(-not $local_file){
            Write-Host "[scoopi]url解析失败： $url"
            Write-Host "[scoopi]请手动下载到缓存文件： $cache_file"
            Write-Host ""
            continue
        }
        
        Write-Host "[scoopi]url解析成功: $url -> $local_file"

        if(Test-Path $cache_file){
            Write-Host "[scoopi]缓存文件已存在: $cache_file"
            Write-Host ""
            continue
        }

        Write-Host "[scoopi]缓存文件不存在: $cache_file"

        if(-not (Test-Path $local_file)){
            Write-Host "[scoopi]url对应本地文件不存在: $local_file"
        }else{
            Write-Host "[scoopi]复制到缓存: $local_file -> $cache_file"
            Copy-Item -Path $local_file -Destination $cache_file -Force
        }
        Write-Host ""
    }

    & scoop install -u $ManifestFile
}

Main $ManifestFile

