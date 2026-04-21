# scooptools
* scoop 增强工具箱

## 1 工具列表

* scoopi - 修复清单文件相对路径再安装
* scoopb - 备份scoop

## 2 其他：安装scoop
* 打开powershell 执行以下内容：
```powershell

# 1 设置安装位置、app缓存位置
$env:SCOOP='D:\Scoop'
$env:SCOOP_CACHE='D:\Scoop\scoopcache'
$env:SCOOP_GLOBAL='D:\ScoopGlobal'

# 永久设置
[Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')
[Environment]::SetEnvironmentVariable('SCOOP_CACHE', $env:SCOOP_CACHE, 'User')
[Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', $env:SCOOP_GLOBAL, 'User')

# 2 设置代理（加速安装)
[net.webrequest]::defaultwebproxy = new-object net.webproxy "http://127.0.0.1:7897"

# 3 安装scoop
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

# 4 设置scoop 下载app的代理
scoop config proxy 127.0.0.1:7897
# 移除代理
# scoop config rm proxy
```
  

