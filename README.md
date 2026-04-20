# mybucket
* scoop 安装方法、添加自定义bucket和常用软件安装
## 0 常用软件下载站点
### 直链下载站
* [当下软件园](https://www.downxia.com/)
* [绿色资源网](http://www.downcc.com/)

### 非直链下载站
* [脚本之家](https://www.jb51.net/softs/)
* [果核剥壳](https://www.ghxi.com/)
* [大眼仔](https://www.dayanzai.me/)
* [华军软件园](https://www.onlinedown.net/)

## 1 安装scoop
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

## 2 添加 bucket
```powershell
# 安装git
scoop install git
# 将ssh公钥添加到 gitee.com ,使用 ssh-keygen 生成的密钥
# ssh-keygen

# 添加extras
scoop bucket add extras
scoop bucket add versions
```

## 3 添加常用软件

```powershell
# 开发常用
scoop install 7zip git gnupg vscode python38
scoop install windows-terminal exiftool mingw apifox nodejs pnpm


# 办公常用
scoop install googlechrome imageglass keepassxc onecommander notepadplusplus 

scoop install everything wiztree openark clash-verge-rev

scoop install localsend syncthing telegram vlc ventoy

scoop install extras/bulk-crap-uninstaller fastcopy

```


## 4 自定义命令

* scoopb - 备份scoop
* scoopr - 还原scoop
* scoopi - 修复清单文件相对路径再安装
  

