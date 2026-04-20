
# scoop 安装目录
$scoop_path = $env:SCOOP

# 判断是否存在
if (!$scoop_path) {
    Write-Host "Scoop not installed."
    exit 1
}

# 保存当前工作目录
$current_dir = Get-Location

# 备份文件
$current_date = Get-Date -Format "yyyy-MM-dd"
$backup_file = "$current_dir/backup_scoop_$current_date.7z"


if (Test-Path $backup_file) {
    Write-Host "Backup file already exists."
    # remove-item $backup_file
    exit 1
}


Set-Location $scoop_path

# 备份scoop主程序
7z a -t7z -mmt8 -mx1 "$backup_file" "apps/scoop/current" '-xr!.git' '-xr!*.vscode' '-xr!*.github'
7z u -mmt8 -mx1 "$backup_file" "shims/scoop.ps1" "shims/scoop.cmd" "shims/scoop"

# 备份main extras buckets
7z u -mmt8 -mx1 "$backup_file" "buckets/main" "buckets/extras" "buckets/versions" '-xr!.git' '-xr!*.vscode' '-xr!*.github'

# 备份mybucket
# 7z u -mmt8 -mx1 "$backup_file" "buckets/mybucket" '-xr!.git' '-xr!*.vscode' '-xr!*.github'



# 恢复工作目录
Set-Location $current_dir

# timeout.exe /t 60
