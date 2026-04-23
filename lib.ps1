# 将 file:// 格式的 URI 转换为本地文件路径
# 参数:
#   -Uri: 文件 URI 字符串，支持 file:// 协议
#   -BaseDir: 可选的父目录，用于解析相对路径
# 返回:
#   转换后的本地路径，格式错误返回 null
function UriToFilePath {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        # 父目录，用于解析相对路径
        [string]$BaseDir
    )

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

function Parse-Json($path) {
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