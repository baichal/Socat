#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# ====================================================
#    系统要求: CentOS 7+、Debian 8+、Ubuntu 16+
#    描述: Socat 一键安装管理脚本
#    版本: 4.0
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
    else
        echo "ipv6 $port1 $socatip $port2" >> "$CONFIG_FILE"
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
    read -p "请输入选项 [1-2]: " ip_version

    if [ "$ip_version" == "2" ]; then
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
    else
        echo -e "${Red}错误: 无效的选项${Font}"
        return 1
    fi
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
    else
        echo -e "${Red}无效的选项，退出配置。${Font}"
        return
    fi

    sleep 2
    if systemctl is-active --quiet "${service_name}-tcp" && systemctl is-active --quiet "${service_name}-udp"; then
        echo -e "${Green}Socat配置成功!${Font}"
        echo -e "${Blue}本地端口: ${port1}${Font}"
        echo -e "${Blue}远程端口: ${port2}${Font}"
        echo -e "${Blue}远程IP: ${socatip}${Font}"
        if [ "$ip_version" == "1" ]; then
            echo -e "${Blue}本地服务器IP: ${ip}${Font}"
            echo -e "${Blue}IP版本: IPv4${Font}"
        else
            echo -e "${Blue}本地服务器IPv6: ${ipv6}${Font}"
            echo -e "${Blue}IP版本: IPv6${Font}"
        fi

        add_to_config
        if [ "$ip_version" == "1" ]; then
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
        else
            echo "$i. IPv6: [$ipv6]:$listen_port --> [$remote_ip]:$remote_port (TCP/UDP)"
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
                else
                    echo -e "${Green}已删除IPv6转发: [$ipv6]:$listen_port (TCP/UDP)${Font}"
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
    systemctl stop ${service_name}
    systemctl disable ${service_name}
    rm -f /etc/systemd/system/${service_name}.service
    systemctl daemon-reload
    echo -e "${Green}已移除端口 ${listen_port} 的转发${Font}"
}

# 防火墙检测和配置
configure_firewall() {
    local port=$1
    local ip_version=$2

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
    local ip_version=$2

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
            if [ "$ip_version" == "ipv4" ]; then
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
            if [ "$ip_version" == "ipv4" ]; then
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
            fi
            echo "已恢复转发：${listen_port} -> ${remote_ip}:${remote_port}"
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
    echo -e "${Yellow}6.${Font} 退出脚本"
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
        read -p "请输入选项 [1-6]: " choice
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
