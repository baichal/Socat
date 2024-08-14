#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# ====================================================
#    系统要求: CentOS 6+、Debian 7+、Ubuntu 14+
#    描述: Socat 一键安装管理脚本
#    版本: 3.1
# ====================================================

Green="\033[32m"
Font="\033[0m"
Blue="\033[34m"
Red="\033[31m"
Yellow="\033[33m"

# 配置文件路径
CONFIG_FILE="./socat_forwards.conf"

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
    ip=$(ip addr | grep 'inet ' | grep -v 127.0.0.1 | head -n1 | awk '{print $2}' | cut -d'/' -f1)
    if [[ -z "$ip" ]]; then
        ip="未知"
    fi
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
    fi
}

# 添加转发到配置文件
add_to_config() {
    echo "$port1 $socatip $port2" >> "$CONFIG_FILE"
}

# 从配置文件中移除转发
remove_from_config() {
    local listen_port=$1
    sed -i "/^$listen_port /d" "$CONFIG_FILE"
}

# 配置Socat
config_socat(){
    echo -e "${Green}请输入Socat配置信息！${Font}"
    read -p "请输入本地端口: " port1
    read -p "请输入远程端口: " port2
    read -p "请输入远程IP: " socatip
}

# 启动Socat
start_socat(){
    echo -e "${Green}正在配置Socat...${Font}"
    nohup socat TCP4-LISTEN:${port1},reuseaddr,fork,keepalive,nodelay TCP4:${socatip}:${port2},keepalive,nodelay >> ./socat.log 2>&1 &

    # 检查是否成功启动
    sleep 2
    if pgrep -f "socat.*LISTEN:${port1}.*TCP4:${socatip}:${port2}" > /dev/null; then
        echo -e "${Green}Socat配置成功!${Font}"
        echo -e "${Blue}本地端口: ${port1}${Font}"
        echo -e "${Blue}远程端口: ${port2}${Font}"
        echo -e "${Blue}远程IP: ${socatip}${Font}"
        echo -e "${Blue}本地服务器IP: ${ip}${Font}"

        # 添加到配置文件和开机自启
        add_to_config
        add_to_startup
    else
        echo -e "${Red}Socat启动失败，请检查配置和系统设置。${Font}"
    fi
}

# 添加到开机自启
add_to_startup() {
    rc_local="/etc/rc.local"
    if [ ! -f "$rc_local" ]; then
        echo '#!/bin/bash' > "$rc_local"
    fi

    startup_cmd="nohup socat TCP4-LISTEN:${port1},reuseaddr,fork,keepalive,nodelay TCP4:${socatip}:${port2},keepalive,nodelay >> $(pwd)/socat.log 2>&1 &"
    if ! grep -q "$startup_cmd" "$rc_local"; then
        echo "$startup_cmd" >> "$rc_local"
        chmod +x "$rc_local"
        echo -e "${Green}已添加到开机自启动${Font}"
    else
        echo -e "${Yellow}该转发已在开机自启动列表中${Font}"
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
    while read -r line; do
        local listen_port=$(echo $line | awk '{print $1}')
        local remote_ip=$(echo $line | awk '{print $2}')
        local remote_port=$(echo $line | awk '{print $3}')
        echo "$i. $ip:$listen_port --> $remote_ip:$remote_port"
        ((i++))
    done < "$CONFIG_FILE"

    read -p "请输入要删除的转发编号（多个编号用空格分隔，直接回车取消）: " numbers
    if [ -n "$numbers" ]; then
        for num in $numbers; do
            if [ $num -ge 1 ] && [ $num -lt $i ]; then
                local line=$(sed -n "${num}p" "$CONFIG_FILE")
                local listen_port=$(echo $line | awk '{print $1}')
                pkill -f "socat.*LISTEN:${listen_port}"
                remove_from_config $listen_port
                remove_from_startup $listen_port
                echo -e "${Green}已删除转发: $ip:$listen_port${Font}"
            else
                echo -e "${Red}无效的编号: $num${Font}"
            fi
        done
    fi
}

# 从开机自启动中移除
remove_from_startup() {
    local listen_port=$1
    rc_local="/etc/rc.local"
    if [ -f "$rc_local" ]; then
        sed -i "/socat.*LISTEN:${listen_port}/d" "$rc_local"
        echo -e "${Green}已从开机自启动中移除端口 ${listen_port} 的转发${Font}"
    fi
}

# 强制终止所有Socat进程
kill_all_socat() {
    echo -e "${Yellow}正在终止所有 Socat 进程...${Font}"
    pkill -9 socat
    sleep 2
    if pgrep -f socat > /dev/null; then
        echo -e "${Red}警告：某些 Socat 进程可能仍在运行。请考虑手动检查。${Font}"
    else
        echo -e "${Green}所有 Socat 进程已成功终止。${Font}"
    fi
    # 清空配置文件
    > "$CONFIG_FILE"
    # 清理开机自启动脚本
    sed -i '/socat TCP4-LISTEN/d' /etc/rc.local
    echo -e "${Green}已从配置和开机自启动中移除所有 Socat 转发${Font}"
}

# 开启端口转发加速
enable_acceleration() {
    echo -e "${Green}正在开启端口转发加速...${Font}"
    
    # 启用 TCP Fast Open
    echo 3 > /proc/sys/net/ipv4/tcp_fastopen
    
    # 优化内核参数
    sysctl -w net.ipv4.tcp_congestion_control=bbr
    sysctl -w net.core.default_qdisc=fq
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0
    sysctl -w net.ipv4.tcp_mtu_probing=1
    
    # 新增优化参数
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
    
    # 持久化设置
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_slow_start_after_idle = 0" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_mtu_probing = 1" >> /etc/sysctl.conf
    # 添加新增的优化参数到sysctl.conf
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
    
    # 恢复默认内核参数
    sysctl -w net.ipv4.tcp_fastopen=0
    sysctl -w net.ipv4.tcp_congestion_control=cubic
    sysctl -w net.core.default_qdisc=pfifo_fast
    sysctl -w net.ipv4.tcp_slow_start_after_idle=1
    sysctl -w net.ipv4.tcp_mtu_probing=0
    
    # 恢复其他参数到默认值
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
    
    # 从配置文件中移除所有自定义设置
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
    echo -e "${Green}========= Socat 管理脚本 ==========${Font}"
    echo "1. 添加新转发"
    echo "2. 查看或删除转发"
    echo "3. 强制终止所有 Socat 进程"
    echo "4. 开启端口转发加速"
    echo "5. 关闭端口转发加速"
    echo "6. 退出脚本"
    echo -e "${Green}=====================================${Font}"
}

# 主程序
main() {
    check_root
    check_sys
    install_socat
    get_ip
    init_config
    clear_screen

    while true; do
        show_menu
        read -p "请输入选项 [1-6]: " choice
        clear_screen
        case $choice in
            1)
                config_socat
                start_socat
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
