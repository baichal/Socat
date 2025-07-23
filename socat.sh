#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# ====================================================
#    系统要求: CentOS 7+、Debian 8+、Ubuntu 16+
#    描述: Socat 一键安装管理脚本
#    版本: 5.0
# ====================================================

Green="\033[32m"
Font="\033[0m"
Blue="\033[34m"
Red="\033[31m"
Yellow="\033[33m"

# 创建 socats 目录并定义相关路径
SOCATS_DIR="$HOME/socats"
mkdir -p "$SOCATS_DIR"

# 配置文件路径
CONFIG_FILE="$SOCATS_DIR/socat_forwards.conf"

# 清屏函数
clear_screen() {
    clear
}

# 按键继续函数
press_any_key() {
    echo
    read -n 1 -s -r -p "按任意键继续..."
    clear_screen
}

# 检查是否为root用户
check_root(){
    if [[ $EUID -ne 0 ]]; then
       echo "错误：此脚本必须以root身份运行！" 1>&2
       exit 1
    fi
}

# 检查系统类型
check_sys(){
    if [[ -f /etc/redhat-release ]]; then
        OS="CentOS"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        OS="Debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        OS="Ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        OS="CentOS"
    else
        echo "不支持的操作系统！"
        exit 1
    fi
}

# 获取本机IP（优化版本）
get_ip(){
    local ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -n1)
    echo ${ip:-"未知IPv4"}
}

# 获取IPv6地址
get_ipv6(){
    local ipv6=$(ip -6 addr show | grep -oP '(?<=inet6\s)[\da-f:]+' | grep -v '^::1' | grep -v '^fe80' | head -n1)
    echo ${ipv6:-"未知IPv6"}
}

# 安装Socat（只在需要时执行）
install_socat(){
    if [ ! -s /usr/bin/socat ]; then
        echo -e "${Green}正在安装 Socat...${Font}"
        if [ "${OS}" == "CentOS" ]; then
            yum install -y socat
        else
            apt-get -y update
            apt-get install -y socat
        fi
        if [ -s /usr/bin/socat ]; then
            echo -e "${Green}Socat 安装完成！${Font}"
        else
            echo -e "${Red}Socat 安装失败，请检查网络连接和系统设置。${Font}"
            exit 1
        fi
    fi
}

# 初始化配置文件
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
        echo "Debug: Created new config file: $CONFIG_FILE"
    else
        echo "Debug: Config file already exists: $CONFIG_FILE"
    fi
}

# 添加到配置文件
add_to_config() {
    if [ "$ip_version" == "1" ]; then
        echo "ipv4 $port1 $socatip $port2" >> "$CONFIG_FILE"
    elif [ "$ip_version" == "2" ]; then
        echo "ipv6 $port1 $socatip $port2" >> "$CONFIG_FILE"
    elif [ "$ip_version" == "3" ]; then
        echo "domain $port1 $socatip $port2" >> "$CONFIG_FILE"
    elif [ "$ip_version" == "4" ]; then
        echo "domain6 $port1 $socatip $port2" >> "$CONFIG_FILE"
    fi
}

# 从配置文件中移除转发
remove_from_config() {
    local listen_port=$1
    sed -i "/ $listen_port /d" "$CONFIG_FILE"
}

# 检测端口是否占用
check_port() {
    if netstat -tuln | grep -q ":$1 "; then
        echo -e "${Red}错误: 端口 $1 已被占用${Font}"
        return 1
    fi
    return 0
}

# 规范化 IPv6 地址
normalize_ipv6() {
    local ip=$1
    ip=$(echo $ip | tr '[:upper:]' '[:lower:]')
    ip=$(echo $ip | sed 's/\b0*\([0-9a-f]\)/\1/g')
    local longest_zero=""
    local current_zero=""
    local IFS=":"
    for group in $ip; do
        if [ "$group" = "0" ]; then
            current_zero="$current_zero:"
        else
            if [ ${#current_zero} -gt ${#longest_zero} ]; then
                longest_zero=$current_zero
            fi
            current_zero=""
        fi
    done
    if [ ${#current_zero} -gt ${#longest_zero} ]; then
        longest_zero=$current_zero
    fi
    if [ -n "$longest_zero" ]; then
        ip=$(echo $ip | sed "s/$longest_zero/::/")
        ip=$(echo $ip | sed 's/:::/::/')
    fi
    ip=$(echo $ip | sed 's/^://' | sed 's/:$//')
    echo $ip
}

# 检查是否支持IPv6
check_ipv6_support() {
    if [ ! -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
        echo -e "${Red}错误: 您的系统似乎不支持 IPv6${Font}"
        return 1
    fi

    if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" -eq 1 ]; then
        echo -e "${Yellow}警告: IPv6 当前被禁用${Font}"
        read -p "是否要启用 IPv6? (y/n): " enable_ipv6
        if [[ $enable_ipv6 =~ ^[Yy]$ ]]; then
            sysctl -w net.ipv6.conf.all.disable_ipv6=0
            echo -e "${Green}IPv6 已启用${Font}"
        else
            echo -e "${Red}IPv6 保持禁用状态，无法进行 IPv6 转发${Font}"
            return 1
        fi
    fi

    local ipv6_addr=$(ip -6 addr show | grep -oP '(?<=inet6 )([0-9a-fA-F:]+)' | grep -v '^::1' | grep -v '^fe80' | head -n 1)
    if [ -z "$ipv6_addr" ]; then
        echo -e "${Red}错误: 未检测到可用的 IPv6 地址${Font}"
        echo -e "${Yellow}请确保您的网络接口已配置 IPv6 地址${Font}"
        return 1
    else
        echo -e "${Green}检测到 IPv6 地址: $ipv6_addr${Font}"
    fi

    if [ "$(cat /proc/sys/net/ipv6/conf/all/forwarding)" -eq 0 ]; then
        echo -e "${Yellow}警告: IPv6 转发当前被禁用${Font}"
        read -p "是否要启用 IPv6 转发? (y/n): " enable_forwarding
        if [[ $enable_forwarding =~ ^[Yy]$ ]]; then
            sysctl -w net.ipv6.conf.all.forwarding=1
            echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
            echo -e "${Green}IPv6 转发已启用${Font}"
        else
            echo -e "${Red}IPv6 转发保持禁用状态，可能影响转发功能${Font}"
            return 1
        fi
    fi

    return 0
}

# 配置Socat
config_socat(){
    echo -e "${Green}请选择转发类型：${Font}"
    echo "1. IPv4 端口转发"
    echo "2. IPv6 端口转发"
    echo "3. IPv4 域名(DDNS)端口转发"
    echo "4. IPv6 域名(DDNS)端口转发"
    read -p "请输入选项 [1-4]: " ip_version

    if [ "$ip_version" == "2" ] || [ "$ip_version" == "4" ]; then
        if ! check_ipv6_support; then
            echo -e "${Red}无法进行 IPv6 转发，请检查系统配置${Font}"
            return 1
        fi
    fi

    echo -e "${Green}请输入Socat配置信息！${Font}"
    while true; do
        read -p "请输入本地端口: " port1
        if check_port $port1; then
            break
        fi
    done
    read -p "请输入远程端口: " port2
    
    if [ "$ip_version" == "3" ] || [ "$ip_version" == "4" ]; then
        read -p "请输入远程域名: " socatip
        if ! is_valid_domain "$socatip"; then
            echo -e "${Red}错误: 无效的域名格式${Font}"
            return 1
        fi
    else
        read -p "请输入远程IP: " socatip

        if [ "$ip_version" == "1" ]; then
            if ! [[ $socatip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo -e "${Red}错误: 无效的IPv4地址格式${Font}"
                return 1
            fi
        elif [ "$ip_version" == "2" ]; then
            if ! [[ $socatip =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
                echo -e "${Red}错误: 无效的IPv6地址格式${Font}"
                return 1
            fi
            socatip=$(normalize_ipv6 "$socatip")
        fi
    fi
}

# 验证域名格式
is_valid_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        # 尝试解析域名
        if host "$domain" >/dev/null 2>&1 || nslookup "$domain" >/dev/null 2>&1 || dig "$domain" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# 创建 systemd 服务文件
create_systemd_service() {
    local name=$1
    local command=$2
    cat > /etc/systemd/system/${name}.service <<EOF
[Unit]
Description=Socat Forwarding Service
After=network.target

[Service]
Type=simple
ExecStart=$command
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ${name}.service
    systemctl start ${name}.service
}

# 启动Socat
start_socat(){
    echo -e "${Green}正在配置Socat...${Font}"

    local service_name="socat-${port1}-${port2}"
    local command=""

    if [ "$ip_version" == "1" ]; then
        command="/usr/bin/socat TCP4-LISTEN:${port1},reuseaddr,fork TCP4:${socatip}:${port2}"
        create_systemd_service "${service_name}-tcp" "$command"
        command="/usr/bin/socat UDP4-LISTEN:${port1},reuseaddr,fork UDP4:${socatip}:${port2}"
        create_systemd_service "${service_name}-udp" "$command"
    elif [ "$ip_version" == "2" ]; then
        command="/usr/bin/socat TCP6-LISTEN:${port1},reuseaddr,fork TCP6:${socatip}:${port2}"
        create_systemd_service "${service_name}-tcp" "$command"
        command="/usr/bin/socat UDP6-LISTEN:${port1},reuseaddr,fork UDP6:${socatip}:${port2}"
        create_systemd_service "${service_name}-udp" "$command"
    elif [ "$ip_version" == "3" ]; then
        # 对于域名，默认使用IPv4，但socat会自动解析
        command="/usr/bin/socat TCP4-LISTEN:${port1},reuseaddr,fork TCP:${socatip}:${port2}"
        create_systemd_service "${service_name}-tcp" "$command"
        command="/usr/bin/socat UDP4-LISTEN:${port1},reuseaddr,fork UDP:${socatip}:${port2}"
        create_systemd_service "${service_name}-udp" "$command"
        
        # 设置域名IP监控
        setup_domain_monitor "$socatip" "$port1" "domain" "$port2"
    elif [ "$ip_version" == "4" ]; then
        # 对于IPv6域名，使用IPv6监听并连接
        command="/usr/bin/socat TCP6-LISTEN:${port1},reuseaddr,fork TCP6:${socatip}:${port2}"
        create_systemd_service "${service_name}-tcp" "$command"
        command="/usr/bin/socat UDP6-LISTEN:${port1},reuseaddr,fork UDP6:${socatip}:${port2}"
        create_systemd_service "${service_name}-udp" "$command"
        
        # 设置域名IP监控
        setup_domain_monitor "$socatip" "$port1" "domain6" "$port2"
    else
        echo -e "${Red}无效的选项，退出配置。${Font}"
        return
    fi

    sleep 2
    if systemctl is-active --quiet "${service_name}-tcp" && systemctl is-active --quiet "${service_name}-udp"; then
        echo -e "${Green}Socat配置成功!${Font}"
        echo -e "${Blue}本地端口: ${port1}${Font}"
        echo -e "${Blue}远程端口: ${port2}${Font}"
        echo -e "${Blue}远程地址: ${socatip}${Font}"
        if [ "$ip_version" == "1" ]; then
            echo -e "${Blue}本地服务器IP: ${ip}${Font}"
            echo -e "${Blue}IP版本: IPv4${Font}"
        elif [ "$ip_version" == "2" ]; then
            echo -e "${Blue}本地服务器IPv6: ${ipv6}${Font}"
            echo -e "${Blue}IP版本: IPv6${Font}"
        elif [ "$ip_version" == "3" ]; then
            echo -e "${Blue}本地服务器IP: ${ip}${Font}"
            echo -e "${Blue}地址类型: 域名 (DDNS, IPv4优先)${Font}"
            echo -e "${Blue}域名监控: 已启用 (每5分钟自动检查IP变更)${Font}"
        elif [ "$ip_version" == "4" ]; then
            echo -e "${Blue}本地服务器IPv6: ${ipv6}${Font}"
            echo -e "${Blue}地址类型: 域名 (DDNS, IPv6优先)${Font}"
            echo -e "${Blue}域名监控: 已启用 (每5分钟自动检查IP变更)${Font}"
        fi

        add_to_config
        if [ "$ip_version" == "1" ] || [ "$ip_version" == "3" ]; then
            configure_firewall ${port1} "ipv4"
        else
            configure_firewall ${port1} "ipv6"
        fi
    else
        echo -e "${Red}Socat启动失败，请检查系统日志。${Font}"
        journalctl -u "${service_name}-tcp" -u "${service_name}-udp"
    fi
}

# 显示和删除转发
view_delete_forward() {
    if [ ! -s "$CONFIG_FILE" ]; then
        echo -e "${Red}当前没有活动的转发。${Font}"
        return
    fi

    echo -e "${Green}当前转发列表:${Font}"
    local i=1
    local entries=()
    while IFS=' ' read -r ip_type listen_port remote_ip remote_port; do
        entries+=("$ip_type $listen_port $remote_ip $remote_port")
        if [ "$ip_type" == "ipv4" ]; then
            echo "$i. IPv4: $ip:$listen_port --> $remote_ip:$remote_port (TCP/UDP)"
        elif [ "$ip_type" == "ipv6" ]; then
            echo "$i. IPv6: [$ipv6]:$listen_port --> [$remote_ip]:$remote_port (TCP/UDP)"
        elif [ "$ip_type" == "domain" ]; then
            echo "$i. 域名: $ip:$listen_port --> $remote_ip:$remote_port (TCP/UDP) [DDNS, IPv4]"
        elif [ "$ip_type" == "domain6" ]; then
            echo "$i. 域名: [$ipv6]:$listen_port --> $remote_ip:$remote_port (TCP/UDP) [DDNS, IPv6]"
        fi
        ((i++))
    done < "$CONFIG_FILE"

    read -p "请输入要删除的转发编号（多个编号用空格分隔，直接回车取消）: " numbers
    if [ -n "$numbers" ]; then
        local nums_to_delete=($(echo "$numbers" | tr ' ' '\n' | sort -rn))
        for num in "${nums_to_delete[@]}"; do
            if [ $num -ge 1 ] && [ $num -lt $i ]; then
                local index=$((num-1))
                IFS=' ' read -r ip_type listen_port remote_ip remote_port <<< "${entries[$index]}"
                remove_forward "$listen_port" "$ip_type"
                sed -i "${num}d" "$CONFIG_FILE"
                if [ "$ip_type" == "ipv4" ]; then
                    echo -e "${Green}已删除IPv4转发: $ip:$listen_port (TCP/UDP)${Font}"
                elif [ "$ip_type" == "ipv6" ]; then
                    echo -e "${Green}已删除IPv6转发: [$ipv6]:$listen_port (TCP/UDP)${Font}"
                elif [ "$ip_type" == "domain" ]; then
                    echo -e "${Green}已删除域名转发: $ip:$listen_port --> $remote_ip (TCP/UDP) [IPv4]${Font}"
                elif [ "$ip_type" == "domain6" ]; then
                    echo -e "${Green}已删除域名转发: [$ipv6]:$listen_port --> $remote_ip (TCP/UDP) [IPv6]${Font}"
                fi
                remove_firewall_rules "$listen_port" "$ip_type"
            else
                echo -e "${Red}无效的编号: $num${Font}"
            fi
        done
    fi
}

# 移除单个转发
remove_forward() {
    local listen_port=$1
    local ip_type=$2
    local service_name="socat-${listen_port}-*"
    
    # 停止并移除socat服务
    systemctl stop ${service_name}
    systemctl disable ${service_name}
    rm -f /etc/systemd/system/${service_name}.service
    systemctl daemon-reload
    
    # 如果是域名类型，移除域名监控服务
    if [ "$ip_type" == "domain" ] || [ "$ip_type" == "domain6" ]; then
        remove_domain_monitor "$listen_port"
    fi
    
    echo -e "${Green}已移除端口 ${listen_port} 的转发${Font}"
}

# 防火墙检测和配置
configure_firewall() {
    local port=$1
    local ip_version=$2
    
    # 处理不同类型的IP版本
    if [ "$ip_version" == "domain" ]; then
        ip_version="ipv4"
    elif [ "$ip_version" == "domain6" ]; then
        ip_version="ipv6"
    fi

    local firewall_tool=""
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall_tool="firewalld"
    elif command -v ufw >/dev/null 2>&1; then
        firewall_tool="ufw"
    elif command -v iptables >/dev/null 2>&1; then
        firewall_tool="iptables"
    fi

    if [ -z "$firewall_tool" ]; then
        echo -e "${Yellow}未检测到防火墙工具，端口 ${port} 配置完成。${Font}"
        return
    fi

    local has_permission=false
    case $firewall_tool in
        "firewalld")
            if firewall-cmd --state >/dev/null 2>&1; then
                has_permission=true
            fi
            ;;
        "ufw")
            if ufw status >/dev/null 2>&1; then
                has_permission=true
            fi
            ;;
        "iptables")
            if iptables -L >/dev/null 2>&1; then
                has_permission=true
            fi
            ;;
    esac

    if [ "$has_permission" = true ]; then
        case $firewall_tool in
            "firewalld")
                if [ "$ip_version" == "ipv4" ]; then
                    firewall-cmd --zone=public --add-port=${port}/tcp --permanent >/dev/null 2>&1
                    firewall-cmd --zone=public --add-port=${port}/udp --permanent >/dev/null 2>&1
                else
                    firewall-cmd --zone=public --add-port=${port}/tcp --permanent --ipv6 >/dev/null 2>&1
                    firewall-cmd --zone=public --add-port=${port}/udp --permanent --ipv6 >/dev/null 2>&1
                fi
                firewall-cmd --reload >/dev/null 2>&1
                ;;
            "ufw")
                ufw allow ${port}/tcp >/dev/null 2>&1
                ufw allow ${port}/udp >/dev/null 2>&1
                ;;
            "iptables")
                if [ "$ip_version" == "ipv4" ]; then
                    iptables -I INPUT -p tcp --dport ${port} -j ACCEPT >/dev/null 2>&1
                    iptables -I INPUT -p udp --dport ${port} -j ACCEPT >/dev/null 2>&1
                else
                    ip6tables -I INPUT -p tcp --dport ${port} -j ACCEPT >/dev/null 2>&1
                    ip6tables -I INPUT -p udp --dport ${port} -j ACCEPT >/dev/null 2>&1
                fi
                ;;
        esac
        echo -e "${Green}已成功为 ${ip_version} 端口 ${port} 配置防火墙规则 (TCP/UDP)。${Font}"
    else
        echo -e "${Yellow}检测到 ${firewall_tool}，但无权限修改。请手动配置 ${ip_version} 端口 ${port} 的防火墙规则 (TCP/UDP)。${Font}"
    fi
}

# 移除防火墙规则
remove_firewall_rules() {
    local port=$1
    local ip_type=$2
    
    # 处理不同类型的IP版本
    if [ "$ip_type" == "domain" ]; then
        ip_type="ipv4"
    elif [ "$ip_type" == "domain6" ]; then
        ip_type="ipv6"
    fi

    local firewall_tool=""
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall_tool="firewalld"
    elif command -v ufw >/dev/null 2>&1; then
        firewall_tool="ufw"
    elif command -v iptables >/dev/null 2>&1; then
        firewall_tool="iptables"
    fi

    if [ -z "$firewall_tool" ]; then
        echo -e "${Yellow}未检测到防火墙工具，跳过防火墙规则移除。${Font}"
        return
    fi

    case $firewall_tool in
        "firewalld")
            if [ "$ip_type" == "ipv4" ]; then
                firewall-cmd --zone=public --remove-port=${port}/tcp --permanent >/dev/null 2>&1
                firewall-cmd --zone=public --remove-port=${port}/udp --permanent >/dev/null 2>&1
            else
                firewall-cmd --zone=public --remove-port=${port}/tcp --permanent --ipv6 >/dev/null 2>&1
                firewall-cmd --zone=public --remove-port=${port}/udp --permanent --ipv6 >/dev/null 2>&1
            fi
            firewall-cmd --reload >/dev/null 2>&1
            ;;
        "ufw")
            ufw delete allow ${port}/tcp >/dev/null 2>&1
            ufw delete allow ${port}/udp >/dev/null 2>&1
            ;;
        "iptables")
            if [ "$ip_type" == "ipv4" ]; then
                iptables -D INPUT -p tcp --dport ${port} -j ACCEPT >/dev/null 2>&1
                iptables -D INPUT -p udp --dport ${port} -j ACCEPT >/dev/null 2>&1
            else
                ip6tables -D INPUT -p tcp --dport ${port} -j ACCEPT >/dev/null 2>&1
                ip6tables -D INPUT -p udp --dport ${port} -j ACCEPT >/dev/null 2>&1
            fi
            ;;
    esac
    echo -e "${Green}已移除端口 ${port} 的防火墙规则 (TCP/UDP)。${Font}"
}

# 恢复之前的转发
restore_forwards() {
    if [ -s "$CONFIG_FILE" ]; then
        echo "正在恢复之前的转发..."
        while IFS=' ' read -r ip_type listen_port remote_ip remote_port; do
            local service_name="socat-${listen_port}-${remote_port}"
            if [ "$ip_type" == "ipv4" ]; then
                create_systemd_service "${service_name}-tcp" "/usr/bin/socat TCP4-LISTEN:${listen_port},reuseaddr,fork TCP4:${remote_ip}:${remote_port}"
                create_systemd_service "${service_name}-udp" "/usr/bin/socat UDP4-LISTEN:${listen_port},reuseaddr,fork UDP4:${remote_ip}:${remote_port}"
            elif [ "$ip_type" == "ipv6" ]; then
                create_systemd_service "${service_name}-tcp" "/usr/bin/socat TCP6-LISTEN:${listen_port},reuseaddr,fork TCP6:${remote_ip}:${remote_port}"
                create_systemd_service "${service_name}-udp" "/usr/bin/socat UDP6-LISTEN:${listen_port},reuseaddr,fork UDP6:${remote_ip}:${remote_port}"
            elif [ "$ip_type" == "domain" ]; then
                create_systemd_service "${service_name}-tcp" "/usr/bin/socat TCP4-LISTEN:${listen_port},reuseaddr,fork TCP:${remote_ip}:${remote_port}"
                create_systemd_service "${service_name}-udp" "/usr/bin/socat UDP4-LISTEN:${listen_port},reuseaddr,fork UDP:${remote_ip}:${remote_port}"
                # 恢复域名监控
                setup_domain_monitor "$remote_ip" "$listen_port" "$ip_type" "$remote_port"
            elif [ "$ip_type" == "domain6" ]; then
                create_systemd_service "${service_name}-tcp" "/usr/bin/socat TCP6-LISTEN:${listen_port},reuseaddr,fork TCP6:${remote_ip}:${remote_port}"
                create_systemd_service "${service_name}-udp" "/usr/bin/socat UDP6-LISTEN:${listen_port},reuseaddr,fork UDP6:${remote_ip}:${remote_port}"
                # 恢复域名监控
                setup_domain_monitor "$remote_ip" "$listen_port" "$ip_type" "$remote_port"
            fi
            
            # 显示不同类型的转发恢复信息
            if [ "$ip_type" == "ipv6" ] || [ "$ip_type" == "domain6" ]; then
                echo "已恢复IPv6转发：${listen_port} -> ${remote_ip}:${remote_port}"
            else
                echo "已恢复IPv4转发：${listen_port} -> ${remote_ip}:${remote_port}"
            fi
            
            # 如果是域名类型，显示监控恢复信息
            if [ "$ip_type" == "domain" ] || [ "$ip_type" == "domain6" ]; then
                echo "已恢复域名 ${remote_ip} 的IP监控服务"
            fi
        done < "$CONFIG_FILE"
    fi
}

# 强制终止所有Socat进程
kill_all_socat() {
    echo -e "${Yellow}正在终止所有 Socat 进程...${Font}"
    systemctl stop 'socat-*'
    systemctl disable 'socat-*'
    rm -f /etc/systemd/system/socat-*.service
    systemctl daemon-reload
    pkill -9 socat
    sleep 2
    if pgrep -f socat > /dev/null; then
        echo -e "${Red}警告：某些 Socat 进程可能仍在运行。请考虑手动检查。${Font}"
    else
        echo -e "${Green}所有 Socat 进程已成功终止。${Font}"
    fi
    > "$CONFIG_FILE"
    echo -e "${Green}已从配置和开机自启动中移除所有 Socat 转发${Font}"
}

# 检查是否已启用BBR或其变种
check_and_enable_bbr() {
    echo -e "${Green}正在检查 BBR 状态...${Font}"

    kernel_version=$(uname -r | cut -d- -f1)
    if [[ $(echo $kernel_version 4.9 | awk '{print ($1 < $2)}') -eq 1 ]]; then
        echo -e "${Red}当前内核版本 ($kernel_version) 过低，不支持 BBR。需要 4.9 或更高版本。${Font}"
        return 1
    fi

    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)

    if ! lsmod | grep -q "tcp_bbr"; then
        echo -e "${Yellow}BBR 模块未加载，正在尝试加载...${Font}"
        modprobe tcp_bbr
        if ! lsmod | grep -q "tcp_bbr"; then
            echo -e "${Red}无法加载 BBR 模块。请检查您的系统是否支持 BBR。${Font}"
            return 1
        fi
    fi

    bbr_variants=("bbr" "bbr2" "bbrplus" "tsunamy")

    if [[ " ${bbr_variants[@]} " =~ " ${current_cc} " ]]; then
        echo -e "${Yellow}检测到系统已启用 ${current_cc}。${Font}"
    else
        echo -e "${Yellow}当前拥塞控制算法为 ${current_cc}，正在切换到 BBR...${Font}"
        sysctl -w net.ipv4.tcp_congestion_control=bbr
    fi

    current_qdisc=$(sysctl -n net.core.default_qdisc)
    if [[ $current_qdisc != "fq" ]]; then
        echo -e "${Yellow}当前队列调度算法为 ${current_qdisc}，正在切换到 fq...${Font}"
        sysctl -w net.core.default_qdisc=fq
        echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    fi

    if ! grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    fi

    sysctl -p

    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    if [[ $current_cc == "bbr" ]]; then
        echo -e "${Green}BBR 已成功启用。${Font}"
    else
        echo -e "${Red}BBR 启用失败，当前拥塞控制算法为 ${current_cc}。${Font}"
    fi
}

# 开启端口转发加速
enable_acceleration() {
    echo -e "${Green}正在开启端口转发加速...${Font}"

    sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_slow_start_after_idle/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_mtu_probing/d' /etc/sysctl.conf
    sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_max/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_mem/d' /etc/sysctl.conf
    sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_keepalive_time/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_rfc1337/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_sack/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_fack/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_window_scaling/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_adv_win_scale/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_moderate_rcvbuf/d' /etc/sysctl.conf
    sed -i '/net.core.optmem_max/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_notsent_lowat/d' /etc/sysctl.conf

    check_and_enable_bbr

    echo 3 > /proc/sys/net/ipv4/tcp_fastopen

    sysctl -w net.ipv4.tcp_slow_start_after_idle=0
    sysctl -w net.ipv4.tcp_mtu_probing=1

    sysctl -w net.core.rmem_max=26214400
    sysctl -w net.core.wmem_max=26214400
    sysctl -w net.ipv4.tcp_rmem='4096 87380 26214400'
    sysctl -w net.ipv4.tcp_wmem='4096 16384 26214400'
    sysctl -w net.ipv4.tcp_mem='26214400 26214400 26214400'
    sysctl -w net.core.netdev_max_backlog=2048
    sysctl -w net.ipv4.tcp_max_syn_backlog=2048
    sysctl -w net.ipv4.tcp_tw_reuse=1
    sysctl -w net.ipv4.tcp_fin_timeout=15
    sysctl -w net.ipv4.tcp_keepalive_time=1200
    sysctl -w net.ipv4.tcp_max_tw_buckets=2000000
    sysctl -w net.ipv4.tcp_fastopen=3
    sysctl -w net.ipv4.tcp_mtu_probing=1
    sysctl -w net.ipv4.tcp_syncookies=1
    sysctl -w net.ipv4.tcp_rfc1337=1
    sysctl -w net.ipv4.tcp_sack=1
    sysctl -w net.ipv4.tcp_fack=1
    sysctl -w net.ipv4.tcp_window_scaling=1
    sysctl -w net.ipv4.tcp_adv_win_scale=2
    sysctl -w net.ipv4.tcp_moderate_rcvbuf=1
    sysctl -w net.core.optmem_max=65535
    sysctl -w net.ipv4.tcp_notsent_lowat=16384

    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_slow_start_after_idle = 0" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_mtu_probing = 1" >> /etc/sysctl.conf
    echo "net.core.rmem_max = 26214400" >> /etc/sysctl.conf
    echo "net.core.wmem_max = 26214400" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem = 4096 87380 26214400" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_wmem = 4096 16384 26214400" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_mem = 26214400 26214400 26214400" >> /etc/sysctl.conf
    echo "net.core.netdev_max_backlog = 2048" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_max_syn_backlog = 2048" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_tw_reuse = 1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_fin_timeout = 15" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_keepalive_time = 1200" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_max_tw_buckets = 2000000" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_mtu_probing = 1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rfc1337 = 1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_sack = 1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_fack = 1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_window_scaling = 1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_adv_win_scale = 2" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_moderate_rcvbuf = 1" >> /etc/sysctl.conf
    echo "net.core.optmem_max = 65535" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_notsent_lowat = 16384" >> /etc/sysctl.conf

    sysctl -p

    echo -e "${Green}端口转发加速已开启${Font}"
}

# 关闭端口转发加速
disable_acceleration() {
    echo -e "${Yellow}正在关闭端口转发加速...${Font}"

    sysctl -w net.ipv4.tcp_fastopen=0
    sysctl -w net.ipv4.tcp_congestion_control=cubic
    sysctl -w net.core.default_qdisc=pfifo_fast
    sysctl -w net.ipv4.tcp_slow_start_after_idle=1
    sysctl -w net.ipv4.tcp_mtu_probing=0

    sysctl -w net.core.rmem_max=212992
    sysctl -w net.core.wmem_max=212992
    sysctl -w net.ipv4.tcp_rmem='4096 87380 6291456'
    sysctl -w net.ipv4.tcp_wmem='4096 16384 4194304'
    sysctl -w net.ipv4.tcp_mem='378651 504868 757299'
    sysctl -w net.core.netdev_max_backlog=1000
    sysctl -w net.ipv4.tcp_max_syn_backlog=128
    sysctl -w net.ipv4.tcp_tw_reuse=0
    sysctl -w net.ipv4.tcp_fin_timeout=60
    sysctl -w net.ipv4.tcp_keepalive_time=7200
    sysctl -w net.ipv4.tcp_max_tw_buckets=180000
    sysctl -w net.ipv4.tcp_syncookies=1
    sysctl -w net.ipv4.tcp_rfc1337=0
    sysctl -w net.ipv4.tcp_sack=1
    sysctl -w net.ipv4.tcp_fack=1
    sysctl -w net.ipv4.tcp_window_scaling=1
    sysctl -w net.ipv4.tcp_adv_win_scale=1
    sysctl -w net.ipv4.tcp_moderate_rcvbuf=1
    sysctl -w net.core.optmem_max=20480
    sysctl -w net.ipv4.tcp_notsent_lowat=4294967295

    sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_slow_start_after_idle/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_mtu_probing/d' /etc/sysctl.conf
    sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_max/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_mem/d' /etc/sysctl.conf
    sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_keepalive_time/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_rfc1337/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_sack/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_fack/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_window_scaling/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_adv_win_scale/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_moderate_rcvbuf/d' /etc/sysctl.conf
    sed -i '/net.core.optmem_max/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_notsent_lowat/d' /etc/sysctl.conf

    sysctl -p

    echo -e "${Yellow}端口转发加速已关闭${Font}"
}

# 设置域名监控服务
setup_domain_monitor() {
    local domain=$1
    local listen_port=$2
    local ip_type=$3
    local remote_port=$4
    
    local monitor_script="$SOCATS_DIR/monitor_${listen_port}.sh"
    
    # 创建完整的监控脚本，直接内嵌函数定义
    cat > "$monitor_script" <<'EOF'
#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# 脚本参数
DOMAIN="$1"
LISTEN_PORT="$2"
IP_TYPE="$3"
REMOTE_PORT="$4"
SOCATS_DIR="$5"

# 监控域名IP变更的函数
monitor_domain_ip() {
    local domain=$1
    local listen_port=$2
    local ip_type=$3
    local cache_file="${SOCATS_DIR}/dns_cache_${domain//[^a-zA-Z0-9]/_}.txt"
    local current_ip=""
    
    # 获取当前IP（支持IPv4和IPv6）
    if [[ "$ip_type" == "ipv4" || "$ip_type" == "domain" ]]; then
        # 尝试使用不同的命令解析IPv4
        current_ip=$(host -t A "$domain" 2>/dev/null | grep "has address" | head -n1 | awk '{print $NF}')
        if [ -z "$current_ip" ]; then
            current_ip=$(dig +short A "$domain" 2>/dev/null | head -n1)
        fi
        if [ -z "$current_ip" ]; then
            current_ip=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | head -n1 | awk '{print $NF}')
        fi
    else
        # 尝试使用不同的命令解析IPv6
        current_ip=$(host -t AAAA "$domain" 2>/dev/null | grep "has IPv6 address" | head -n1 | awk '{print $NF}')
        if [ -z "$current_ip" ]; then
            current_ip=$(dig +short AAAA "$domain" 2>/dev/null | head -n1)
        fi
        if [ -z "$current_ip" ]; then
            current_ip=$(nslookup -type=AAAA "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | head -n1 | awk '{print $NF}')
        fi
    fi
    
    if [ -z "$current_ip" ]; then
        echo "无法解析域名 $domain 的IP地址" >> "${SOCATS_DIR}/dns_monitor.log"
        return 1
    fi
    
    # 如果缓存文件不存在，创建它
    if [ ! -f "$cache_file" ]; then
        echo "$current_ip" > "$cache_file"
        echo "$(date): 初始化域名 $domain 的IP缓存: $current_ip" >> "${SOCATS_DIR}/dns_monitor.log"
        return 0
    fi
    
    # 读取上次缓存的IP
    local cached_ip=$(cat "$cache_file")
    
    # 如果IP变更，重启服务
    if [ "$current_ip" != "$cached_ip" ]; then
        echo "$(date): 检测到域名 $domain 的IP变更: $cached_ip -> $current_ip" >> "${SOCATS_DIR}/dns_monitor.log"
        echo "$current_ip" > "$cache_file"
        
        # 重启对应的socat服务
        local service_name="socat-${listen_port}-*"
        systemctl restart $service_name
        echo "$(date): 已重启转发服务 $service_name" >> "${SOCATS_DIR}/dns_monitor.log"
        return 0
    fi
    
    return 0
}

# 执行监控
monitor_domain_ip "$DOMAIN" "$LISTEN_PORT" "$IP_TYPE"
EOF
    
    chmod +x "$monitor_script"
    
    # 创建systemd定时器服务
    local timer_name="domain-monitor-${listen_port}"
    
    cat > /etc/systemd/system/${timer_name}.service <<EOF
[Unit]
Description=Domain IP Monitor Service for ${domain}
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $monitor_script "${domain}" "${listen_port}" "${ip_type}" "${remote_port}" "${SOCATS_DIR}"

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/${timer_name}.timer <<EOF
[Unit]
Description=Domain IP Monitor Timer for ${domain}
Requires=${timer_name}.service

[Timer]
OnBootSec=60
OnUnitActiveSec=300
AccuracySec=1

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable ${timer_name}.timer
    systemctl start ${timer_name}.timer
    
    echo -e "${Green}已启用域名 ${domain} 的IP监控，每5分钟检查一次变更${Font}"
}

# 移除域名监控服务
remove_domain_monitor() {
    local listen_port=$1
    local timer_name="domain-monitor-${listen_port}"
    
    systemctl stop ${timer_name}.timer >/dev/null 2>&1
    systemctl disable ${timer_name}.timer >/dev/null 2>&1
    rm -f /etc/systemd/system/${timer_name}.service
    rm -f /etc/systemd/system/${timer_name}.timer
    rm -f "$SOCATS_DIR/monitor_${listen_port}.sh"
    systemctl daemon-reload
    
    echo -e "${Green}已移除端口 ${listen_port} 的域名监控服务${Font}"
}

# 修改域名监控频率
change_monitor_interval() {
    if [ ! -s "$CONFIG_FILE" ]; then
        echo -e "${Red}当前没有活动的转发。${Font}"
        return
    fi
    
    local has_domain=false
    while IFS=' ' read -r ip_type listen_port remote_ip remote_port; do
        if [ "$ip_type" == "domain" ] || [ "$ip_type" == "domain6" ]; then
            has_domain=true
            break
        fi
    done < "$CONFIG_FILE"
    
    if [ "$has_domain" == "false" ]; then
        echo -e "${Red}当前没有活动的域名转发。${Font}"
        return
    fi
    
    echo -e "${Green}当前域名转发:${Font}"
    local i=1
    local domain_entries=()
    while IFS=' ' read -r ip_type listen_port remote_ip remote_port; do
        if [ "$ip_type" == "domain" ] || [ "$ip_type" == "domain6" ]; then
            domain_entries+=("$listen_port $remote_ip $ip_type")
            if [ "$ip_type" == "domain" ]; then
                echo "$i. IPv4域名: $ip:$listen_port --> $remote_ip:$remote_port"
            else
                echo "$i. IPv6域名: [$ipv6]:$listen_port --> $remote_ip:$remote_port"
            fi
            ((i++))
        fi
    done < "$CONFIG_FILE"
    
    if [ ${#domain_entries[@]} -eq 0 ]; then
        echo -e "${Red}未找到任何域名转发。${Font}"
        return
    fi
    
    read -p "请输入要修改监控频率的域名转发编号: " num
    if [ -z "$num" ] || ! [[ $num =~ ^[0-9]+$ ]] || [ $num -lt 1 ] || [ $num -gt ${#domain_entries[@]} ]; then
        echo -e "${Red}无效的编号。${Font}"
        return
    fi
    
    local index=$((num-1))
    IFS=' ' read -r port domain type <<< "${domain_entries[$index]}"
    
    local timer_name="domain-monitor-${port}"
    local timer_file="/etc/systemd/system/${timer_name}.timer"
    
    if [ ! -f "$timer_file" ]; then
        echo -e "${Red}找不到域名 $domain 的监控定时器。${Font}"
        return
    fi
    
    local current_interval=$(grep "OnUnitActiveSec" "$timer_file" | awk -F= '{print $2}' | tr -d '[:space:]')
    echo -e "${Green}当前域名 $domain 的监控频率为 ${current_interval:-300s}${Font}"
    
    echo -e "${Yellow}请选择新的监控频率:${Font}"
    echo "1. 1分钟 (适合频繁变更的域名)"
    echo "2. 5分钟 (默认)"
    echo "3. 15分钟"
    echo "4. 30分钟"
    echo "5. 1小时"
    echo "6. 自定义"
    
    read -p "请选择 [1-6]: " choice
    
    local new_interval=""
    case $choice in
        1) new_interval="60s" ;;
        2) new_interval="300s" ;;
        3) new_interval="900s" ;;
        4) new_interval="1800s" ;;
        5) new_interval="3600s" ;;
        6)
            read -p "请输入自定义时间间隔 (格式: 数字+单位, 例如 10s, 5m, 1h): " custom_interval
            if [[ $custom_interval =~ ^[0-9]+[smhd]$ ]]; then
                new_interval=$custom_interval
            else
                echo -e "${Red}无效的时间格式。使用默认值300s。${Font}"
                new_interval="300s"
            fi
            ;;
        *)
            echo -e "${Red}无效的选择。使用默认值300s。${Font}"
            new_interval="300s"
            ;;
    esac
    
    # 更新定时器配置
    sed -i "s/OnUnitActiveSec=.*/OnUnitActiveSec=$new_interval/" "$timer_file"
    systemctl daemon-reload
    systemctl restart ${timer_name}.timer
    
    echo -e "${Green}已将域名 $domain 的监控频率更新为 $new_interval${Font}"
}

# 显示菜单
show_menu() {
    echo -e "${Green}
   _____                 __
  / ___/____  _________ _/ /_
  \__ \/ __ \/ ___/ __ \`/ __/
 ___/ / /_/ / /__/ /_/ / /_
/____/\____/\___/\__,_/\__/  ${Yellow}Management Script${Font}"
    echo -e "${Blue}==========================================${Font}"
    echo -e "${Yellow}1.${Font} 添加新转发"
    echo -e "${Yellow}2.${Font} 查看或删除转发"
    echo -e "${Yellow}3.${Font} 强制终止所有 Socat 进程"
    echo -e "${Yellow}4.${Font} 开启端口转发加速"
    echo -e "${Yellow}5.${Font} 关闭端口转发加速"
    echo -e "${Yellow}6.${Font} 设置域名监控频率"
    echo -e "${Yellow}7.${Font} 退出脚本"
    echo -e "${Blue}==========================================${Font}"
    echo -e "${Green}当前 IPv4: ${ip:-未知}${Font}"
    echo -e "${Green}当前 IPv6: ${ipv6:-未知}${Font}"
    echo
}

# 主程序
main() {
    check_root
    check_sys
    install_socat

    ip=$(get_ip)
    ipv6=$(get_ipv6)

    echo "Debug: IP = $ip"
    echo "Debug: IPv6 = $ipv6"
    echo "Debug: CONFIG_FILE = $CONFIG_FILE"

    init_config
    restore_forwards
    clear_screen

    echo -e "${Green}所有配置和日志文件将保存在: $SOCATS_DIR${Font}"

    while true; do
        show_menu
        read -p "请输入选项 [1-7]: " choice
        clear_screen
        case $choice in
            1)
                if config_socat; then
                    start_socat
                else
                    echo -e "${Red}配置失败，未能启动 Socat${Font}"
                fi
                press_any_key
                ;;
            2)
                view_delete_forward
                press_any_key
                ;;
            3)
                kill_all_socat
                press_any_key
                ;;
            4)
                enable_acceleration
                press_any_key
                ;;
            5)
                disable_acceleration
                press_any_key
                ;;
            6)
                change_monitor_interval
                press_any_key
                ;;
            7)
                echo -e "${Green}感谢使用,再见!${Font}"
                exit 0
                ;;
            *)
                echo -e "${Red}无效选项,请重新选择${Font}"
                press_any_key
                ;;
        esac
    done
}

# 执行主程序
main
