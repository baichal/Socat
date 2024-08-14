#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# ====================================================
#    系统要求: CentOS 6+、Debian 7+、Ubuntu 14+
#    描述: Socat 一键安装管理脚本
#    版本: 2.8
#    作者：白茶
# ====================================================

Green="\033[32m"
Font="\033[0m"
Blue="\033[34m"
Red="\033[31m"
Yellow="\033[33m"

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

# 获取本机IP（使用多个备选服务）
get_ip(){
    local ip_services=("http://ipv4.icanhazip.com" "http://api.ipify.org" "http://ifconfig.me")
    for service in "${ip_services[@]}"; do
        ip=$(curl -s -m 10 "$service")
        if [[ -n "$ip" ]]; then
            break
        fi
    done

    if [[ -z "$ip" ]]; then
        ip=$(ip addr | grep 'inet ' | grep -v 127.0.0.1 | head -n1 | awk '{print $2}' | cut -d'/' -f1)
    fi

    if [[ -z "$ip" ]]; then
        echo -e "${Red}无法获取服务器IP地址${Font}"
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
    nohup socat TCP4-LISTEN:${port1},reuseaddr,fork TCP4:${socatip}:${port2} >> /root/socat.log 2>&1 &

    # 检查是否成功启动
    sleep 2
    if pgrep -f "socat.*LISTEN:${port1}.*TCP4:${socatip}:${port2}" > /dev/null; then
        echo -e "${Green}Socat配置成功!${Font}"
        echo -e "${Blue}本地端口: ${port1}${Font}"
        echo -e "${Blue}远程端口: ${port2}${Font}"
        echo -e "${Blue}远程IP: ${socatip}${Font}"
        get_ip
        echo -e "${Blue}本地服务器IP: ${ip}${Font}"

        # 添加到开机自启
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

    startup_cmd="nohup socat TCP4-LISTEN:${port1},reuseaddr,fork TCP4:${socatip}:${port2} >> /root/socat.log 2>&1 &"
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
    local forwards=$(ps aux | grep socat | grep -v grep | grep -v "socat.sh")
    if [ -z "$forwards" ]; then
        echo -e "${Red}当前没有活动的转发。${Font}"
        return
    fi

    echo -e "${Green}当前转发列表:${Font}"
    local i=1
    declare -A unique_forwards

    while read -r line; do
        local pid=$(echo $line | awk '{print $2}')
        local config=$(echo $line | awk -F'socat ' '{print $2}')
        local listen_port=$(echo $config | awk -F'LISTEN:' '{print $2}' | cut -d',' -f1)
        local remote_info=$(echo $config | awk -F'TCP4:' '{print $2}')
        local remote_ip=$(echo $remote_info | cut -d: -f1)
        local remote_port=$(echo $remote_info | cut -d: -f2)

        local key="${listen_port}:${remote_ip}:${remote_port}"
        if [[ -z ${unique_forwards[$key]} ]]; then
            unique_forwards[$key]="$i. $ip:$listen_port --> $remote_ip:$remote_port (PID: $pid)"
            ((i++))
        fi
    done <<< "$forwards"

    for forward in "${unique_forwards[@]}"; do
        echo "$forward"
    done

    read -p "请输入要删除的转发编号（多个编号用空格分隔，直接回车取消）: " numbers
    if [ -n "$numbers" ]; then
        for num in $numbers; do
            local selected_forward=""
            for forward in "${unique_forwards[@]}"; do
                if [[ $forward == $num.* ]]; then
                    selected_forward=$forward
                    break
                fi
            done

            if [ -n "$selected_forward" ]; then
                local listen_port=$(echo $selected_forward | awk -F':' '{print $2}' | awk '{print $1}')
                local pids=$(pgrep -f "socat.*LISTEN:${listen_port}")
                for pid in $pids; do
                    kill -9 $pid
                    echo -e "${Green}已删除转发: PID $pid${Font}"
                done
                remove_from_startup $listen_port
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
    # 清理开机自启动脚本
    sed -i '/socat TCP4-LISTEN/d' /etc/rc.local
    echo -e "${Green}已从开机自启动中移除所有 Socat 转发${Font}"
}

# 显示菜单
show_menu() {
    echo -e "${Green}========= Socat 管理脚本 ==========${Font}"
    echo "1. 添加新转发"
    echo "2. 查看或删除转发"
    echo "3. 强制终止所有 Socat 进程"
    echo "4. 退出脚本"
    echo -e "${Green}=====================================${Font}"
}

# 主程序
main() {
    check_root
    check_sys
    install_socat
    clear_screen

    while true; do
        show_menu
        read -p "请输入选项 [1-4]: " choice
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
