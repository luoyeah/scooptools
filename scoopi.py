#!/usr/bin/env python3
"""
Scoop 安装预处理脚本 - 复制安装包到缓存目录。

功能：
    1. 读取 Scoop 清单文件 (.json)
    2. 将 file:// URL 转换为本地文件路径
    3. 复制文件到 Scoop 缓存目录
    4. 可选执行 Scoop install 安装

用法：
    python scoopi.py install -f <manifest.json>
    python scoopi.py test -f <manifest.json>
    python scoopi.py copy -f <manifest.json>
"""

import hashlib
import json
import os
import re
import shutil
import sys
import urllib.parse
from pathlib import Path

import typer
from typer import Option

# Typer 应用实例
app = typer.Typer(help="Scoop 安装预处理工具")

# 全局 Scoop 配置
scoop_config = {}


def load_scoop_config():
    """
    加载 Scoop 配置文件 config.json。

    读取位置：$XDG_CONFIG_HOME/scoop/config.json 或 ~/.config/scoop/config.json
    读取失败时返回空字典，不影响程序运行。
    """
    config_home = os.environ.get('XDG_CONFIG_HOME') or os.path.join(os.path.expanduser('~'), '.config')
    config_file = os.path.join(config_home, 'scoop', 'config.json')

    if not os.path.exists(config_file):
        return {}

    try:
        with open(config_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        typer.echo(f"ERROR loading {config_file}: {e}", err=True)
        return {}


def get_config(name, default=None):
    """
    获取 Scoop 配置项。

    参数:
        name: 配置项名称（不区分大小写）
        default: 默认值，当配置项不存在时返回

    返回:
        配置值或默认值
    """
    name_lower = name.lower()
    if name_lower in scoop_config:
        return scoop_config[name_lower]
    return default


def get_default_architecture():
    """
    获取系统默认 CPU 架构。

    优先级：
        1. Scoop 配置中的 DEFAULT_ARCHITECTURE
        2. 自动检测系统架构（ARM64 / 64bit / 32bit）

    返回:
        架构字符串：arm64 / 64bit / 32bit
    """
    arch = get_config('DEFAULT_ARCHITECTURE')

    import platform
    system = platform.machine()

    if system == 'ARM64' or os.environ.get('ProgramFiles(Arm)'):
        arch = arch or 'arm64'
    elif platform.machine() in ('x86_64', 'AMD64'):
        arch = arch or '64bit'
    else:
        arch = arch or '32bit'

    return arch


def get_absolute_path(path):
    """
    获取绝对路径。

    参数:
        path: 任意路径（可不存在）

    返回:
        绝对路径字符串
    """
    return str(Path(path).resolve())


def cache_path(app_name, version, url, scoop_dir=None):
    """
    生成 Scoop 缓存文件路径。

    缓存目录优先级：
        1. 环境变量 SCOOP_CACHE
        2. Scoop 配置 CACHE_PATH
        3. SCOOP_DIR/cache

    文件名格式：{app}#{version}#{url_hash}

    参数:
        app_name: 应用名称
        version: 版本号
        url: 原始下载 URL（字符串）
        scoop_dir: Scoop 根目录（备用）

    返回:
        缓存文件完整路径
    """
    cachedir = os.environ.get('SCOOP_CACHE')
    if not cachedir:
        cachedir = get_config('CACHE_PATH')
    if not cachedir:
        cachedir = os.path.join(scoop_dir, 'cache') if scoop_dir else None

    if not cachedir:
        raise ValueError("Cannot determine cache directory. Set SCOOP_CACHE env var.")

    cachedir = get_absolute_path(cachedir)
    os.makedirs(cachedir, exist_ok=True)

    # 将 URL 转换为合法的文件名
    underscored_url = urllib.parse.quote(url, safe='_.-')
    underscored_url = underscored_url.replace('%', '_')

    file_path = os.path.join(cachedir, f"{app_name}#{version}#{underscored_url}")

    # 如果已存在直接返回
    if os.path.exists(file_path):
        return file_path

    # 使用 URL 的 SHA256 哈希作为备用文件名
    url_bytes = url.encode('utf-8')
    sha = hashlib.sha256(url_bytes).hexdigest()[:7]
    extension = Path(url).suffix
    file_path = file_path.replace(underscored_url, f"{sha}{extension}")

    return file_path


def cache_paths(app_name, version, urls, scoop_dir=None):
    """
    为多个 URL 生成缓存文件路径列表。

    参数:
        app_name: 应用名称
        version: 版本号
        urls: URL 字符串列表
        scoop_dir: Scoop 根目录（备用）

    返回:
        缓存文件路径列表
    """
    return [cache_path(app_name, version, u, scoop_dir) for u in urls]


def arch_specific(prop, manifest, architecture):
    """
    获取清单中特定架构的属性值。

    优先级：
        1. architecture.{architecture}.{prop}
        2. {prop}

    支持返回单个值或数组。

    参数:
        prop: 属性名（如 url、filename）
        manifest: 清单字典对象
        architecture: 目标架构

    返回:
        属性值（单个字符串或字符串数组），不存在返回 None
    """
    if manifest.get('architecture'):
        val = manifest['architecture'].get(architecture, {}).get(prop)
        if val is not None:
            return val if isinstance(val, list) else [val]

    val = manifest.get(prop)
    if val is not None:
        return val if isinstance(val, list) else [val]

    return []


def get_url(manifest, architecture):
    """
    从清单中获取下载 URL 列表。

    参数:
        manifest: 清单字典对象
        architecture: 目标架构

    返回:
        URL 字符串列表
    """
    return arch_specific('url', manifest, architecture)


def uri_to_file_path(uri, base_dir=None):
    """
    将 file:// URI 转换为本地文件路径。

    支持的格式：
        - file://C:/path/to/file.exe
        - file:///path/to/file.exe
        - file://./relative/path.exe
        - file://../parent/path.exe

    参数:
        uri: file:// 格式的 URI
        base_dir: 基础目录，用于解析相对路径

    返回:
        本地文件路径，解析失败返回 None
    """
    parsed = urllib.parse.urlparse(uri)

    if parsed.scheme != 'file':
        return None

    # 处理 netloc 为驱动器盘符的情况（如 file://C:/path/file.exe）
    # netloc 包含冒号时表示驱动器，如 "C:"
    if parsed.netloc and ':' in parsed.netloc:
        path_part = parsed.path or ''
        if path_part.startswith('/'):
            path_part = path_part[1:]
        path = f"{parsed.netloc}:{path_part}"
    else:
        path = parsed.path or ''

    # 移除前导斜杠（Unix 风格）
    if path.startswith('/'):
        path = path[1:]

    # URL 解码（如 %20 转换为空格）
    path = urllib.parse.unquote(path)

    # 检查是否为绝对路径（Windows 盘符）
    is_absolute = re.match(r'^[A-Za-z]:', path) or path.startswith('\\\\')

    # 处理 /C:/path 格式（转换为 C:/path）
    if re.match(r'^/[A-Za-z]:', path):
        path = path[1:]
        is_absolute = True

    # 相对路径处理
    if base_dir and not is_absolute:
        if re.match(r'^\.\.?[/\\]', path):
            # ./ 或 ../ 开头，解析为绝对路径
            path = os.path.abspath(os.path.join(base_dir, path))
        else:
            path = os.path.join(base_dir, path)

    # 统一路径分隔符为反斜杠（Windows）
    path = path.replace('/', '\\')

    return path


def parse_json(path):
    """
    解析 JSON 清单文件。

    参数:
        path: JSON 文件路径

    返回:
        解析后的字典对象，失败返回 None
    """
    if not os.path.exists(path):
        typer.echo(f"File not found: {path}", err=True)
        return None

    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        typer.echo(f"JSON parse failed: {e}", err=True)
        return None


def process_manifest(manifest_file):
    """
    处理清单文件，解析 URL 和路径。

    参数:
        manifest_file: 清单文件路径

    返回:
        包含以下键的字典：
        - manifest_file: 清单文件绝对路径
        - app_name: 应用名称（文件名不含扩展名）
        - version: 版本号
        - urls: URL 列表
        - cache_files: 缓存文件路径列表
        - local_files: 本地文件路径列表
    """
    if not os.path.exists(manifest_file):
        raise FileNotFoundError(f"Manifest file not found: {manifest_file}")

    manifest_file = os.path.abspath(manifest_file)
    manifest_dir = os.path.dirname(manifest_file)

    manifest = parse_json(manifest_file)

    if manifest is None:
        raise ValueError("Manifest parse failed")

    app_name = Path(manifest_file).stem
    version = manifest.get('version', '0')

    architecture = get_default_architecture()
    urls = get_url(manifest, architecture)

    cache_files = cache_paths(app_name, version, urls)
    local_files = [uri_to_file_path(url, manifest_dir) for url in urls]

    return {
        'manifest_file': manifest_file,
        'app_name': app_name,
        'version': version,
        'urls': urls,
        'cache_files': cache_files,
        'local_files': local_files,
    }


def copy_to_cache(local_file, cache_file):
    """
    复制文件到 Scoop 缓存目录。

    参数:
        local_file: 源文件路径
        cache_file: 目标缓存路径

    返回:
        复制成功返回 True，源文件不存在返回 False
    """
    if not os.path.exists(local_file):
        return False

    os.makedirs(os.path.dirname(cache_file), exist_ok=True)
    shutil.copy2(local_file, cache_file)
    return True


@app.command()
def install(
    file: str = Option(..., "--file", "-f", help="清单文件路径 (.json)", rich_help_panel="必需参数"),
    force: bool = Option(False, "--force", help="强制重新安装"),
):
    """
    复制安装包到缓存并执行 Scoop 安装。

    执行流程：
        1. 解析清单文件
        2. 复制本地文件到缓存（如需要）
        3. 执行 scoop install 命令
    """
    import subprocess

    result = process_manifest(file)

    for i, url in enumerate(result['urls']):
        local_file = result['local_files'][i]
        cache_file = result['cache_files'][i]
        local_exists = os.path.exists(local_file)
        typer.echo(f"[scoopi] URL: {url} -> [{'+' if local_exists else '-'}]" + local_file)

        cache_exists = os.path.exists(cache_file)
        if cache_exists:
            typer.echo(f"[scoopi] Cache exists: {cache_file}")
        else:
            typer.echo(f"[scoopi] Cache: {cache_file}")
            if local_exists:
                copy_to_cache(local_file, cache_file)
                typer.echo(f"[scoopi] Copied to cache")

    cmd = ['scoop', 'install']
    if force:
        cmd.append('-f')
    cmd.append(file)

    typer.echo(f"[scoopi] Running: {' '.join(cmd)}")
    subprocess.run(cmd)


@app.command()
def test(
    file: str = Option(..., "--file", "-f", help="清单文件路径 (.json)", rich_help_panel="必需参数"),
):
    """
    测试清单解析（dry run 模式）。

    仅解析并显示信息，不执行实际复制或安装。
    用于验证清单文件和路径解析是否正确。
    """
    result = process_manifest(file)

    for i, url in enumerate(result['urls']):
        local_file = result['local_files'][i]
        cache_file = result['cache_files'][i]
        local_exists = os.path.exists(local_file)
        typer.echo(f"[scoopi] URL: {url}")
        typer.echo(f"[scoopi] Local file: [{'+' if local_exists else '-'}]" + local_file)
        typer.echo(f"[scoopi] Cache file: {cache_file}")

    typer.echo(f"[scoopi] App: {result['app_name']} v{result['version']}")


@app.command()
def copy(
    file: str = Option(..., "--file", "-f", help="清单文件路径 (.json)", rich_help_panel="必需参数"),
    force: bool = Option(False, "--force", "-w", help="覆盖已存在的缓存文件"),
):
    """
    仅复制安装包到缓存目录。

    不执行 Scoop 安装，仅将本地文件复制到缓存。
    适用于提前缓存安装包或手动处理特殊情况。
    """
    result = process_manifest(file)

    for i, url in enumerate(result['urls']):
        local_file = result['local_files'][i]
        cache_file = result['cache_files'][i]
        local_exists = os.path.exists(local_file)

        if not local_file:
            typer.echo(f"[scoopi] URL parse failed: {url}", err=True)
            raise typer.Exit(1)

        typer.echo(f"[scoopi] URL: {url} -> [{'+' if local_exists else '-'}]" + local_file)

        if os.path.exists(cache_file):
            if force:
                typer.echo(f"[scoopi] Overwriting cache: {cache_file}")
            else:
                typer.echo(f"[scoopi] Cache exists: {cache_file} (use --force to overwrite)")
                raise typer.Exit()

        if not local_exists:
            typer.echo(f"[scoopi] Local file not found: {local_file}", err=True)
            raise typer.Exit(1)

        copy_to_cache(local_file, cache_file)
        typer.echo(f"[scoopi] Copied: {local_file} -> {cache_file}")


if __name__ == '__main__':
    # 启动前加载 Scoop 配置
    scoop_config = load_scoop_config()
    app()