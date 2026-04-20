param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$ManifesFile
)

# 解析json
function parse_json($path) {
    if ($null -eq $path -or !(Test-Path $path)) { 
        return $null 
    }
    try {
        Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "Error parsing JSON at '$path'."
    }
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
# 获取缓存路径
function get_cache_path($app, $version, $url) {
    # 缓存文件夹
    $cachedir = $env:SCOOP_CACHE, "$scoopdir\cache" | Where-Object { $_ } | Select-Object -First 1 | Get-AbsolutePath

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
function parse_manifest($InputFile){
    $InputFile =  Convert-Path -Path $InputFile
    # 获取输入文件的目录路径作为基准路径
    $basePath = Split-Path $InputFile -Parent

    # 使用parse_json函数解析JSON
    $jsonObject = parse_json $InputFile
    
    if ($null -eq $jsonObject) {
        Write-Error "无法解析JSON文件: $InputFile"
        exit 1
    }
    
    # 检查是否有url字段
    if (-not $jsonObject.PSObject.Properties['url']) {
        Write-Output "JSON文件中没有找到'url'字段，无需处理。"
        
        # 直接返回原始
        return $InputFile
    }
    
    # 处理URL字段
    $urlValue = $jsonObject.url
    
    if ([string]::IsNullOrEmpty($urlValue)) {
        Write-Verbose "URL字段为空，无需处理" -Verbose
        return $InputFile
    }

    # 检查是否为相对路径（不是绝对路径且不是URL）
    if ([System.IO.Path]::IsPathRooted($urlValue) -or
        $urlValue.StartsWith("http://") -or
        $urlValue.StartsWith("https://") -or
        $urlValue.StartsWith("ftp://") -or
        $urlValue.StartsWith("file://")) {
			
		Write-Verbose "URL '$urlValue' 已经是绝对路径或完整URL，无需转换" -Verbose
        return $InputFile
	}    
	
	# 分离路径和片段（#后面的部分）
	$pathPart = $urlValue
	$fragmentPart = $null
	
	# 检查是否有片段（#后面的部分）
	if ($urlValue.Contains('#')) {
		$hashIndex = $urlValue.LastIndexOf('#')
		if ($hashIndex -ge 0) {
			$pathPart = $urlValue.Substring(0, $hashIndex)
			$fragmentPart = $urlValue.Substring($hashIndex)  # 包含#
		}
	}
	
	# 转换为绝对路径
	$absolutePath = Join-Path $basePath $pathPart
	$absolutePath = [System.IO.Path]::GetFullPath($absolutePath)

	if(!(Test-Path $absolutePath)){
		Write-Error "'url文件不存在：'$absolutePath"
		exit 1
	}

    $nofragmentPath = $absolutePath
	
	# 重新附加片段（如果有）
	if ($fragmentPart) {
		$absolutePath = $absolutePath + $fragmentPart
	}
	
	$jsonObject.url = "file:///" + $absolutePath
	
	Write-Verbose "已将URL从 '$urlValue' 转换为 '$absolutePath'" -Verbose

    ## 写入到临时文件
    # 创建临时文件夹
    $tempDir = [System.IO.Path]::GetTempPath()
    $tempSubDir = Join-Path $tempDir "scoop_manifest_temp"
    if (!(Test-Path $tempSubDir)) {
        New-Item -ItemType Directory -Path $tempSubDir -Force | Out-Null
    }
    
    # 获取原始文件名
    $originalFileName = [System.IO.Path]::GetFileName($InputFile)
    $outputFile = Join-Path $tempSubDir $originalFileName
    
    # 将修改后的JSON转换回字符串
    $modifiedJson = $jsonObject | ConvertTo-Json -Depth 20
    
    # 写入临时文件
    $modifiedJson | Out-File -FilePath $outputFile -Encoding UTF8 -Force
    
    Write-Host "处理成功！文件已保存到:" -ForegroundColor Green
    Write-Host $outputFile -ForegroundColor Cyan


    ## 复制到缓存(加快安装进度)
    # 获取app名称
    $app_name = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    
    # 获取目标缓存路径
    $cache_path = get_cache_path $app_name $jsonObject.version $jsonObject.url

    if(-not (Test-Path($cache_path))){
        Copy-Item -Path $nofragmentPath -Destination $cache_path
        Write-Host "已复制到缓存:" -ForegroundColor Green
        Write-Host "$nofragmentPath -> $cache_path" -ForegroundColor Cyan
    }
    
    # 返回输出文件路径
    $outputFile
}

$manifest_file = parse_manifest $ManifesFile

# 安装
& scoop install -u $manifest_file

# Remove-Item -Path $manifest_file