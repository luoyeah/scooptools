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