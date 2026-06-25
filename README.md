# Socat 端口转发管理脚本

## 简介

一个功能完善的 Socat 一键安装管理脚本，支持多种协议的端口转发配置，提供开机自启、域名监控（DDNS）、网络加速（BBR）等功能。

**版本**: 5.2
**系统要求**: CentOS 7+、Debian 8+、Ubuntu 16+、Arch Linux

## 功能特性

### 支持的转发协议

| 协议 | 说明 | 防火墙配置 | 域名监控 | 典型场景 |
|------|------|------------|----------|----------|
| **TCP** | 标准TCP转发 | TCP | 支持 | 通用端口转发、HTTP/HTTPS、SSH |
| **UDP** | UDP转发 | UDP | 不支持 | DNS、游戏服务器、视频流 |
| **SCTP** | 流控制传输协议 | SCTP | 支持 | 电话信令、高可靠消息传输 |
| **SSL/TLS** | 加密TCP转发 | TCP | 支持 | HTTPS代理、数据加密传输 |
| **UNIX** | 本地套接字转发 | 不需要 | 不适用 | 容器/数据库socket通信 |
| **SOCKS4A** | SOCKS代理转发 | TCP | 不支持 | 穿透防火墙、代理上网 |
| **HTTP PROXY** | HTTP CONNECT代理 | TCP | 不支持 | 企业网络代理、HTTP/HTTPS代理 |

### 核心功能

- **多协议支持**: 支持 TCP、UDP、SCTP、SSL/TLS、UNIX 套接字、SOCKS4A、HTTP PROXY
- **IPv4/IPv6**: 支持纯 IPv4、纯 IPv6、IPv4 域名、IPv6 域名四种地址类型
- **开机自启**: 通过 systemd 服务实现开机自动恢复转发配置
- **域名监控**: 支持 DDNS 域名监控，IP 变更自动重启服务
- **网络加速**: 支持 BBR 拥塞控制算法，提升传输性能
- **防火墙配置**: 自动配置 firewalld/ufw/iptables 防火墙规则
- **配置持久化**: JSON 格式配置文件，支持导出导入
- **多发行版支持**: 兼容 CentOS、Debian、Ubuntu、Arch 等主流 Linux 发行版

## 安装

```bash
# 下载脚本
curl -sL https://raw.githubusercontent.com/baichal/Socat/refs/heads/main/socat.sh

# 添加执行权限
chmod +x socat.sh

# 运行脚本（需要 root 权限）
sudo ./socat.sh
```

## 使用指南

### 首次运行

首次运行脚本时，程序会自动检测并安装必要的依赖（socat、jq、openssl），然后进入交互式菜单。

### 主菜单功能

```
========================================
    Socat 端口转发一键管理脚本
========================================
    
    1. 添加端口转发
    2. 查看转发列表
    3. 删除转发规则
    4. 开启网络加速
    5. 关闭网络加速
    6. 查看加速状态
    7. 切换 IPv4/IPv6 监控
    8. 修改域名监控间隔
    9. 恢复转发规则
   10. 卸载 Socat
   11. 退出

========================================
请输入选项数字: 
```

### 添加转发配置

#### 1. 选择协议类型

脚本提供 8 种协议选项：

```
请选择转发协议：
1. TCP + UDP（默认）- 同时支持 TCP 和 UDP 流量
2. 仅 TCP - 仅转发 TCP 流量
3. 仅 UDP - 仅转发 UDP 流量
4. SCTP - 流控制传输协议
5. SSL/TLS 加密转发 - 数据全程加密
6. UNIX 域套接字 - TCP 与本地 socket 互转
7. SOCKS4A 代理转发 - 通过 SOCKS 代理
8. HTTP PROXY 代理转发 - 通过 HTTP 代理
```

#### 2. 选择地址类型

```
请选择 IP 版本：
1. IPv4（默认）
2. IPv6
3. IPv4 域名（DDNS）
4. IPv6 域名（DDNS）
```

#### 3. 输入转发信息

根据选择的协议和地址类型，输入相应信息：

- **本地端口**: 监听端口（1-65535）
- **远程端口**: 目标端口
- **远程地址**: 目标 IP 或域名

#### 4. 配置示例

**示例 1: TCP 端口转发**
```
协议: TCP + UDP
地址类型: IPv4
本地端口: 8080
远程端口: 80
远程地址: 192.168.1.100
```
将本机 8080 端口的流量转发到 192.168.1.100:80

**示例 2: SSL/TLS 加密转发**
```
协议: SSL/TLS 加密转发
地址类型: IPv4 域名
本地端口: 443
远程端口: 80
远程地址: example.com
```
将本机 443 端口的加密流量转发到 example.com:80

**示例 3: UNIX 套接字转发**
```
协议: UNIX 域套接字
方向: TCP端口 -> UNIX套接字
套接字路径: /var/run/mysql/mysql.sock
本地端口: 3306
```
将本机 3306 端口转发到 MySQL UNIX 套接字

### 查看转发列表

运行后显示当前所有转发配置：

```
当前转发列表:
1. IPv4: 0.0.0.0:8080 --> 192.168.1.100:80 (TCP/UDP)
2. IPv4 域名: 0.0.0.0:443 --> example.com:80 (OPENSSL) [DDNS, IPv4]
3. IPv6: [::]:8080 --> [2001:db8::1]:80 (TCP)
```

### 删除转发

选择要删除的转发编号，脚本会：
1. 停止对应的 systemd 服务
2. 删除服务文件
3. 移除防火墙规则（如有）
4. 从配置文件删除记录

### 网络加速（BBR）

BBR（Bottleneck Bandwidth and RTT）是一种 TCP 拥塞控制算法，可显著提升网络传输速度。

**开启加速**:
```
选择功能: 4. 开启网络加速

正在优化网络参数...
已开启 BBR 加速
```

**查看状态**:
```
选择功能: 6. 查看加速状态

当前加速状态: 已开启
算法: bbr
```

### 域名监控（DDNS）

当使用域名作为远程地址时，脚本会每 5 分钟自动检查域名 IP 是否变更。

**修改监控间隔**:
```
选择功能: 8. 修改域名监控间隔

当前监控间隔: 5 分钟
请输入新的监控间隔（分钟）: 10
已更新监控间隔为 10 分钟
```

## 配置文件

### 配置文件位置

- **主配置**: `/etc/socats/config.json`
- **JSON 格式化开关**: `/etc/socats/.json_format`
- **SSL 证书**: `/etc/socats/ssl/server.crt` 和 `server.key`
- **域名缓存**: `/etc/socats/dns_cache_*.txt`
- **监控脚本**: `/etc/socats/monitor_*.sh`

### 配置格式

```json
[
  {
    "type": "ipv4",
    "listen_port": 8080,
    "remote_ip": "192.168.1.100",
    "remote_port": 80,
    "protocols": ["tcp", "udp"],
    "extra": "null"
  },
  {
    "type": "domain",
    "listen_port": 443,
    "remote_ip": "example.com",
    "remote_port": 80,
    "protocols": ["openssl"],
    "extra": "null"
  },
  {
    "type": "ipv4",
    "listen_port": 3306,
    "remote_ip": "127.0.0.1",
    "remote_port": 0,
    "protocols": ["unix"],
    "extra": "tcp2unix:/var/run/mysql/mysql.sock"
  }
]
```

### 字段说明

| 字段 | 说明 |
|------|------|
| `type` | 地址类型：`ipv4`、`ipv6`、`domain`、`domain6` |
| `listen_port` | 本地监听端口，UNIX→TCP 模式为 0 |
| `remote_ip` | 远程 IP 或域名，UNIX→TCP 模式为 `127.0.0.1` |
| `remote_port` | 远程端口，TCP→UNIX 模式为 0 |
| `protocols` | 协议列表：`tcp`、`udp`、`sctp`、`openssl`、`unix`、`socks`、`proxy` |
| `extra` | 额外参数，UNIX 路径或代理地址 |

## 服务管理

### 查看服务状态

```bash
# 查看所有 Socat 服务
systemctl list-units 'socat-*' --type=service

# 查看单个服务状态
systemctl status socat-8080-80-tcp
```

### 手动管理服务

```bash
# 停止服务
sudo systemctl stop socat-8080-80-tcp

# 启动服务
sudo systemctl start socat-8080-80-tcp

# 重启服务
sudo systemctl restart socat-8080-80-tcp

# 查看日志
sudo journalctl -u socat-8080-80-tcp -f
```

### 服务命名规则

| 协议类型 | 服务名格式 |
|----------|------------|
| TCP/UDP/SCTP/SSL | `socat-<监听端口>-<目标端口>-<协议>` |
| UNIX→TCP | `socat-unix-<socket名>-<目标端口>-unix` |
| TCP→UNIX | `socat-<监听端口>-unix-<socket名>-unix` |

## 防火墙配置

脚本会自动检测并配置防火墙：

### firewalld (CentOS 7+)

```bash
# 查看开放的端口
sudo firewall-cmd --list-ports

# 手动添加端口
sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --reload
```

### ufw (Ubuntu/Debian)

```bash
# 查看状态
sudo ufw status

# 手动添加规则
sudo ufw allow 8080/tcp
```

### iptables

```bash
# 查看规则
sudo iptables -L -n

# 手动添加规则
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
```

## 故障排查

### 服务启动失败

```bash
# 查看详细错误
sudo journalctl -u socat-端口1-端口2-协议 -xe

# 常见错误
# - 端口已被占用: 更换端口或停止占用进程
# - 权限不足: 以 root 运行
# - socat 未安装: 重新运行安装脚本
```

### 端口无法访问

```bash
# 检查防火墙
sudo firewall-cmd --list-ports
sudo iptables -L -n | grep 端口

# 检查服务状态
sudo systemctl status socat-端口1-端口2-协议

# 检查端口监听
sudo ss -tlnp | grep 端口
sudo netstat -tlnp | grep 端口
```

### 域名监控不生效

```bash
# 检查监控服务
sudo systemctl status socat-domain-monitor

# 查看监控日志
sudo cat /etc/socats/dns_monitor.log

# 检查域名解析
nslookup your-domain.com
dig your-domain.com
```

### 转发连接不稳定

```bash
# 开启 BBR 加速
sudo ./socat.sh
# 选择 4. 开启网络加速

# 检查系统参数
sysctl net.ipv4.tcp_congestion_control
# 应显示: net.ipv4.tcp_congestion_control = bbr
```

## 卸载

```bash
# 运行卸载
sudo ./socat.sh
# 选择 10. 卸载 Socat

# 或强制卸载
sudo killall socat
sudo rm -rf /etc/socats
sudo rm -f /etc/systemd/system/socat-*.service
sudo systemctl daemon-reload
```

## 常见问题

### Q: 如何同时转发多个端口？

A: 多次运行添加转发功能，或手动创建多个 systemd 服务。

### Q: 支持端口范围转发吗？

A: Socat 支持端口范围，需要手动创建服务，脚本暂不支持。

### Q: 如何实现 TCP/UDP 端口复用？

A: 脚本使用独立的 TCP 和 UDP 服务，如需端口复用可手动修改配置。

### Q: SSL 证书如何实现双向认证？

A: 当前脚本使用自签名证书，如需双向认证请手动配置证书。

### Q: 如何限制转发带宽？

A: 可通过 iptables 或 tc 命令限制带宽，脚本暂不内置此功能。

## 许可证

MIT License

## 更新日志

### v5.2
- 新增 UNIX 套接字转发支持（TCP↔UNIX 双向）
- 新增 SOCKS4A 和 HTTP PROXY 代理转发
- 新增 SCTP 协议支持
- 优化域名监控服务，支持多协议重启
- 修复配置文件 JSON 解析问题
- 提升防火墙配置兼容性
