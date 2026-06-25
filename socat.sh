#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# ====================================================
#    系统要求: CentOS 7+、Debian 8+、Ubuntu 16+
#    描述: Socat 一键安装管理脚本
#    版本: 5.2
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

# JSON格式化开关 (0=不格式化, 1=格式化)
JSON_FORMAT_ENABLED=${JSON_FORMAT_ENABLED:-1}

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

# 系统检测逻辑
check_sys(){
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="centos"
        VER=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        VER=$(cat /etc/debian_version)
    else
        echo "不支持的操作系统！"
        exit 1
    fi
    
    # 标准化包管理器检测
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
    else
        echo "未找到支持的包管理器！"
        exit 1
    fi
}

# IP获取
get_ip(){
    local ip=""
    
    # 优先使用ip命令
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    fi
    
    # 备选方案
    if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    fi
    
    echo ${ip:-"127.0.0.1"}
}

# IPv6检测和获取
get_ipv6(){
    local ipv6=""
    
    # 检查系统是否支持IPv6
    if [[ ! -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]] || [[ $(cat /proc/sys/net/ipv6/conf/all/disable_ipv6) -eq 1 ]]; then
        echo ""
        return
    fi
    
    # 获取可用的全球单播IPv6地址
    if command -v ip >/dev/null 2>&1; then
        ipv6=$(ip -6 route get 2001:4860:4860::8888 2>/dev/null | grep -oE 'src [0-9a-fA-F:]+' | awk '{print $2}' | grep -v '^fe80' | head -n1)
    fi
    
    # 备选方案
    if [[ -z "$ipv6" ]] && command -v hostname >/dev/null 2>&1; then
        ipv6=$(hostname -I 2>/dev/null | grep -oE '([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}' | head -n1)
    fi
    
    echo ${ipv6:-""}
}

# 检查并安装jq
install_jq(){
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${Green}检测到 jq 未安装，正在安装 jq...${Font}"
        
        case "$PKG_MANAGER" in
            "yum")
                yum install -y jq
                ;;
            "dnf")
                dnf install -y jq
                ;;
            "apt")
                apt-get update -y
                apt-get install -y jq
                ;;
            "pacman")
                pacman -Sy --noconfirm jq
                ;;
            *)
                echo -e "${Yellow}不支持的包管理器: $PKG_MANAGER，跳过 jq 安装${Font}"
                return 1
                ;;
        esac
        
        if command -v jq >/dev/null 2>&1; then
            echo -e "${Green}jq 安装完成！${Font}"
            return 0
        else
            echo -e "${Red}jq 安装失败，将使用手动 JSON 解析${Font}"
            return 1
        fi
    else
        echo -e "${Green}jq 已安装，跳过安装${Font}"
        return 0
    fi
}

# 卸载jq
uninstall_jq(){
    if command -v jq >/dev/null 2>&1; then
        echo -e "${Green}正在卸载 jq...${Font}"
        
        case "$PKG_MANAGER" in
            "yum")
                yum remove -y jq
                ;;
            "dnf")
                dnf remove -y jq
                ;;
            "apt")
                apt-get remove -y jq
                ;;
            "pacman")
                pacman -R --noconfirm jq
                ;;
            *)
                echo -e "${Red}不支持的包管理器: $PKG_MANAGER${Font}"
                return 1
                ;;
        esac
        
        if ! command -v jq >/dev/null 2>&1; then
            echo -e "${Green}jq 卸载完成！${Font}"
        else
            echo -e "${Red}jq 卸载失败${Font}"
        fi
    else
        echo -e "${Yellow}jq 未安装，无需卸载${Font}"
    fi
}

# Socat安装
install_socat(){
    if ! command -v socat >/dev/null 2>&1; then
        echo -e "${Green}正在安装 Socat...${Font}"
        
        case "$PKG_MANAGER" in
            "yum")
                yum install -y socat
                ;;
            "dnf")
                dnf install -y socat
                ;;
            "apt")
                apt-get update -y
                apt-get install -y socat
                ;;
            "pacman")
                pacman -Sy --noconfirm socat
                ;;
            *)
                echo -e "${Red}不支持的包管理器: $PKG_MANAGER${Font}"
                exit 1
                ;;
        esac
        
        if command -v socat >/dev/null 2>&1; then
            echo -e "${Green}Socat 安装完成！${Font}"
        else
            echo -e "${Red}Socat 安装失败，请检查网络连接和系统设置。${Font}"
            exit 1
        fi
    fi
}

# 迁移旧格式配置到JSON格式
migrate_old_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[]" > "$CONFIG_FILE"
        return
    fi
    
    # 检查是否为JSON格式
    if command -v jq >/dev/null 2>&1; then
        if jq empty "$CONFIG_FILE" 2>/dev/null; then
            return  # 已经是有效的JSON格式
        fi
    else
        # 简单的JSON格式检查
        if head -c 1 "$CONFIG_FILE" | grep -q '^\['; then
            return  # 看起来是JSON数组
        fi
    fi
    
    echo -e "${Yellow}检测到旧格式配置文件，正在迁移到JSON格式...${Font}"
    
    # 创建备份
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 迁移旧格式到JSON
    local temp_json=$(mktemp)
    echo "[" > "$temp_json"
    
    local first_entry=true
    while IFS=' ' read -r type port1 socatip port2; do
        if [[ -n "$type" && -n "$port1" && -n "$socatip" && -n "$port2" ]]; then
            local forward_type=""
            case "$type" in
                "ipv4") forward_type="ipv4" ;;
                "ipv6") forward_type="ipv6" ;;
                "domain") forward_type="domain" ;;
                "domain6") forward_type="domain6" ;;
                *) forward_type="ipv4" ;;
            esac
            
            if [[ "$first_entry" == "false" ]]; then
                echo "," >> "$temp_json"
            fi
            
            echo -n "{\"type\":\"$forward_type\",\"listen_port\":$port1,\"remote_ip\":\"$socatip\",\"remote_port\":$port2}" >> "$temp_json"
            first_entry=false
        fi
    done < "$CONFIG_FILE"
    
    echo "]" >> "$temp_json"
    
    # 验证并替换
    if command -v jq >/dev/null 2>&1; then
        if jq empty "$temp_json" 2>/dev/null; then
            mv "$temp_json" "$CONFIG_FILE"
            echo -e "${Green}配置迁移完成！旧配置已备份${Font}"
        else
            echo -e "${Red}配置迁移失败，保留原配置${Font}"
            rm -f "$temp_json"
        fi
    else
        # 无jq时直接替换
        mv "$temp_json" "$CONFIG_FILE"
        echo -e "${Green}配置迁移完成！旧配置已备份${Font}"
    fi
}

# 统一JSON格式处理函数
format_json_config() {
    local input_file="${1:-$CONFIG_FILE}"
    local format_type="${2:-$JSON_FORMAT_ENABLED}"
    
    if [ ! -f "$input_file" ]; then
        echo "[]" > "$input_file"
        return 0
    fi
    
    if command -v jq >/dev/null 2>&1; then
        if [ "$format_type" -eq 1 ]; then
            # 格式化模式 - 完全格式化
            jq '.' "$input_file" > "$input_file.tmp" 2>/dev/null && mv "$input_file.tmp" "$input_file"
        else
            # 紧凑模式但每个对象单独一行，逗号放在对象后面
            local temp_file=$(mktemp)
            
            # 使用jq生成紧凑格式，逗号放在对象后面
            echo "[" > "$temp_file"
            
            local objects=$(jq -c '.[]' "$input_file" 2>/dev/null)
            local count=0
            local total=$(echo "$objects" | wc -l | tr -d ' ')
            
            while IFS= read -r obj; do
                [[ -z "$obj" ]] && continue
                count=$((count + 1))
                
                if [[ $count -eq $total ]]; then
                    echo "  $obj" >> "$temp_file"
                else
                    echo "  $obj," >> "$temp_file"
                fi
            done <<< "$objects"
            
            echo "]" >> "$temp_file"
            mv "$temp_file" "$input_file"
        fi
        return 0
    fi
    
    # 无jq时的回退处理
    if [ "$format_type" -eq 1 ]; then
        # 使用回退方案进行格式化
        local temp_file=$(mktemp)
        local content=$(cat "$input_file")
        
        # 提取所有有效的JSON对象
        local objects=()
        local current_object=""
        local brace_count=0
        local in_object=false
        
        # 逐字符解析JSON
        while IFS= read -r -n1 char; do
            case "$char" in
                '{')
                    if [[ $brace_count -eq 0 ]]; then
                        in_object=true
                        current_object="{"
                    else
                        current_object="$current_object{"
                    fi
                    brace_count=$((brace_count + 1))
                    ;;
                '}')
                    current_object="$current_object}"
                    brace_count=$((brace_count - 1))
                    if [[ $brace_count -eq 0 && $in_object == true ]]; then
                        objects+=("$current_object")
                        in_object=false
                        current_object=""
                    fi
                    ;;
                *)
                    if [[ $in_object == true ]]; then
                        current_object="$current_object$char"
                    fi
                    ;;
            esac
        done <<< "$content"
        
        # 重新构建JSON数组 - 紧凑模式但每个对象单独一行
        echo "[" > "$temp_file"
        
        local first=true
        for obj in "${objects[@]}"; do
            # 确保对象是有效的JSON格式
            if [[ -n "$obj" && "$obj" =~ ^\{.*\}$ ]]; then
                # 检查是否包含必要的字段
                if [[ "$obj" == *"\"type\""* && "$obj" == *"\"listen_port\""* && "$obj" == *"\"remote_ip\""* && "$obj" == *"\"remote_port\""* ]]; then
                    if [[ "$first" == "true" ]]; then
                        first=false
                    else
                        echo "," >> "$temp_file"
                    fi
                    # 紧凑模式：每个对象单独一行
                    echo "  $obj" >> "$temp_file"
                fi
            fi
        done
        
        echo "]" >> "$temp_file"
        
        # 确保格式正确：移除多余逗号、空行等
        sed -i 's/,,/,/g' "$temp_file"
        sed -i 's/\[,\?/[/' "$temp_file"
        sed -i 's/\,\?\]/]/' "$temp_file"
        sed -i 's/},\s*,/},/g' "$temp_file"
        
        mv "$temp_file" "$input_file"
    else
        # 紧凑模式但每个对象单独一行，逗号放在对象后面（无jq回退）
        local temp_file=$(mktemp)
        
        # 提取现有对象并重新格式化
        local content=$(cat "$input_file" | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 使用sed重新格式化：紧凑但每个对象一行，逗号放在对象后面
        echo "[" > "$temp_file"
        
        # 提取对象并格式化
        local objects=$(echo "$content" | sed 's/^\[//;s/\]$//' | sed 's/},{/}\n  {/g')
        
        local count=0
        local total=$(echo "$objects" | grep -c '^' || echo 0)
        
        while IFS= read -r obj; do
            [[ -z "$obj" || "$obj" == "{" ]] && continue
            
            count=$((count + 1))
            
            # 确保对象格式正确
            if [[ "$obj" != *"}" ]]; then
                obj="$obj}"
            fi
            
            # 添加对象，根据是否是最后一个决定是否添加逗号
            if [[ $count -eq $total ]]; then
                echo "  $obj" >> "$temp_file"
            else
                echo "  $obj," >> "$temp_file"
            fi
        done <<< "$objects"
        
        echo "]" >> "$temp_file"
        mv "$temp_file" "$input_file"
    fi
}

# 从JSON配置文件提取所有对象（无jq回退辅助函数）
json_extract_objects() {
    local file="$1"
    local content=$(cat "$file" 2>/dev/null | tr -d '\n')
    
    local objects=()
    local current=""
    local brace_count=0
    local in_object=false
    
    local i=0
    local len=${#content}
    while [ $i -lt $len ]; do
        local char="${content:$i:1}"
        case "$char" in
            '{')
                if [ $brace_count -eq 0 ]; then
                    in_object=true
                    current="{"
                else
                    current="$current{"
                fi
                brace_count=$((brace_count + 1))
                ;;
            '}')
                current="$current}"
                brace_count=$((brace_count - 1))
                if [ $brace_count -eq 0 ] && [ "$in_object" = true ]; then
                    objects+=("$current")
                    in_object=false
                    current=""
                fi
                ;;
            *)
                if [ "$in_object" = true ]; then
                    current="$current$char"
                fi
                ;;
        esac
        i=$((i + 1))
    done
    
    for obj in "${objects[@]}"; do
        echo "$obj"
    done
}

# 从JSON对象字符串中提取字段值（无jq回退辅助函数）
# 支持字符串、数字、数组值
json_extract_field() {
    local json_str="$1"
    local field_name="$2"
    
    # 尝试匹配字符串值: "field":"value"
    local str_val=$(echo "$json_str" | grep -oE "\"${field_name}\":\"[^\"]*\"" | head -n1 | sed 's/^[^:]*://;s/"$//;s/^"//')
    if [[ -n "$str_val" ]]; then
        echo "$str_val"
        return 0
    fi
    
    # 尝试匹配数字值: "field":123
    local num_val=$(echo "$json_str" | grep -oE "\"${field_name}\":[0-9]+" | head -n1 | sed 's/^[^:]*://')
    if [[ -n "$num_val" ]]; then
        echo "$num_val"
        return 0
    fi
    
    # 尝试匹配数组值: "field":["a","b"]
    local arr_val=$(echo "$json_str" | grep -oE "\"${field_name}\":\[[^\]]*\]" | head -n1 | sed 's/^[^:]*:\[\(.*\)\]/\1/' | tr -d '"' | tr ',' ' ')
    if [[ -n "$arr_val" ]]; then
        echo "$arr_val"
        return 0
    fi
    
    echo ""
    return 1
}

# 修复JSON配置文件格式（兼容旧函数名）
fix_json_format() {
    format_json_config "$CONFIG_FILE" "$JSON_FORMAT_ENABLED"
}

# 初始化配置文件
init_config() {
    migrate_old_config
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[]" > "$CONFIG_FILE"
        echo "Debug: Created new JSON config file: $CONFIG_FILE"
    else
        echo "Debug: Config file already exists: $CONFIG_FILE"
        # 修复可能存在的格式问题
        format_json_config "$CONFIG_FILE" "$JSON_FORMAT_ENABLED"
    fi
}

# 添加到配置文件 (JSON格式)
add_to_config() {
    local forward_type=""
    case "$ip_version" in
        1) forward_type="ipv4" ;;
        2) forward_type="ipv6" ;;
        3) forward_type="domain" ;;
        4) forward_type="domain6" ;;
    esac
    
    # 构建protocols JSON数组
    local protocols_json="["
    local first_proto=true
    for proto in "${forward_protocols[@]}"; do
        if $first_proto; then
            protocols_json+="\"$proto\""
            first_proto=false
        else
            protocols_json+=",\"$proto\""
        fi
    done
    protocols_json+="]"
    
    # 转义extra_config中的特殊字符
    local extra_escaped=$(echo "$extra_config" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    # 使用统一格式处理函数添加配置
    local new_entry='{"type":"'$forward_type'","listen_port":'$port1',"remote_ip":"'$socatip'","remote_port":'$port2',"protocols":'$protocols_json',"extra":"'$extra_escaped'"}'
    
    if command -v jq >/dev/null 2>&1; then
        jq ". += [$new_entry]" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        # 回退到简单的JSON数组追加
        local new_entry='{"type":"'$forward_type'","listen_port":'$port1',"remote_ip":"'$socatip'","remote_port":'$port2',"protocols":'$protocols_json',"extra":"'$extra_escaped'"}'
        
        # 确保配置文件存在且为有效的JSON格式
        if [ ! -s "$CONFIG_FILE" ]; then
            echo "[$new_entry]" > "$CONFIG_FILE"
            return
        fi
        
        # 清理现有文件中的空元素和多余逗号
        local temp_file=$(mktemp)
        
        # 读取并清理现有内容
        local content=$(cat "$CONFIG_FILE" | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 移除空数组元素和多余逗号
        content=$(echo "$content" | sed 's/\[,\?\s*\[,\?\s*\]/[]/g')
        content=$(echo "$content" | sed 's/\[,\?\s*,\?\s*\]/[]/g')
        content=$(echo "$content" | sed 's/,,/,/g')
        content=$(echo "$content" | sed 's/\[,\?/[/' | sed 's/\,\?\]/]/')
        
        # 如果是空数组，直接创建新数组
        if [[ "$content" == "[]" ]]; then
            echo "[$new_entry]" > "$CONFIG_FILE"
            rm -f "$temp_file"
            fix_json_format
            return
        fi
        
        # 提取现有对象
        echo "$content" | sed 's/\[\(.*\)\]/\1/' | sed 's/},{/}\n{/g' | while IFS= read -r obj; do
            [[ -n "$obj" && "$obj" != "{" ]] && echo "$obj"
        done > "$temp_file"
        
        # 构建新的JSON数组
        echo "[" > "$CONFIG_FILE"
        
        local first=true
        while IFS= read -r obj; do
            [[ -z "$obj" || "$obj" == "{" ]] && continue
            
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo "," >> "$CONFIG_FILE"
            fi
            
            # 确保对象格式正确
            if [[ "$obj" != *"}" ]]; then
                obj="$obj}"
            fi
            echo -n "$obj" >> "$CONFIG_FILE"
        done < "$temp_file"
        
        # 添加新条目
        if [[ "$first" == "true" ]]; then
            echo "$new_entry]" >> "$CONFIG_FILE"
        else
            echo "," >> "$CONFIG_FILE"
            echo "$new_entry]" >> "$CONFIG_FILE"
        fi
        
        rm -f "$temp_file"
    fi
    
    # 使用统一格式处理函数确保格式正确
    format_json_config "$CONFIG_FILE" "$JSON_FORMAT_ENABLED"
}

# 从配置文件中移除转发 (JSON格式)
remove_from_config() {
    local listen_port=$1
    if command -v jq >/dev/null 2>&1; then
        jq "map(select(.listen_port != $listen_port))" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        # 回退到基于行的处理 - 修复JSON格式问题
        local temp_file=$(mktemp)
        
        # 读取配置文件内容
        local json_content=$(cat "$CONFIG_FILE")
        
        # 提取所有有效的JSON对象
        local entries=()
        local entry_count=$(echo "$json_content" | grep -o '"type"' | wc -l)
        
        # 收集所有非空且端口不匹配的配置项
        local first_entry=true
        echo "[" > "$temp_file"
        
        # 使用更可靠的JSON解析
        local in_entry=false
        local entry=""
        local brace_count=0
        
        while IFS= read -r line; do
            # 跳过空行和仅包含逗号的行
            [[ -z "$line" || "$line" =~ ^[[:space:]]*,[[:space:]]*$ ]] && continue
            
            # 检测JSON对象的开始
            if [[ "$line" =~ ^[[:space:]]*\{ ]]; then
                in_entry=true
                entry=""
                brace_count=1
            fi
            
            if [[ "$in_entry" == "true" ]]; then
                entry="$entry$line"
                # 计算大括号匹配
                brace_count=$(echo "$line" | sed 's/[^{}]//g' | sed 's/{/\n{/g' | sed 's/}/\n}/g' | grep -c '{')
                brace_count=$((brace_count - $(echo "$line" | sed 's/[^{}]//g' | sed 's/{/\n{/g' | sed 's/}/\n}/g' | grep -c '}')))
                
                if [[ $brace_count -eq 0 ]]; then
                    # 完整的JSON对象
                    if [[ "$entry" != *"\"listen_port\":$listen_port"* ]]; then
                        if [[ "$first_entry" == "false" ]]; then
                            echo "," >> "$temp_file"
                        fi
                        echo -n "$entry" >> "$temp_file"
                        first_entry=false
                    fi
                    in_entry=false
                    entry=""
                fi
            fi
        done < <(cat "$CONFIG_FILE" | tr -d '\n' | sed 's/\[/\[\n/g' | sed 's/\]/\n\]/g' | sed 's/},{/},\n{/g')
        
        # 如果没有找到任何有效条目，创建空数组
        if [[ "$first_entry" == "true" ]]; then
            echo "]" > "$temp_file"
        else
            echo "" >> "$temp_file"
            echo "]" >> "$temp_file"
        fi
        
        # 清理生成的JSON
        sed -i 's/,,/,/g' "$temp_file"  # 移除重复逗号
        sed -i 's/\[,/[/' "$temp_file"   # 修复开头
        sed -i 's/,\]/]/' "$temp_file"   # 修复结尾
        
        mv "$temp_file" "$CONFIG_FILE"
        # 使用统一格式处理函数确保格式正确
        format_json_config "$CONFIG_FILE" "$JSON_FORMAT_ENABLED"
    fi
}

# 端口占用检测
check_port() {
    local port=$1
    local protocol=${2:-"tcp"}
    
    # SCTP等非TCP/UDP协议，跳过检测
    if [[ "$protocol" != "tcp" && "$protocol" != "udp" ]]; then
        return 0
    fi
    
    local proto_flag="${protocol:0:1}"
    
    # 使用ss命令（优先）
    if command -v ss >/dev/null 2>&1; then
        if ss -${proto_flag}ln | grep -q ":${port} "; then
            local process=$(ss -${proto_flag}lnp | grep ":${port} " | awk '{print $7}' | cut -d',' -f1 | cut -d'"' -f2 | head -n1)
            echo -e "${Red}错误: 端口 $1 已被占用 (${process:-未知进程})${Font}"
            return 1
        fi
    # 备选使用netstat
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -${proto_flag}ln | grep -q ":${port} "; then
            local process=$(netstat -${proto_flag}lnp | grep ":${port} " | awk '{print $7}' | cut -d'/' -f2 | head -n1)
            echo -e "${Red}错误: 端口 $1 已被占用 (${process:-未知进程})${Font}"
            return 1
        fi
    fi
    
    return 0
}

# 规范化 IPv6 地址
normalize_ipv6() {
    local ip=$1
    
    # 使用系统工具标准化IPv6地址
    if command -v ipcalc >/dev/null 2>&1; then
        local normalized=$(ipcalc -i "$ip" 2>/dev/null | grep -oE '([0-9a-fA-F]{1,4}:){1,7}[0-9a-fA-F]{1,4}' | head -n1)
        [[ -n "$normalized" ]] && echo "$normalized" && return
    fi
    
    # 备选方案：使用python3
    if command -v python3 >/dev/null 2>&1; then
        local normalized=$(python3 -c "
import ipaddress
import sys
try:
    ip = ipaddress.IPv6Address('$ip')
    print(str(ip))
except:
    sys.exit(1)
" 2>/dev/null)
        [[ -n "$normalized" ]] && echo "$normalized" && return
    fi
    
    # 最后备选：简化处理
    echo "$ip"
}

# 检查是否支持IPv6
check_ipv6_support() {
    # 检查内核IPv6支持
    if [[ ! -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]]; then
        echo -e "${Red}错误: 您的内核不支持 IPv6${Font}"
        return 1
    fi
    
    # 检查IPv6模块是否加载
    if ! lsmod | grep -q ipv6; then
        echo -e "${Yellow}警告: IPv6 模块未加载，尝试加载...${Font}"
        modprobe ipv6 2>/dev/null || {
            echo -e "${Red}无法加载 IPv6 模块${Font}"
            return 1
        }
    fi
    
    # 检查并启用IPv6
    if [[ $(cat /proc/sys/net/ipv6/conf/all/disable_ipv6) -eq 1 ]]; then
        echo -e "${Yellow}警告: IPv6 当前被禁用${Font}"
        read -p "是否要启用 IPv6? (y/n): " enable_ipv6
        if [[ $enable_ipv6 =~ ^[Yy]$ ]]; then
            # 启用IPv6
            sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
            sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1
            echo "net.ipv6.conf.all.disable_ipv6=0" >> /etc/sysctl.conf
            echo "net.ipv6.conf.default.disable_ipv6=0" >> /etc/sysctl.conf
            echo -e "${Green}IPv6 已启用${Font}"
        else
            echo -e "${Red}IPv6 保持禁用状态，无法进行 IPv6 转发${Font}"
            return 1
        fi
    fi
    
    # 检查网络接口IPv6地址
    local ipv6_addr=""
    if command -v ip >/dev/null 2>&1; then
        ipv6_addr=$(ip -6 addr show scope global 2>/dev/null | grep -oE 'inet6 ([0-9a-fA-F:]+)' | awk '{print $2}' | cut -d'/' -f1 | grep -v '^::1' | head -n1)
    fi
    
    if [[ -z "$ipv6_addr" ]]; then
        echo -e "${Red}错误: 未检测到可用的 IPv6 地址${Font}"
        echo -e "${Yellow}请确保您的网络接口已配置 IPv6 地址${Font}"
        return 1
    else
        echo -e "${Green}检测到 IPv6 地址: $ipv6_addr${Font}"
    fi
    
    # 检查并启用IPv6转发
    if [[ $(cat /proc/sys/net/ipv6/conf/all/forwarding) -eq 0 ]]; then
        echo -e "${Yellow}警告: IPv6 转发当前被禁用${Font}"
        read -p "是否要启用 IPv6 转发? (y/n): " enable_forwarding
        if [[ $enable_forwarding =~ ^[Yy]$ ]]; then
            sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1
            sysctl -w net.ipv6.conf.default.forwarding=1 >/dev/null 2>&1
            echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.default.forwarding=1" >> /etc/sysctl.conf
            echo -e "${Green}IPv6 转发已启用${Font}"
        else
            echo -e "${Yellow}IPv6 转发保持禁用状态，可能影响转发功能${Font}"
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
    read -p "请输入选项 [1-4] (回车返回主菜单): " ip_version
    
    # 检查空输入，回车返回主菜单
    if [[ -z "$ip_version" ]]; then
        echo -e "${Yellow}已取消操作，返回主菜单...${Font}"
        return 1
    fi

    if [ "$ip_version" == "2" ] || [ "$ip_version" == "4" ]; then
        if ! check_ipv6_support; then
            echo -e "${Red}无法进行 IPv6 转发，请检查系统配置${Font}"
            return 1
        fi
    fi

    # 选择转发协议
    echo
    echo -e "${Green}请选择转发协议：${Font}"
    echo "1. TCP + UDP（默认）"
    echo "   用途：同时支持 TCP 和 UDP 流量转发，如 SSH、游戏服务器、DNS 等"
    echo "2. 仅 TCP"
    echo "   用途：仅转发 TCP 流量，如 HTTP/HTTPS 网站、SSH、SMTP 等"
    echo "3. 仅 UDP"
    echo "   用途：仅转发 UDP 流量，如 DNS、音视频流媒体、游戏等"
    echo "4. SCTP（流控制传输协议）"
    echo "   用途：支持多流、多宿的传输协议，类似 TCP+多路复用，适合电话信令等"
    echo "5. SSL/TLS 加密转发"
    echo "   用途：加密 TCP 转发，数据全程加密，防止中间人窃听"
    echo "6. UNIX 域套接字"
    echo "   用途：将 TCP 端口与本地 UNIX socket 互转，常用于容器/进程通信"
    echo "7. SOCKS4A 代理转发"
    echo "   用途：通过 SOCKS 代理服务器转发，支持域名解析在代理端完成"
    echo "8. HTTP PROXY 代理转发"
    echo "   用途：通过 HTTP CONNECT 代理转发，适合 HTTP/HTTPS 流量"
    while true; do
        read -p "请输入选项 [1-8] (默认1): " proto_choice
        proto_choice=${proto_choice:-1}
        case "$proto_choice" in
            1|2|3|4|5|6|7|8) break ;;
            *) echo -e "${Red}无效选项，请重新选择${Font}" ;;
        esac
    done
    
    # 初始化协议列表和额外参数
    forward_protocols=()
    extra_config=""
    
    case "$proto_choice" in
        1)
            forward_protocols=("tcp" "udp")
            ;;
        2)
            forward_protocols=("tcp")
            ;;
        3)
            forward_protocols=("udp")
            ;;
        4)
            forward_protocols=("sctp")
            ;;
        5)
            forward_protocols=("openssl")
            generate_ssl_cert
            ;;
        6)
            forward_protocols=("unix")
            echo
            echo -e "${Green}请选择UNIX套接字方向：${Font}"
            echo "1. TCP端口 -> UNIX套接字（连接已有UNIX socket）"
            echo "2. UNIX套接字 -> TCP端口（创建UNIX socket监听）"
            while true; do
                read -p "请输入选项 [1-2] (默认1): " unix_dir
                unix_dir=${unix_dir:-1}
                case "$unix_dir" in
                    1|2) break ;;
                    *) echo -e "${Red}无效选项${Font}" ;;
                esac
            done
            while true; do
                read -p "请输入UNIX套接字路径: " unix_path
                if [[ -n "$unix_path" && "$unix_path" == /* ]]; then
                    if [ "$unix_dir" == "1" ]; then
                        # TCP -> UNIX
                        extra_config="tcp2unix:${unix_path}"
                        socatip="${unix_path}"
                    else
                        # UNIX -> TCP
                        extra_config="unix2tcp:${unix_path}"
                        socatip="127.0.0.1"
                    fi
                    break
                else
                    echo -e "${Red}请输入有效的绝对路径${Font}"
                fi
            done
            ;;
        7)
            forward_protocols=("socks")
            while true; do
                read -p "请输入SOCKS代理地址:端口 (如 127.0.0.1:1080): " socks_addr
                if [[ "$socks_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
                    extra_config="$socks_addr"
                    break
                else
                    echo -e "${Red}格式错误，请使用 地址:端口 格式${Font}"
                fi
            done
            ;;
        8)
            forward_protocols=("proxy")
            while true; do
                read -p "请输入HTTP代理地址:端口 (如 127.0.0.1:8080): " proxy_addr
                if [[ "$proxy_addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
                    extra_config="$proxy_addr"
                    break
                else
                    echo -e "${Red}格式错误，请使用 地址:端口 格式${Font}"
                fi
            done
            ;;
    esac

    echo
    echo -e "${Green}请输入Socat配置信息！${Font}"
    
    # UNIX套接字模式跳过部分输入
    if [ "$proto_choice" != "6" ]; then
        while true; do
            read -p "请输入本地端口 (留空随机分配): " port1
            if [[ -z "$port1" ]]; then
                echo -e "${Yellow}正在为您分配随机端口...${Font}"
                port1=$(get_random_unused_port)
                if [[ -n "$port1" ]]; then
                    echo -e "${Green}已分配随机端口: $port1${Font}"
                    break
                else
                    continue
                fi
            elif [[ "$port1" =~ ^[0-9]+$ ]] && [[ $port1 -ge 1 ]] && [[ $port1 -le 65535 ]]; then
                if check_port $port1; then
                    break
                fi
            else
                echo -e "${Red}错误: 请输入1-65535之间的有效端口号${Font}"
            fi
        done
    else
        # UNIX模式的端口处理
        if [ "$unix_dir" == "1" ]; then
            # TCP -> UNIX：需要本地监听端口
            while true; do
                read -p "请输入本地监听端口 (留空随机分配): " port1
                if [[ -z "$port1" ]]; then
                    port1=$(get_random_unused_port)
                    echo -e "${Green}已分配随机端口: $port1${Font}"
                    break
                elif [[ "$port1" =~ ^[0-9]+$ ]] && [[ $port1 -ge 1 ]] && [[ $port1 -le 65535 ]]; then
                    if check_port $port1; then
                        break
                    fi
                else
                    echo -e "${Red}错误: 请输入1-65535之间的有效端口号${Font}"
                fi
            done
            port2=0  # 远程端口用0占位
        else
            # UNIX -> TCP：需要目标TCP端口
            port1=0  # 本地端口用0占位（UNIX socket路径作标识）
            while true; do
                read -p "请输入目标TCP端口 (127.0.0.1): " port2
                if [[ "$port2" =~ ^[0-9]+$ ]] && [[ $port2 -ge 1 ]] && [[ $port2 -le 65535 ]]; then
                    break
                else
                    echo -e "${Red}错误: 请输入1-65535之间的有效端口号${Font}"
                fi
            done
        fi
    fi
    
    # 非UNIX模式下，输入远程端口和地址
    if [ "$proto_choice" != "6" ]; then
        while true; do
            read -p "请输入远程端口: " port2
            if [[ -z "$port2" ]]; then
                echo -e "${Red}错误: 远程端口不能为空${Font}"
                continue
            elif [[ "$port2" =~ ^[0-9]+$ ]] && [[ $port2 -ge 1 ]] && [[ $port2 -le 65535 ]]; then
                break
            else
                echo -e "${Red}错误: 请输入1-65535之间的有效端口号${Font}"
            fi
        done
        
        if [ "$ip_version" == "3" ] || [ "$ip_version" == "4" ]; then
            while true; do
                read -p "请输入远程域名: " socatip
                if validate_domain_name "$socatip"; then
                    break
                fi
            done
        else
            while true; do
                read -p "请输入远程IP: " socatip
                if validate_ip_address "$socatip" "$ip_version"; then
                    if [ "$ip_version" == "2" ]; then
                        socatip=$(normalize_ipv6 "$socatip")
                    fi
                    break
                fi
            done
        fi
    else
        # UNIX模式：socatip 和 extra_config 已在上面设置完毕
        :
    fi
}

# IP地址验证函数
validate_ip_address() {
    local ip=$1
    local ip_version=$2
    
    case "$ip_version" in
        1)
            if ! [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo -e "${Red}错误: 无效的IPv4地址格式${Font}"
                return 1
            fi
            ;;
        2)
            if ! [[ $ip =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
                echo -e "${Red}错误: 无效的IPv6地址格式${Font}"
                return 1
            fi
            ;;
    esac
    return 0
}

# 域名验证函数
validate_domain_name() {
    local domain=$1
    
    if ! [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo -e "${Red}错误: 无效的域名格式${Font}"
        return 1
    fi
    
    # 尝试解析域名
    if ! host "$domain" >/dev/null 2>&1 && ! nslookup "$domain" >/dev/null 2>&1 && ! dig "$domain" >/dev/null 2>&1; then
        echo -e "${Red}错误: 无法解析域名${Font}"
        return 1
    fi
    
    return 0
}

# 获取随机未使用的端口
get_random_unused_port() {
    local min_port=1024
    local max_port=65535
    local max_attempts=100
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        local port=$((RANDOM % (max_port - min_port + 1) + min_port))
        if check_port $port; then
            echo $port
            return 0
        fi
        ((attempts++))
    done
    
    echo -e "${Red}错误: 无法找到可用的随机端口${Font}"
    return 1
}

# 创建 systemd 服务文件
create_systemd_service() {
    local name=$1
    local command=$2
    
    # 检查服务是否已存在且正在运行，若运行则先停止
    if systemctl is-active --quiet "$name" 2>/dev/null; then
        systemctl stop "$name" 2>/dev/null
    fi
    
    cat > /etc/systemd/system/${name}.service <<EOF
[Unit]
Description=Socat Forwarding Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$command
Restart=on-failure
RestartSec=5
StartLimitInterval=60
StartLimitBurst=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ${name}.service
    systemctl start ${name}.service
}

# 生成SSL自签名证书
generate_ssl_cert() {
    local ssl_dir="$SOCATS_DIR/ssl"
    local cert_file="$ssl_dir/server.crt"
    local key_file="$ssl_dir/server.key"
    
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        return 0
    fi
    
    mkdir -p "$ssl_dir"
    
    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "${Yellow}未检测到openssl，正在安装...${Font}"
        case "$PKG_MANAGER" in
            apt) apt-get install -y openssl >/dev/null 2>&1 ;;
            yum) yum install -y openssl >/dev/null 2>&1 ;;
            dnf) dnf install -y openssl >/dev/null 2>&1 ;;
            pacman) pacman -S --noconfirm openssl >/dev/null 2>&1 ;;
        esac
    fi
    
    openssl req -x509 -newkey rsa:2048 -keyout "$key_file" -out "$cert_file" \
        -days 3650 -nodes -subj "/CN=socat-forward" >/dev/null 2>&1
    
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        echo -e "${Green}SSL证书生成成功${Font}"
        return 0
    else
        echo -e "${Red}SSL证书生成失败${Font}"
        return 1
    fi
}

# 创建单个Socat服务
create_single_socat_service() {
    local protocol=$1  # tcp/udp/sctp/openssl/unix/socks/proxy
    local ip_version=$2  # 4/6/domain/domain6
    local listen_port=$3
    local target_ip=$4
    local target_port=$5
    local extra=$6  # 额外参数：UNIX socket路径/代理地址等
    
    local service_name="socat-${listen_port}-${target_port}-${protocol}"
    local socat_cmd=""
    
    # UNIX 协议：根据方向和路径生成唯一服务名
    if [ "$protocol" == "unix" ]; then
        # 解析extra获取路径
        local unix_path=""
        if [[ "$extra" == tcp2unix:* ]] || [[ "$extra" == unix2tcp:* ]]; then
            unix_path="${extra#*:}"
        elif [[ "$extra" == /* ]]; then
            unix_path="$extra"
        else
            unix_path="$target_ip"
        fi
        
        # 用路径的basename和端口组合生成服务名，避免冲突
        local path_suffix=$(basename "$unix_path")
        # 替换特殊字符
        path_suffix=$(echo "$path_suffix" | tr '/.' '_')
        
        if [ "$listen_port" == "0" ]; then
            # UNIX -> TCP 模式
            service_name="socat-unix-${path_suffix}-${target_port}-unix"
        else
            # TCP -> UNIX 模式
            service_name="socat-${listen_port}-unix-${path_suffix}-unix"
        fi
    fi
    
    # TCP 通用选项
    local tcp_common_opts="reuseaddr,fork,so-keepalive,so-sndbuf=1048576,so-rcvbuf=1048576"
    
    # SSL证书路径
    local ssl_cert="$SOCATS_DIR/ssl/server.crt"
    local ssl_key="$SOCATS_DIR/ssl/server.key"
    
    # 根据协议和IP版本构建socat命令
    case "$protocol" in
        tcp)
            if [ "$ip_version" == "4" ]; then
                socat_cmd="/usr/bin/socat TCP4-LISTEN:${listen_port},${tcp_common_opts} TCP4:${target_ip}:${target_port},connect-timeout=10"
            elif [ "$ip_version" == "6" ]; then
                socat_cmd="/usr/bin/socat TCP6-LISTEN:${listen_port},${tcp_common_opts} TCP6:${target_ip}:${target_port},connect-timeout=10"
            elif [ "$ip_version" == "domain" ]; then
                socat_cmd="/usr/bin/socat TCP4-LISTEN:${listen_port},${tcp_common_opts} TCP:${target_ip}:${target_port},connect-timeout=10"
            elif [ "$ip_version" == "domain6" ]; then
                socat_cmd="/usr/bin/socat TCP6-LISTEN:${listen_port},${tcp_common_opts} TCP6:${target_ip}:${target_port},connect-timeout=10"
            fi
            ;;
        udp)
            if [ "$ip_version" == "4" ]; then
                socat_cmd="/usr/bin/socat UDP4-LISTEN:${listen_port},reuseaddr,fork,so-sndbuf=1048576,so-rcvbuf=1048576 UDP4:${target_ip}:${target_port}"
            elif [ "$ip_version" == "6" ]; then
                socat_cmd="/usr/bin/socat UDP6-LISTEN:${listen_port},reuseaddr,fork,so-sndbuf=1048576,so-rcvbuf=1048576 UDP6:${target_ip}:${target_port}"
            elif [ "$ip_version" == "domain" ]; then
                socat_cmd="/usr/bin/socat UDP4-LISTEN:${listen_port},reuseaddr,fork,so-sndbuf=1048576,so-rcvbuf=1048576 UDP:${target_ip}:${target_port}"
            elif [ "$ip_version" == "domain6" ]; then
                socat_cmd="/usr/bin/socat UDP6-LISTEN:${listen_port},reuseaddr,fork,so-sndbuf=1048576,so-rcvbuf=1048576 UDP6:${target_ip}:${target_port}"
            fi
            ;;
        sctp)
            if [ "$ip_version" == "4" ]; then
                socat_cmd="/usr/bin/socat SCTP4-LISTEN:${listen_port},reuseaddr,fork SCTP4:${target_ip}:${target_port},connect-timeout=10"
            elif [ "$ip_version" == "6" ]; then
                socat_cmd="/usr/bin/socat SCTP6-LISTEN:${listen_port},reuseaddr,fork SCTP6:${target_ip}:${target_port},connect-timeout=10"
            elif [ "$ip_version" == "domain" ]; then
                socat_cmd="/usr/bin/socat SCTP4-LISTEN:${listen_port},reuseaddr,fork SCTP:${target_ip}:${target_port},connect-timeout=10"
            elif [ "$ip_version" == "domain6" ]; then
                socat_cmd="/usr/bin/socat SCTP6-LISTEN:${listen_port},reuseaddr,fork SCTP6:${target_ip}:${target_port},connect-timeout=10"
            fi
            ;;
        openssl)
            if [ "$ip_version" == "4" ]; then
                socat_cmd="/usr/bin/socat OPENSSL-LISTEN:${listen_port},reuseaddr,fork,cert=${ssl_cert},key=${ssl_key},verify=0 TCP4:${target_ip}:${target_port},connect-timeout=10"
            elif [ "$ip_version" == "6" ]; then
                socat_cmd="/usr/bin/socat OPENSSL-LISTEN:${listen_port},reuseaddr,fork,cert=${ssl_cert},key=${ssl_key},verify=0,pf=ip6 TCP6:${target_ip}:${target_port},connect-timeout=10"
            elif [ "$ip_version" == "domain" ]; then
                socat_cmd="/usr/bin/socat OPENSSL-LISTEN:${listen_port},reuseaddr,fork,cert=${ssl_cert},key=${ssl_key},verify=0 TCP:${target_ip}:${target_port},connect-timeout=10"
            elif [ "$ip_version" == "domain6" ]; then
                socat_cmd="/usr/bin/socat OPENSSL-LISTEN:${listen_port},reuseaddr,fork,cert=${ssl_cert},key=${ssl_key},verify=0,pf=ip6 TCP6:${target_ip}:${target_port},connect-timeout=10"
            fi
            ;;
        unix)
            # extra 格式：tcp2unix:/path 或 unix2tcp:/path （新格式）
            # 兼容旧格式：/path （纯路径，需通过target_ip判断）
            local unix_path=""
            local unix_direction=""  # tcp2unix 或 unix2tcp
            
            if [[ "$extra" == tcp2unix:* ]]; then
                unix_direction="tcp2unix"
                unix_path="${extra#tcp2unix:}"
            elif [[ "$extra" == unix2tcp:* ]]; then
                unix_direction="unix2tcp"
                unix_path="${extra#unix2tcp:}"
            elif [[ "$extra" == /* ]]; then
                # 旧格式兼容：纯路径
                unix_path="$extra"
                # 通过 target_ip 判断方向
                # - 如果 target_ip 等于 extra 路径本身：TCP->UNIX（target_ip存的是socket路径）
                # - 如果 target_ip 是 "127.0.0.1" 或 "127.0.0.1:端口"：UNIX->TCP
                if [[ "$target_ip" == "$extra" ]]; then
                    unix_direction="tcp2unix"
                elif [[ "$target_ip" == "127.0.0.1" ]]; then
                    unix_direction="unix2tcp"
                elif [[ "$target_ip" == 127.0.0.1:* ]]; then
                    # 旧格式：127.0.0.1:端口
                    unix_direction="unix2tcp"
                else
                    unix_direction="tcp2unix"  # 默认TCP->UNIX
                fi
            else
                # 兼容最老配置：extra 不存在，target_ip 是路径
                unix_path="$target_ip"
                unix_direction="tcp2unix"
            fi
            
            if [[ "$unix_direction" == "unix2tcp" ]]; then
                # UNIX -> TCP 模式
                socat_cmd="/usr/bin/socat UNIX-LISTEN:${unix_path},reuseaddr,fork,unlink-early TCP4:127.0.0.1:${target_port},connect-timeout=10"
            else
                # TCP -> UNIX 模式
                socat_cmd="/usr/bin/socat TCP4-LISTEN:${listen_port},${tcp_common_opts} UNIX-CONNECT:${unix_path}"
            fi
            ;;
        socks)
            local socks_host="${extra%%:*}"
            local socks_port="${extra##*:}"
            socat_cmd="/usr/bin/socat TCP4-LISTEN:${listen_port},${tcp_common_opts} SOCKS4A:${socks_host}:${target_ip}:${target_port},socksport=${socks_port}"
            ;;
        proxy)
            local proxy_host="${extra%%:*}"
            local proxy_port="${extra##*:}"
            socat_cmd="/usr/bin/socat TCP4-LISTEN:${listen_port},${tcp_common_opts} PROXY:${proxy_host}:${target_ip}:${target_port},proxyport=${proxy_port}"
            ;;
        *)
            echo -e "${Red}不支持的协议: $protocol${Font}"
            return 1
            ;;
    esac
    
    create_systemd_service "$service_name" "$socat_cmd"
    
    # 输出服务名，供调用方捕获
    echo "$service_name"
}

# 启动Socat - 重构后的版本
start_socat(){
    echo -e "${Green}正在配置Socat...${Font}"

    local ip_type_num=""
    local firewall_type=""
    
    # 根据IP版本类型设置参数
    case "$ip_version" in
        1)
            ip_type_num="4"
            firewall_type="ipv4"
            ;;
        2)
            ip_type_num="6"
            firewall_type="ipv6"
            ;;
        3)
            ip_type_num="domain"
            firewall_type="ipv4"
            ;;
        4)
            ip_type_num="domain6"
            firewall_type="ipv6"
            ;;
        *)
            echo -e "${Red}无效的选项，退出配置。${Font}"
            return 1
            ;;
    esac
    
    # 根据 forward_protocols 数组创建对应协议的服务
    local service_names=()
    for proto in "${forward_protocols[@]}"; do
        local svc_name=$(create_single_socat_service "$proto" "$ip_type_num" "$port1" "$socatip" "$port2" "$extra_config")
        service_names+=("$svc_name")
    done
    
    # 如果是域名类型，设置监控（仅TCP类协议有效，排除UNIX和代理协议）
    if [ "$ip_version" == "3" ] || [ "$ip_version" == "4" ]; then
        if [[ " ${forward_protocols[*]} " =~ " tcp " ]] || [[ " ${forward_protocols[*]} " =~ " openssl " ]] || [[ " ${forward_protocols[*]} " =~ " sctp " ]]; then
            if [[ ! " ${forward_protocols[*]} " =~ " socks " ]] && [[ ! " ${forward_protocols[*]} " =~ " proxy " ]]; then
                setup_domain_monitor "$socatip" "$port1" "$ip_type_num" "$port2" "${forward_protocols[*]}"
            fi
        fi
    fi

    sleep 2
    
    # 检查所有服务是否正常运行
    local all_running=true
    local failed_services=()
    for svc in "${service_names[@]}"; do
        if ! systemctl is-active --quiet "$svc"; then
            all_running=false
            failed_services+=("$svc")
        fi
    done
    
    if $all_running; then
        echo -e "${Green}Socat配置成功!${Font}"
        
        # 显示协议信息
        echo -e "${Blue}协议: ${forward_protocols[*]}${Font}"
        
        # UNIX模式特殊显示
        if [[ " ${forward_protocols[*]} " =~ " unix " ]]; then
            # 提取实际的socket路径
            local display_path="${extra_config#tcp2unix:}"
            display_path="${display_path#unix2tcp:}"
            echo -e "${Blue}UNIX套接字路径: ${display_path}${Font}"
            if [[ "$extra_config" == tcp2unix:* ]]; then
                echo -e "${Blue}方向: TCP端口 ${port1} -> UNIX套接字${Font}"
            else
                echo -e "${Blue}方向: UNIX套接字 -> 127.0.0.1:${port2}${Font}"
            fi
        else
            echo -e "${Blue}本地端口: ${port1}${Font}"
            echo -e "${Blue}远程端口: ${port2}${Font}"
            echo -e "${Blue}远程地址: ${socatip}${Font}"
        fi
        
        # 代理模式额外显示
        if [[ " ${forward_protocols[*]} " =~ " socks " ]] || [[ " ${forward_protocols[*]} " =~ " proxy " ]]; then
            echo -e "${Blue}代理地址: ${extra_config}${Font}"
        fi
        
        # 统一的显示信息
        local local_addr="$ip"
        [[ "$ip_version" == "2" ]] && [[ -n "$ipv6" ]] && local_addr="$ipv6"
        case "$ip_version" in
            1)
                echo -e "${Blue}本地服务器IP: ${ip}${Font}"
                echo -e "${Blue}IP版本: IPv4${Font}"
                ;;
            2)
                echo -e "${Blue}本地服务器IPv6: ${ipv6:-未检测到}${Font}"
                echo -e "${Blue}IP版本: IPv6${Font}"
                ;;
            3)
                echo -e "${Blue}本地服务器IP: ${ip}${Font}"
                echo -e "${Blue}地址类型: 域名 (DDNS, IPv4优先)${Font}"
                echo -e "${Blue}域名监控: 已启用 (每5分钟自动检查IP变更)${Font}"
                ;;
            4)
                echo -e "${Blue}本地服务器IPv6: ${ipv6:-未检测到}${Font}"
                echo -e "${Blue}地址类型: 域名 (DDNS, IPv6优先)${Font}"
                echo -e "${Blue}域名监控: 已启用 (每5分钟自动检查IP变更)${Font}"
                ;;
        esac

        add_to_config
        # UNIX套接字模式不需要配置防火墙
        if [[ ! " ${forward_protocols[*]} " =~ " unix " ]]; then
            configure_firewall ${port1} "$firewall_type" "${forward_protocols[*]}"
        fi
        return 0
    else
        echo -e "${Red}Socat启动失败，请检查系统日志。${Font}"
        echo -e "${Red}失败的服务: ${failed_services[*]}${Font}"
        for svc in "${failed_services[@]}"; do
            journalctl -u "$svc" --no-pager -n 20
            echo "---"
        done
        return 1
    fi
}

# 显示和删除转发
view_delete_forward() {
    clear_screen
    
    # 检查配置文件是否存在或是否为空
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${Red}当前没有活动的转发。${Font}"
        return
    fi
    
    # 检查配置内容是否为空数组
    local config_content=$(cat "$CONFIG_FILE" | tr -d '[:space:]')
    if [ -z "$config_content" ] || [ "$config_content" = "[]" ]; then
        echo -e "${Red}当前没有活动的转发。${Font}"
        return
    fi

    echo -e "${Green}当前转发列表:${Font}"
    local i=1
    local entries=()
    
    if command -v jq >/dev/null 2>&1; then
        # 使用jq解析JSON配置
        local configs=$(jq -c '.[]' "$CONFIG_FILE")
        while IFS= read -r config; do
            local ip_type=$(echo "$config" | jq -r '.type')
            local listen_port=$(echo "$config" | jq -r '.listen_port')
            local remote_ip=$(echo "$config" | jq -r '.remote_ip')
            local remote_port=$(echo "$config" | jq -r '.remote_port')
            local protocols_raw=$(echo "$config" | jq -r '.protocols // empty')
            local extra_raw=$(echo "$config" | jq -r '.extra // empty')
            
            # 兼容旧配置：没有protocols字段时默认tcp+udp
            local proto_display="TCP/UDP"
            if [[ -n "$protocols_raw" && "$protocols_raw" != "null" ]]; then
                proto_display=$(echo "$protocols_raw" | tr -d '[]"' | sed 's/,/ \/ /g' | tr 'a-z' 'A-Z')
            fi
            
            # 使用 | 分隔符存储，避免 extra 中空格导致解析错误
            entries+=("$ip_type|$listen_port|$remote_ip|$remote_port|$protocols_raw|$extra_raw")
            local local_ipv6="${ipv6:-未检测到}"
            case "$ip_type" in
                "ipv4")
                    echo "$i. IPv4: $ip:$listen_port --> $remote_ip:$remote_port ($proto_display)"
                    ;;
                "ipv6")
                    echo "$i. IPv6: [$local_ipv6]:$listen_port --> [$remote_ip]:$remote_port ($proto_display)"
                    ;;
                "domain")
                    echo "$i. IPv4 域名: $ip:$listen_port --> $remote_ip:$remote_port ($proto_display) [DDNS, IPv4]"
                    ;;
                "domain6")
                    echo "$i. IPv6 域名: [$local_ipv6]:$listen_port --> $remote_ip:$remote_port ($proto_display) [DDNS, IPv6]"
                    ;;
            esac
            # 显示extra信息（如果有）
            if [[ -n "$extra_raw" && "$extra_raw" != "null" && -n "$extra_raw" ]]; then
                if [[ "$extra_raw" == tcp2unix:* ]] || [[ "$extra_raw" == unix2tcp:* ]]; then
                    local display_unix="${extra_raw#*:}"
                    local dir_label="TCP->UNIX"
                    [[ "$extra_raw" == unix2tcp:* ]] && dir_label="UNIX->TCP"
                    echo "   UNIX套接字: $display_unix ($dir_label)"
                elif [[ "$extra_raw" == /* ]]; then
                    echo "   UNIX套接字: $extra_raw"
                elif [[ "$extra_raw" == *:* && "$extra_raw" != tcp2unix:* && "$extra_raw" != unix2tcp:* ]]; then
                    echo "   代理: $extra_raw"
                fi
            fi
            ((i++))
        done <<< "$configs"
    else
        # 回退到基于字符解析的JSON提取
        local configs=$(json_extract_objects "$CONFIG_FILE")
        
        while IFS= read -r config; do
            [[ -z "$config" ]] && continue
            
            local ip_type=$(json_extract_field "$config" "type")
            local listen_port=$(json_extract_field "$config" "listen_port")
            local remote_ip=$(json_extract_field "$config" "remote_ip")
            local remote_port=$(json_extract_field "$config" "remote_port")
            local protocols_raw=$(json_extract_field "$config" "protocols")
            local extra_raw=$(json_extract_field "$config" "extra")
            
            [ -z "$ip_type" ] && continue
            
            local proto_display="TCP/UDP"
            if [[ -n "$protocols_raw" ]]; then
                proto_display=$(echo "$protocols_raw" | tr ' ' '/' | tr 'a-z' 'A-Z')
            fi
            
            # 使用 | 分隔符存储，避免 extra 中空格导致解析错误
            entries+=("$ip_type|$listen_port|$remote_ip|$remote_port|$protocols_raw|$extra_raw")
            local local_ipv6="${ipv6:-未检测到}"
            case "$ip_type" in
                "ipv4")
                    echo "$i. IPv4: $ip:$listen_port --> $remote_ip:$remote_port ($proto_display)"
                    ;;
                "ipv6")
                    echo "$i. IPv6: [$local_ipv6]:$listen_port --> [$remote_ip]:$remote_port ($proto_display)"
                    ;;
                "domain")
                    echo "$i. IPv4 域名: $ip:$listen_port --> $remote_ip:$remote_port ($proto_display) [DDNS, IPv4]"
                    ;;
                "domain6")
                    echo "$i. IPv6 域名: [$local_ipv6]:$listen_port --> $remote_ip:$remote_port ($proto_display) [DDNS, IPv6]"
                    ;;
            esac
            # 显示extra信息
            if [[ -n "$extra_raw" ]]; then
                if [[ "$extra_raw" == tcp2unix:* ]] || [[ "$extra_raw" == unix2tcp:* ]]; then
                    local display_unix="${extra_raw#*:}"
                    local dir_label="TCP->UNIX"
                    [[ "$extra_raw" == unix2tcp:* ]] && dir_label="UNIX->TCP"
                    echo "   UNIX套接字: $display_unix ($dir_label)"
                elif [[ "$extra_raw" == /* ]]; then
                    echo "   UNIX套接字: $extra_raw"
                elif [[ "$extra_raw" == *:* && "$extra_raw" != tcp2unix:* && "$extra_raw" != unix2tcp:* ]]; then
                    echo "   代理: $extra_raw"
                fi
            fi
            ((i++))
        done <<< "$configs"
    fi

    read -p "请输入要删除的转发编号（多个编号用空格分隔，直接回车取消）: " numbers
    if [ -n "$numbers" ]; then
        local nums_to_delete=($(echo "$numbers" | tr ' ' '\n' | sort -rn))
        for num in "${nums_to_delete[@]}"; do
            if [ $num -ge 1 ] && [ $num -lt $i ]; then
                local index=$((num-1))
                local entry_str="${entries[$index]}"
                IFS='|' read -r ip_type listen_port remote_ip remote_port protocols_raw extra_raw <<< "$entry_str"
                
                # 解析协议列表用于显示
                local proto_display="TCP/UDP"
                if [[ -n "$protocols_raw" && "$protocols_raw" != "null" ]]; then
                    proto_display=$(echo "$protocols_raw" | tr -d '[]"' | sed 's/,/ \/ /g' | tr 'a-z' 'A-Z')
                fi
                
                remove_forward "$listen_port" "$ip_type" "$protocols_raw" "$extra_raw"
                
                # 从JSON配置中删除（精确匹配，避免误删）
                if command -v jq >/dev/null 2>&1; then
                    # 有jq时，使用 listen_port + extra 组合精确匹配
                    if [[ -n "$extra_raw" && "$extra_raw" != "null" ]]; then
                        jq --arg port "$listen_port" --arg extra "$extra_raw" \
                            'del(.[] | select(.listen_port == ($port | tonumber) and .extra == $extra))' \
                            "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                    else
                        jq --arg port "$listen_port" 'del(.[] | select(.listen_port == ($port | tonumber)))' \
                            "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                    fi
                else
                    # 回退到基于行的删除 - 使用更精确的匹配
                    local json_content=$(cat "$CONFIG_FILE")
                    # 构造匹配模式：包含 listen_port 和 extra（如果有）
                    local pattern='"listen_port":'$listen_port
                    if [[ -n "$extra_raw" ]]; then
                        # 转义 extra_raw 中的特殊字符用于 sed
                        local escaped_extra=$(echo "$extra_raw" | sed 's/[&/\]/\\&/g')
                        pattern="${pattern}[^}]*\"extra\":\"${escaped_extra}\""
                    fi
                    local new_content=$(echo "$json_content" | sed "s/{[^}]*${pattern}[^}]*},\?//g")
                    echo "$new_content" > "$CONFIG_FILE"
                fi
                
                local local_ipv6="${ipv6:-未检测到}"
                case "$ip_type" in
                    "ipv4")
                        echo -e "${Green}已删除IPv4转发: $ip:$listen_port ($proto_display)${Font}"
                        ;;
                    "ipv6")
                        echo -e "${Green}已删除IPv6转发: [$local_ipv6]:$listen_port ($proto_display)${Font}"
                        ;;
                    "domain")
                        echo -e "${Green}已删除IPv4 域名转发: $ip:$listen_port --> $remote_ip ($proto_display) [IPv4]${Font}"
                        ;;
                    "domain6")
                        echo -e "${Green}已删除IPv6 域名转发: [$local_ipv6]:$listen_port --> $remote_ip ($proto_display) [IPv6]${Font}"
                        ;;
                esac
                # UNIX套接字模式不需要移除防火墙规则
                if [[ ! " $protocols_raw " =~ " unix " ]]; then
                    # 将JSON数组格式的protocols转换为空格分隔
                    local fw_protocols=$(echo "$protocols_raw" | tr -d '[]"' | tr ',' ' ')
                    remove_firewall_rules "$listen_port" "$ip_type" "$fw_protocols"
                fi
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
    local protocols_raw=$3  # JSON数组格式（如 ["tcp","udp"]）或空格分隔格式
    local extra_raw=$4      # 额外参数（UNIX路径/代理地址）
    
    # 解析协议列表（支持JSON数组格式和空格分隔格式）
    local protocols=()
    if [[ -n "$protocols_raw" && "$protocols_raw" != "null" ]]; then
        # 检测是否为JSON数组格式（包含 [ 或 ]）
        if [[ "$protocols_raw" == *'['* ]] || [[ "$protocols_raw" == *']'* ]]; then
            # JSON数组格式：["tcp","udp"] -> tcp udp
            local parsed=$(echo "$protocols_raw" | tr -d '[]"' | tr ',' ' ' | xargs)
            IFS=' ' read -ra protocols <<< "$parsed"
        else
            # 空格分隔格式
            IFS=' ' read -ra protocols <<< "$protocols_raw"
        fi
    else
        protocols=("tcp" "udp")
    fi
    
    local removed_count=0
    
    # 根据协议精确移除服务
    for proto in "${protocols[@]}"; do
        local svc_name=""
        
        if [[ "$proto" == "unix" ]]; then
            # UNIX协议：需要根据extra路径精确匹配
            # 解析extra，提取实际socket路径（支持新格式tcp2unix:/path和旧格式/path）
            local unix_path=""
            if [[ "$extra_raw" == tcp2unix:* ]] || [[ "$extra_raw" == unix2tcp:* ]]; then
                unix_path="${extra_raw#*:}"
            elif [[ "$extra_raw" == /* ]]; then
                unix_path="$extra_raw"
            fi
            
            if [[ -n "$unix_path" ]]; then
                # 遍历所有socat-unix服务，查找匹配的
                for svc_file in /etc/systemd/system/socat-*-unix-*.service; do
                    [ -f "$svc_file" ] || continue
                    if grep -q "UNIX-LISTEN:${unix_path}\|UNIX-CONNECT:${unix_path}" "$svc_file" 2>/dev/null; then
                        svc_name=$(basename "$svc_file" .service)
                        systemctl stop "$svc_name" 2>/dev/null
                        systemctl disable "$svc_name" 2>/dev/null
                        rm -f "$svc_file"
                        # 清理UNIX socket文件
                        rm -f "$unix_path" 2>/dev/null
                        removed_count=$((removed_count + 1))
                    fi
                done
            fi
        else
            # 普通协议：使用精确服务名
            # 需要找到remote_port，这里用通配符但限定协议
            for svc_file in /etc/systemd/system/socat-${listen_port}-*-${proto}.service; do
                [ -f "$svc_file" ] || continue
                svc_name=$(basename "$svc_file" .service)
                systemctl stop "$svc_name" 2>/dev/null
                systemctl disable "$svc_name" 2>/dev/null
                rm -f "$svc_file"
                removed_count=$((removed_count + 1))
            done
        fi
    done
    
    # 如果上述精确匹配没有找到（兼容旧配置），尝试使用listen_port通配符
    if [[ $removed_count -eq 0 ]] && [[ "$listen_port" != "0" ]]; then
        for svc_file in /etc/systemd/system/socat-${listen_port}-*.service; do
            [ -f "$svc_file" ] || continue
            local svc_name=$(basename "$svc_file" .service)
            systemctl stop "$svc_name" 2>/dev/null
            systemctl disable "$svc_name" 2>/dev/null
            rm -f "$svc_file"
            removed_count=$((removed_count + 1))
        done
    fi
    
    systemctl daemon-reload
    
    # 如果是域名类型，移除域名监控服务
    if [ "$ip_type" == "domain" ] || [ "$ip_type" == "domain6" ]; then
        remove_domain_monitor "$listen_port"
    fi
    
    echo -e "${Green}已移除 ${removed_count} 个转发服务${Font}"
}

# 防火墙检测和配置
configure_firewall() {
    local port=$1
    local ip_version=$2
    local protocols=$3  # 空格分隔的协议列表，如 "tcp udp sctp"
    
    # 标准化IP版本参数
    case "$ip_version" in
        domain|ipv4) ip_version="ipv4" ;;
        domain6|ipv6) ip_version="ipv6" ;;
    esac
    
    # 检测防火墙类型和状态
    local firewall_type=$(detect_firewall)
    [[ -z "$firewall_type" ]] && {
        echo -e "${Yellow}未检测到防火墙工具，端口 ${port} 配置完成。${Font}"
        return 0
    }
    
    # 计算需要开放的防火墙协议（基于转发协议推导）
    local fw_protocols=""
    if [[ -z "$protocols" ]]; then
        fw_protocols="tcp udp"
    else
        for proto in $protocols; do
            case "$proto" in
                tcp|udp|sctp)
                    fw_protocols="$fw_protocols $proto"
                    ;;
                openssl|socks|proxy)
                    # 这些都是基于TCP的
                    [[ ! " $fw_protocols " =~ " tcp " ]] && fw_protocols="$fw_protocols tcp"
                    ;;
                unix)
                    # UNIX套接字不需要防火墙
                    ;;
            esac
        done
    fi
    fw_protocols=$(echo "$fw_protocols" | xargs)  # trim
    
    [[ -z "$fw_protocols" ]] && return 0
    
    # 统一配置防火墙规则
    if configure_firewall_rules "$firewall_type" "$port" "$ip_version" "$fw_protocols"; then
        local proto_display=$(echo "$fw_protocols" | tr ' ' '/' | tr 'a-z' 'A-Z')
        echo -e "${Green}已为 ${ip_version} 端口 ${port} 配置防火墙规则 (${proto_display})${Font}"
    else
        echo -e "${Yellow}防火墙配置失败或无权限，请手动配置端口 ${port}${Font}"
    fi
}

# 检测防火墙类型
detect_firewall() {
    local firewall_type=""
    
    # 检测防火墙状态
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall_type="firewalld"
    elif command -v ufw >/dev/null 2>&1 && ufw status >/dev/null 2>&1; then
        firewall_type="ufw"
    elif command -v iptables >/dev/null 2>&1; then
        firewall_type="iptables"
    fi
    
    echo "$firewall_type"
}

# 统一的防火墙规则配置
configure_firewall_rules() {
    local firewall_type=$1
    local port=$2
    local ip_version=$3
    local protocols=$4  # 空格分隔的协议列表，如 "tcp udp sctp"
    
    # 默认协议
    if [[ -z "$protocols" ]]; then
        protocols="tcp udp"
    fi
    
    case "$firewall_type" in
        firewalld)
            local zone=$(firewall-cmd --get-default-zone 2>/dev/null || echo "public")
            local ipv6_flag=""
            [[ "$ip_version" == "ipv6" ]] && ipv6_flag="--ipv6"
            
            for protocol in $protocols; do
                firewall-cmd --zone="$zone" --add-port="${port}/${protocol}" --permanent $ipv6_flag 2>/dev/null || return 1
            done
            firewall-cmd --reload 2>/dev/null || return 1
            ;;
        ufw)
            for protocol in $protocols; do
                ufw allow "${port}/${protocol}" 2>/dev/null || return 1
            done
            ;;
        iptables)
            local cmd="iptables"
            [[ "$ip_version" == "ipv6" ]] && cmd="ip6tables"
            
            for protocol in $protocols; do
                $cmd -C INPUT -p "$protocol" --dport "$port" -j ACCEPT 2>/dev/null || \
                $cmd -I INPUT -p "$protocol" --dport "$port" -j ACCEPT 2>/dev/null || return 1
            done
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# 移除防火墙规则
remove_firewall_rules() {
    local port=$1
    local ip_type=$2
    local protocols=$3  # 空格分隔的协议列表（可选）
    
    # 标准化IP版本参数
    case "$ip_type" in
        domain|ipv4) ip_type="ipv4" ;;
        domain6|ipv6) ip_type="ipv6" ;;
    esac
    
    # 检测防火墙类型
    local firewall_type=$(detect_firewall)
    [[ -z "$firewall_type" ]] && {
        echo -e "${Yellow}未检测到防火墙工具，跳过防火墙规则移除。${Font}"
        return 0
    }
    
    # 如果没有指定协议，尝试移除所有可能的协议
    if [[ -z "$protocols" ]]; then
        protocols="tcp udp sctp"
    fi
    
    # 统一移除防火墙规则
    if remove_firewall_rules_by_type "$firewall_type" "$port" "$ip_type" "$protocols"; then
        local proto_display=$(echo "$protocols" | tr ' ' '/' | tr 'a-z' 'A-Z')
        echo -e "${Green}已移除端口 ${port} 的防火墙规则 (${proto_display})${Font}"
    else
        echo -e "${Yellow}防火墙规则移除失败或无权限${Font}"
    fi
}

# 统一的防火墙规则移除
remove_firewall_rules_by_type() {
    local firewall_type=$1
    local port=$2
    local ip_type=$3
    local protocols=$4  # 空格分隔的协议列表
    
    [[ -z "$protocols" ]] && protocols="tcp udp sctp"
    
    case "$firewall_type" in
        firewalld)
            local zone=$(firewall-cmd --get-default-zone 2>/dev/null || echo "public")
            local ipv6_flag=""
            [[ "$ip_type" == "ipv6" ]] && ipv6_flag="--ipv6"
            
            for protocol in $protocols; do
                firewall-cmd --zone="$zone" --remove-port="${port}/${protocol}" --permanent $ipv6_flag 2>/dev/null || continue
            done
            firewall-cmd --reload 2>/dev/null || return 1
            ;;
        ufw)
            for protocol in $protocols; do
                ufw delete allow "${port}/${protocol}" 2>/dev/null || continue
            done
            ;;
        iptables)
            local cmd="iptables"
            [[ "$ip_type" == "ipv6" ]] && cmd="ip6tables"
            
            for protocol in $protocols; do
                $cmd -D INPUT -p "$protocol" --dport "$port" -j ACCEPT 2>/dev/null || continue
            done
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# 恢复之前的转发
restore_forwards() {
    if [ -s "$CONFIG_FILE" ]; then
        echo "正在恢复之前的转发..."
        
        if command -v jq >/dev/null 2>&1; then
            # 使用jq解析JSON配置
            local configs=$(jq -c '.[]' "$CONFIG_FILE")
            while IFS= read -r config; do
                local ip_type=$(echo "$config" | jq -r '.type')
                local listen_port=$(echo "$config" | jq -r '.listen_port')
                local remote_ip=$(echo "$config" | jq -r '.remote_ip')
                local remote_port=$(echo "$config" | jq -r '.remote_port')
                local protocols_raw=$(echo "$config" | jq -r '.protocols // empty')
                local extra_raw=$(echo "$config" | jq -r '.extra // empty')
                
                # 兼容旧配置：没有protocols字段时默认tcp+udp
                local restore_protocols=()
                if [[ -z "$protocols_raw" || "$protocols_raw" == "null" ]]; then
                    restore_protocols=("tcp" "udp")
                else
                    restore_protocols=($(echo "$protocols_raw" | tr -d '[]"' | tr ',' ' '))
                fi
                
                # 将配置类型转换为内部格式
                local ip_version=""
                case "$ip_type" in
                    "ipv4") ip_version="4" ;;
                    "ipv6") ip_version="6" ;;
                    "domain") ip_version="domain" ;;
                    "domain6") ip_version="domain6" ;;
                    *) continue ;;  # 跳过无效类型
                esac
                
                # SSL协议需要先确保证书存在
                if [[ " ${restore_protocols[*]} " =~ " openssl " ]]; then
                    generate_ssl_cert
                fi
                
                # 使用统一的函数创建服务
                for proto in "${restore_protocols[@]}"; do
                    create_single_socat_service "$proto" "$ip_version" "$listen_port" "$remote_ip" "$remote_port" "$extra_raw"
                done
                
                # 如果是域名类型，恢复监控（排除代理协议）
                if [ "$ip_type" == "domain" ] || [ "$ip_type" == "domain6" ]; then
                    if [[ " ${restore_protocols[*]} " =~ " tcp " ]] || [[ " ${restore_protocols[*]} " =~ " openssl " ]] || [[ " ${restore_protocols[*]} " =~ " sctp " ]]; then
                        if [[ ! " ${restore_protocols[*]} " =~ " socks " ]] && [[ ! " ${restore_protocols[*]} " =~ " proxy " ]]; then
                            setup_domain_monitor "$remote_ip" "$listen_port" "$ip_type" "$remote_port" "${restore_protocols[*]}"
                        fi
                    fi
                fi
                
                # 协议显示
                local proto_display=""
                for proto in "${restore_protocols[@]}"; do
                    [[ -n "$proto_display" ]] && proto_display+="/"
                    proto_display+=$(echo "$proto" | tr 'a-z' 'A-Z')
                done
                
                # 统一的显示信息
                case "$ip_type" in
                    "ipv6"|"domain6")
                        echo "已恢复IPv6转发：${listen_port} -> ${remote_ip}:${remote_port} [${proto_display}]"
                        ;;
                    *)
                        echo "已恢复IPv4转发：${listen_port} -> ${remote_ip}:${remote_port} [${proto_display}]"
                        ;;
                esac
                
                # 显示extra信息
                if [[ -n "$extra_raw" && "$extra_raw" != "null" ]]; then
                    if [[ "$extra_raw" == tcp2unix:* ]] || [[ "$extra_raw" == unix2tcp:* ]]; then
                        local display_unix="${extra_raw#*:}"
                        local dir_label="TCP->UNIX"
                        [[ "$extra_raw" == unix2tcp:* ]] && dir_label="UNIX->TCP"
                        echo "  UNIX套接字: $display_unix ($dir_label)"
                    elif [[ "$extra_raw" == /* ]]; then
                        echo "  UNIX套接字: $extra_raw"
                    elif [[ "$extra_raw" == *:* && "$extra_raw" != tcp2unix:* && "$extra_raw" != unix2tcp:* ]]; then
                        echo "  代理: $extra_raw"
                    fi
                fi
                
                # 域名监控恢复信息
                if [ "$ip_type" == "domain" ] || [ "$ip_type" == "domain6" ]; then
                    echo "已恢复域名 ${remote_ip} 的IP监控服务"
                fi
            done <<< "$configs"
        else
            # 回退到基于字符解析的JSON提取
            local configs=$(json_extract_objects "$CONFIG_FILE")
            
            while IFS= read -r config; do
                [[ -z "$config" ]] && continue
                
                local ip_type=$(json_extract_field "$config" "type")
                local listen_port=$(json_extract_field "$config" "listen_port")
                local remote_ip=$(json_extract_field "$config" "remote_ip")
                local remote_port=$(json_extract_field "$config" "remote_port")
                local protocols_raw=$(json_extract_field "$config" "protocols")
                local extra_raw=$(json_extract_field "$config" "extra")
                
                [ -z "$ip_type" ] && continue
                
                # 将配置类型转换为内部格式
                local ip_version=""
                case "$ip_type" in
                    "ipv4") ip_version="4" ;;
                    "ipv6") ip_version="6" ;;
                    "domain") ip_version="domain" ;;
                    "domain6") ip_version="domain6" ;;
                    *) continue ;;
                esac
                
                # 解析协议列表
                local restore_protocols=()
                if [[ -n "$protocols_raw" ]]; then
                    restore_protocols=($protocols_raw)
                else
                    restore_protocols=("tcp" "udp")
                fi
                
                # SSL协议需要证书
                if [[ " ${restore_protocols[*]} " =~ " openssl " ]]; then
                    generate_ssl_cert
                fi
                
                # 创建各协议服务
                for proto in "${restore_protocols[@]}"; do
                    create_single_socat_service "$proto" "$ip_version" "$listen_port" "$remote_ip" "$remote_port" "$extra_raw"
                done
                
                # 协议显示
                local proto_display=""
                for proto in "${restore_protocols[@]}"; do
                    [[ -n "$proto_display" ]] && proto_display+="/"
                    proto_display+=$(echo "$proto" | tr 'a-z' 'A-Z')
                done
                
                case "$ip_type" in
                    "ipv6"|"domain6")
                        echo "已恢复IPv6转发：${listen_port} -> ${remote_ip}:${remote_port} [${proto_display}]"
                        ;;
                    *)
                        echo "已恢复IPv4转发：${listen_port} -> ${remote_ip}:${remote_port} [${proto_display}]"
                        ;;
                esac
                
                if [[ -n "$extra_raw" && "$extra_raw" != "null" ]]; then
                    [[ "$extra_raw" == /* ]] && echo "  UNIX套接字: $extra_raw"
                    [[ "$extra_raw" == *:* ]] && echo "  代理: $extra_raw"
                fi
                
                if [ "$ip_type" == "domain" ] || [ "$ip_type" == "domain6" ]; then
                    if [[ " ${restore_protocols[*]} " =~ " tcp " ]] || [[ " ${restore_protocols[*]} " =~ " openssl " ]] || [[ " ${restore_protocols[*]} " =~ " sctp " ]]; then
                        setup_domain_monitor "$remote_ip" "$listen_port" "$ip_type" "$remote_port" "${restore_protocols[*]}"
                        echo "已恢复域名 ${remote_ip} 的IP监控服务"
                    fi
                fi
            done <<< "$configs"
        fi
    fi
}

# 检查是否已启用BBR或其变种
check_and_enable_bbr() {
    echo -e "${Green}正在检查 BBR 状态...${Font}"

    # 获取内核版本 - 更精确的版本检测
    kernel_version=$(uname -r | sed 's/[^0-9.]*\([0-9.]*\).*/\1/')
    major_version=$(echo "$kernel_version" | cut -d. -f1)
    minor_version=$(echo "$kernel_version" | cut -d. -f2)
    
    # 检查内核版本是否支持BBR (4.9+ 支持BBR, 4.13+ 支持BBRv2)
    if [[ $major_version -lt 4 ]] || [[ $major_version -eq 4 && $minor_version -lt 9 ]]; then
        echo -e "${Red}当前内核版本 ($kernel_version) 过低，不支持 BBR。需要 4.9 或更高版本。${Font}"
        return 1
    fi

    # 检查系统是否支持BBR算法
    if ! sysctl net.ipv4.tcp_available_congestion_control &>/dev/null; then
        echo -e "${Red}系统不支持拥塞控制算法配置${Font}"
        return 1
    fi

    # 获取可用的拥塞控制算法
    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
    if [[ -z "$available_cc" ]]; then
        echo -e "${Red}无法获取可用的拥塞控制算法${Font}"
        return 1
    fi

    # 检查BBR是否可用 - 按优先级顺序：bbrplus -> bbr -> bbr2
    bbr_variants=("bbrplus" "bbr" "bbr2")
    supported_bbr=""
    for variant in "${bbr_variants[@]}"; do
        if echo "$available_cc" | grep -q "$variant"; then
            supported_bbr="$variant"
            break
        fi
    done

    if [[ -z "$supported_bbr" ]]; then
        echo -e "${Red}系统不支持BBR算法。可用算法: $available_cc${Font}"
        return 1
    fi

    # 获取当前拥塞控制算法
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    if [[ -z "$current_cc" ]]; then
        echo -e "${Red}无法获取当前拥塞控制算法${Font}"
        return 1
    fi

    # 检查当前算法是否为BBR变体
    is_bbr_enabled=false
    current_bbr_variant=""
    for variant in "${bbr_variants[@]}"; do
        if [[ "$current_cc" == "$variant" ]]; then
            is_bbr_enabled=true
            current_bbr_variant="$variant"
            echo -e "${Yellow}检测到系统已启用 ${current_bbr_variant}${Font}"
            break
        fi
    done

    # 检查内核是否内置BBR - 不再强制要求模块加载
    has_bbr_module=false
    if lsmod | grep -q "tcp_bbr" || echo "$available_cc" | grep -q "bbr"; then
        has_bbr_module=true
    fi

    if [[ "$has_bbr_module" == false ]]; then
        echo -e "${Yellow}BBR模块未找到，尝试加载...${Font}"
        if modprobe tcp_bbr 2>/dev/null; then
            echo -e "${Green}BBR模块加载成功${Font}"
            has_bbr_module=true
        else
            echo -e "${Yellow}BBR模块加载失败，可能是内置内核或已集成${Font}"
            # 继续执行，因为可能是内置内核
        fi
    fi

    # 如果未启用BBR，尝试启用
    if [[ "$is_bbr_enabled" != true ]]; then
        echo -e "${Yellow}当前拥塞控制算法为 ${current_cc}，正在切换到 ${supported_bbr}...${Font}"
        if sysctl -w net.ipv4.tcp_congestion_control="$supported_bbr" 2>/dev/null; then
            echo -e "${Green}已切换到 ${supported_bbr}${Font}"
            current_cc="$supported_bbr"
        else
            echo -e "${Red}切换到 ${supported_bbr} 失败${Font}"
            return 1
        fi
    fi

    # 检查并设置队列调度算法
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "")
    if [[ "$current_qdisc" != "fq" ]]; then
        echo -e "${Yellow}当前队列调度算法为 ${current_qdisc}，正在切换到 fq...${Font}"
        if sysctl -w net.core.default_qdisc=fq 2>/dev/null; then
            echo -e "${Green}已切换到 fq 队列调度${Font}"
        else
            echo -e "${Yellow}切换到 fq 失败，可能系统不支持${Font}"
        fi
    fi

    # 持久化配置
    local sysctl_file="/etc/sysctl.conf"
    if [[ -w "$sysctl_file" ]]; then
        # 清理旧的BBR配置
        sed -i '/net\.ipv4\.tcp_congestion_control/d' "$sysctl_file"
        sed -i '/net\.core\.default_qdisc/d' "$sysctl_file"
        
        # 添加新的BBR配置
        echo "net.ipv4.tcp_congestion_control = $current_cc" >> "$sysctl_file"
        echo "net.core.default_qdisc = fq" >> "$sysctl_file"
        
        # 重新加载配置
        sysctl -p 2>/dev/null || echo -e "${Yellow}sysctl配置重载部分失败${Font}"
    else
        echo -e "${Yellow}无法写入sysctl配置文件，配置将在重启后失效${Font}"
    fi

    # 最终验证
    final_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    final_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "")
    
    # 检查是否为BBR变体
    is_bbr_final=false
    for variant in "${bbr_variants[@]}"; do
        if [[ "$final_cc" == "$variant" ]]; then
            is_bbr_final=true
            break
        fi
    done

    if [[ "$is_bbr_final" == true ]]; then
        echo -e "${Green}BBR 已成功启用。当前算法: $final_cc, 队列调度: $final_qdisc${Font}"
        return 0
    else
        echo -e "${Red}BBR 启用失败，当前拥塞控制算法为 ${final_cc}${Font}"
        return 1
    fi
}

# 网络加速配置管理
manage_network_acceleration() {
    local action="$1"  # "enable" 或 "disable"
    
    # 备份文件路径 - 保存用户原始配置
    local backup_file="$SOCATS_DIR/sysctl_backup.conf"
    
    # 定义所有需要管理的配置键
    local all_keys=(
        "net.ipv4.tcp_fastopen"
        "net.ipv4.tcp_congestion_control"
        "net.core.default_qdisc"
        "net.ipv4.tcp_slow_start_after_idle"
        "net.ipv4.tcp_mtu_probing"
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.ipv4.tcp_rmem"
        "net.ipv4.tcp_wmem"
        "net.ipv4.tcp_mem"
        "net.core.netdev_max_backlog"
        "net.core.netdev_budget"
        "net.ipv4.tcp_max_syn_backlog"
        "net.ipv4.tcp_tw_reuse"
        "net.ipv4.tcp_fin_timeout"
        "net.ipv4.tcp_keepalive_time"
        "net.ipv4.tcp_keepalive_intvl"
        "net.ipv4.tcp_keepalive_probes"
        "net.ipv4.tcp_max_tw_buckets"
        "net.ipv4.tcp_syncookies"
        "net.ipv4.tcp_rfc1337"
        "net.ipv4.tcp_sack"
        "net.ipv4.tcp_fack"
        "net.ipv4.tcp_window_scaling"
        "net.ipv4.tcp_adv_win_scale"
        "net.ipv4.tcp_moderate_rcvbuf"
        "net.ipv4.tcp_no_metrics_save"
        "net.ipv4.tcp_timestamps"
        "net.ipv4.tcp_ecn"
        "net.core.optmem_max"
        "net.ipv4.tcp_notsent_lowat"
        "net.ipv4.ip_local_port_range"
        "net.ipv4.tcp_max_orphans"
        "net.ipv4.tcp_abort_on_overflow"
        "net.core.somaxconn"
    )
    
    # 定义加速配置（键=值 格式）- 专为端口转发优化
    local -A acceleration_configs=(
        ["net.ipv4.tcp_fastopen"]="3"
        ["net.ipv4.tcp_slow_start_after_idle"]="0"
        ["net.ipv4.tcp_mtu_probing"]="1"
        ["net.core.rmem_max"]="67108864"
        ["net.core.wmem_max"]="67108864"
        ["net.ipv4.tcp_rmem"]="4096 262144 67108864"
        ["net.ipv4.tcp_wmem"]="4096 262144 67108864"
        ["net.ipv4.tcp_mem"]="8388608 12582912 16777216"
        ["net.core.netdev_max_backlog"]="8192"
        ["net.core.netdev_budget"]="600"
        ["net.ipv4.tcp_max_syn_backlog"]="8192"
        ["net.ipv4.tcp_tw_reuse"]="1"
        ["net.ipv4.tcp_fin_timeout"]="10"
        ["net.ipv4.tcp_keepalive_time"]="600"
        ["net.ipv4.tcp_keepalive_intvl"]="30"
        ["net.ipv4.tcp_keepalive_probes"]="3"
        ["net.ipv4.tcp_max_tw_buckets"]="5000000"
        ["net.ipv4.tcp_syncookies"]="1"
        ["net.ipv4.tcp_sack"]="1"
        ["net.ipv4.tcp_fack"]="1"
        ["net.ipv4.tcp_window_scaling"]="1"
        ["net.ipv4.tcp_adv_win_scale"]="1"
        ["net.ipv4.tcp_moderate_rcvbuf"]="1"
        ["net.ipv4.tcp_no_metrics_save"]="1"
        ["net.ipv4.tcp_rfc1337"]="1"
        ["net.ipv4.tcp_timestamps"]="1"
        ["net.ipv4.tcp_ecn"]="0"
        ["net.core.optmem_max"]="65536"
        ["net.ipv4.tcp_notsent_lowat"]="32768"
        ["net.ipv4.ip_local_port_range"]="1024 65535"
        ["net.ipv4.tcp_max_orphans"]="8192"
        ["net.ipv4.tcp_abort_on_overflow"]="0"
        ["net.core.somaxconn"]="8192"
    )
    
    # 备份当前系统配置（只在开启加速且没有备份时执行）
    backup_current_config() {
        if [ -f "$backup_file" ]; then
            return 0  # 已有备份，不覆盖
        fi
        echo "# Sysctl configuration backup - created $(date '+%Y-%m-%d %H:%M:%S')" > "$backup_file"
        for key in "${all_keys[@]}"; do
            local current_val=$(sysctl -n "$key" 2>/dev/null)
            if [[ -n "$current_val" ]]; then
                echo "$key = $current_val" >> "$backup_file"
            fi
        done
        return 0
    }
    
    # 从 /etc/sysctl.conf 中清理所有相关配置
    cleanup_sysctl_conf() {
        for key in "${all_keys[@]}"; do
            sed -i "/${key//\./\\.}/d" /etc/sysctl.conf
        done
    }
    
    if [[ "$action" == "enable" ]]; then
        # 先备份原始配置
        backup_current_config
        
        # 清理 sysctl.conf 中旧的相关配置
        cleanup_sysctl_conf
        
        # 启用 BBR
        check_and_enable_bbr
        
        # 应用加速参数
        local applied=0
        for key in "${!acceleration_configs[@]}"; do
            if sysctl -w "${key}=${acceleration_configs[$key]}" >/dev/null 2>&1; then
                applied=$((applied + 1))
            fi
        done
        
        # 写入 sysctl.conf 持久化
        for key in "${!acceleration_configs[@]}"; do
            echo "$key = ${acceleration_configs[$key]}" >> /etc/sysctl.conf
        done
        
        # 重新加载 sysctl.conf 确保生效
        sysctl -p >/dev/null 2>&1
        
        echo -e "${Green}端口转发加速已开启${Font} (已优化 $applied 项参数)"
        
    else
        # 关闭加速 - 优先从备份恢复
        local restored_ok=false
        
        if [ -f "$backup_file" ]; then
            echo -e "${Yellow}正在从备份恢复原始网络配置...${Font}"
            
            # 清理 sysctl.conf 中相关配置
            cleanup_sysctl_conf
            
            # 应用备份值
            local restored_count=0
            while IFS='=' read -r key value; do
                key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [[ -z "$key" || "$key" == \#* ]] && continue
                sysctl -w "$key=$value" >/dev/null 2>&1 && restored_count=$((restored_count + 1))
                echo "$key = $value" >> /etc/sysctl.conf
            done < "$backup_file"
            
            sysctl -p >/dev/null 2>&1
            
            if [[ $restored_count -gt 0 ]]; then
                restored_ok=true
                # 删除备份文件，表示已恢复
                rm -f "$backup_file"
                echo -e "${Green}端口转发加速已关闭${Font} (已恢复 $restored_count 项原始配置)"
            fi
        fi
        
        # 如果备份恢复失败，使用内置默认值作为兜底
        if [[ "$restored_ok" != true ]]; then
            echo -e "${Yellow}未找到原始配置备份，使用系统默认值恢复...${Font}"
            
            cleanup_sysctl_conf
            
            local -A fallback_defaults=(
                ["net.ipv4.tcp_fastopen"]="0"
                ["net.ipv4.tcp_congestion_control"]="cubic"
                ["net.core.default_qdisc"]="pfifo_fast"
                ["net.ipv4.tcp_slow_start_after_idle"]="1"
                ["net.ipv4.tcp_mtu_probing"]="0"
                ["net.core.rmem_max"]="212992"
                ["net.core.wmem_max"]="212992"
                ["net.ipv4.tcp_rmem"]="4096 87380 6291456"
                ["net.ipv4.tcp_wmem"]="4096 16384 4194304"
                ["net.ipv4.tcp_mem"]="378651 504868 757299"
                ["net.core.netdev_max_backlog"]="1000"
                ["net.core.netdev_budget"]="300"
                ["net.ipv4.tcp_max_syn_backlog"]="128"
                ["net.ipv4.tcp_tw_reuse"]="0"
                ["net.ipv4.tcp_fin_timeout"]="60"
                ["net.ipv4.tcp_keepalive_time"]="7200"
                ["net.ipv4.tcp_keepalive_intvl"]="75"
                ["net.ipv4.tcp_keepalive_probes"]="9"
                ["net.ipv4.tcp_max_tw_buckets"]="180000"
                ["net.ipv4.tcp_syncookies"]="1"
                ["net.ipv4.tcp_rfc1337"]="0"
                ["net.ipv4.tcp_sack"]="1"
                ["net.ipv4.tcp_fack"]="1"
                ["net.ipv4.tcp_window_scaling"]="1"
                ["net.ipv4.tcp_adv_win_scale"]="1"
                ["net.ipv4.tcp_moderate_rcvbuf"]="1"
                ["net.ipv4.tcp_no_metrics_save"]="0"
                ["net.ipv4.tcp_timestamps"]="1"
                ["net.ipv4.tcp_ecn"]="2"
                ["net.core.optmem_max"]="20480"
                ["net.ipv4.tcp_notsent_lowat"]="4294967295"
                ["net.ipv4.ip_local_port_range"]="32768 60999"
                ["net.ipv4.tcp_max_orphans"]="8192"
                ["net.ipv4.tcp_abort_on_overflow"]="0"
                ["net.core.somaxconn"]="128"
            )
            
            local restored=0
            for key in "${!fallback_defaults[@]}"; do
                if sysctl -w "${key}=${fallback_defaults[$key]}" >/dev/null 2>&1; then
                    restored=$((restored + 1))
                fi
                echo "$key = ${fallback_defaults[$key]}" >> /etc/sysctl.conf
            done
            
            sysctl -p >/dev/null 2>&1
            
            echo -e "${Yellow}端口转发加速已关闭${Font} (已恢复 $restored 项默认配置)"
        fi
    fi
}

# 开启端口转发加速
enable_acceleration() {
    echo -e "${Green}正在开启端口转发加速...${Font}"
    manage_network_acceleration "enable"
}

# 关闭端口转发加速
disable_acceleration() {
    echo -e "${Yellow}正在关闭端口转发加速...${Font}"
    manage_network_acceleration "disable"
}

# 查看端口转发加速状态
show_acceleration_status() {
    echo -e "${Green}=== 端口转发加速状态 ===${Font}"
    echo
    
    # 检查BBR状态
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    local current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    local is_bbr=false
    
    for variant in bbrplus bbr bbr2; do
        if [[ "$current_cc" == "$variant" ]]; then
            is_bbr=true
            break
        fi
    done
    
    echo -e "拥塞控制算法: ${Blue}$current_cc${Font} $($is_bbr && echo -e "${Green}[已启用BBR]${Font}" || echo -e "${Yellow}[未启用BBR]${Font}")"
    echo -e "队列调度算法: ${Blue}$current_qdisc${Font}"
    echo
    
    # 检查关键加速参数
    echo -e "${Green}关键加速参数:${Font}"
    
    local params=(
        "net.ipv4.tcp_fastopen|TCP快速打开"
        "net.ipv4.tcp_slow_start_after_idle|空闲后慢启动"
        "net.core.rmem_max|最大接收缓冲区"
        "net.core.wmem_max|最大发送缓冲区"
        "net.ipv4.tcp_tw_reuse|TIME_WAIT重用"
        "net.ipv4.tcp_fin_timeout|FIN超时时间"
    )
    
    local enabled_count=0
    local total_params=0
    
    for param_info in "${params[@]}"; do
        local key="${param_info%%|*}"
        local name="${param_info##*|}"
        local value=$(sysctl -n "$key" 2>/dev/null || echo "未知")
        echo -e "  $name: ${Blue}$value${Font}"
        
        # 简单判断是否为加速值
        total_params=$((total_params + 1))
        case "$key" in
            "net.ipv4.tcp_fastopen")
                [[ "$value" == "3" ]] && enabled_count=$((enabled_count + 1))
                ;;
            "net.ipv4.tcp_slow_start_after_idle")
                [[ "$value" == "0" ]] && enabled_count=$((enabled_count + 1))
                ;;
            "net.core.rmem_max")
                [[ "$value" -gt 212992 ]] && enabled_count=$((enabled_count + 1))
                ;;
            "net.core.wmem_max")
                [[ "$value" -gt 212992 ]] && enabled_count=$((enabled_count + 1))
                ;;
            "net.ipv4.tcp_tw_reuse")
                [[ "$value" == "1" ]] && enabled_count=$((enabled_count + 1))
                ;;
            "net.ipv4.tcp_fin_timeout")
                [[ "$value" -lt 60 ]] && enabled_count=$((enabled_count + 1))
                ;;
        esac
    done
    
    echo
    
    # 综合判断加速状态
    if $is_bbr && [[ $enabled_count -ge $((total_params / 2)) ]]; then
        echo -e "${Green}端口转发加速: 已启用${Font}"
    elif $is_bbr || [[ $enabled_count -gt 0 ]]; then
        echo -e "${Yellow}端口转发加速: 部分启用${Font} (已优化 $enabled_count/$total_params 项参数)"
    else
        echo -e "${Red}端口转发加速: 未启用${Font}"
    fi
}

# 设置域名监控服务
setup_domain_monitor() {
    local domain=$1
    local listen_port=$2
    local ip_type=$3
    local remote_port=$4
    local protocols_raw=$5  # 协议列表，空格分隔，如 "tcp udp openssl"
    
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
PROTOCOLS="$6"  # 协议列表，空格分隔

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
        
        # 根据协议列表重启对应的socat服务
        local services_to_restart=()
        for proto in $PROTOCOLS; do
            local svc_name="socat-${LISTEN_PORT}-${REMOTE_PORT}-${proto}"
            if systemctl list-unit-files "${svc_name}.service" >/dev/null 2>&1; then
                services_to_restart+=("${svc_name}.service")
            fi
        done
        
        if [ ${#services_to_restart[@]} -gt 0 ]; then
            systemctl restart "${services_to_restart[@]}" 2>/dev/null
            echo "$(date): 已重启转发服务: ${services_to_restart[*]}" >> "${SOCATS_DIR}/dns_monitor.log"
        else
            echo "$(date): 未找到匹配的转发服务，跳过重启" >> "${SOCATS_DIR}/dns_monitor.log"
        fi
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
    
    # 检查定时器是否已存在，若存在则跳过
    if systemctl is-active --quiet "$timer_name.timer" 2>/dev/null; then
        echo -e "${Yellow}域名 ${domain} 的监控定时器已存在，跳过创建${Font}"
        return 0
    fi
    
    cat > /etc/systemd/system/${timer_name}.service <<EOF
[Unit]
Description=Domain IP Monitor Service for ${domain}
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $monitor_script "${domain}" "${listen_port}" "${ip_type}" "${remote_port}" "${SOCATS_DIR}" "${protocols_raw}"

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
    
    # 获取当前端口的域名信息并删除对应的DNS缓存文件
    local domain=""
    if command -v jq >/dev/null 2>&1; then
        domain=$(jq -r --argjson port "$listen_port" '.[] | select(.listen_port == $port and (.type == "domain" or .type == "domain6")) | .remote_ip' "$CONFIG_FILE" 2>/dev/null)
    else
        # 从配置文件中提取域名（无jq回退）
        local configs=$(json_extract_objects "$CONFIG_FILE")
        while IFS= read -r config; do
            [[ -z "$config" ]] && continue
            local cfg_port=$(json_extract_field "$config" "listen_port")
            local cfg_type=$(json_extract_field "$config" "type")
            if [[ "$cfg_port" == "$listen_port" ]] && [[ "$cfg_type" == "domain" || "$cfg_type" == "domain6" ]]; then
                domain=$(json_extract_field "$config" "remote_ip")
                break
            fi
        done <<< "$configs"
    fi
    
    if [[ -n "$domain" ]]; then
        # 将域名转换为缓存文件名格式
        local cache_filename="dns_cache_${domain//[^a-zA-Z0-9]/_}.txt"
        local cache_file="${SOCATS_DIR}/${cache_filename}"
        
        if [ -f "$cache_file" ]; then
            rm -f "$cache_file"
            echo -e "${Green}已删除DNS缓存文件: ${cache_filename}${Font}"
        fi
    fi
    
    systemctl daemon-reload
    
    echo -e "${Green}已移除端口 ${listen_port} 的域名监控服务${Font}"
}

# 切换JSON格式化开关
toggle_json_format() {
    if [ "$JSON_FORMAT_ENABLED" -eq 1 ]; then
        JSON_FORMAT_ENABLED=0
        echo -e "${Green}已关闭JSON格式化，配置文件将保持紧凑格式${Font}"
    else
        JSON_FORMAT_ENABLED=1
        echo -e "${Green}已开启JSON格式化，配置文件将被格式化${Font}"
    fi
    
    # 立即应用新的格式化设置到现有配置
    if [ -f "$CONFIG_FILE" ]; then
        format_json_config "$CONFIG_FILE" "$JSON_FORMAT_ENABLED"
    fi
    
    # 保存设置到配置文件
    echo "JSON_FORMAT_ENABLED=$JSON_FORMAT_ENABLED" > "$SOCATS_DIR/.json_format"
}

# 修改域名监控频率
change_monitor_interval() {
    if [ ! -s "$CONFIG_FILE" ]; then
        echo -e "${Red}当前没有活动的转发。${Font}"
        return
    fi
    
    local has_domain=false
    local domain_entries=()
    local i=1
    
    if command -v jq >/dev/null 2>&1; then
        # 使用jq解析JSON配置
        local configs=$(jq -c '.[]' "$CONFIG_FILE")
        while IFS= read -r config; do
            local ip_type=$(echo "$config" | jq -r '.type')
            local listen_port=$(echo "$config" | jq -r '.listen_port')
            local remote_ip=$(echo "$config" | jq -r '.remote_ip')
            local remote_port=$(echo "$config" | jq -r '.remote_port')
            
            if [ "$ip_type" == "domain" ] || [ "$ip_type" == "domain6" ]; then
                has_domain=true
                domain_entries+=("$listen_port $remote_ip $ip_type $remote_port")
                if [ "$ip_type" == "domain" ]; then
                    echo "$i. IPv4 域名: $ip:$listen_port --> $remote_ip:$remote_port"
                else
                    echo "$i. IPv6 域名: [$ipv6]:$listen_port --> $remote_ip:$remote_port"
                fi
                ((i++))
            fi
        done <<< "$configs"
    else
        # 回退到基于字符解析的JSON提取
        local configs=$(json_extract_objects "$CONFIG_FILE")
        
        while IFS= read -r config; do
            [[ -z "$config" ]] && continue
            
            local ip_type=$(json_extract_field "$config" "type")
            local listen_port=$(json_extract_field "$config" "listen_port")
            local remote_ip=$(json_extract_field "$config" "remote_ip")
            local remote_port=$(json_extract_field "$config" "remote_port")
            
            [ -z "$ip_type" ] && continue
            
            if [ "$ip_type" == "domain" ] || [ "$ip_type" == "domain6" ]; then
                has_domain=true
                domain_entries+=("$listen_port $remote_ip $ip_type $remote_port")
                if [ "$ip_type" == "domain" ]; then
                    echo "$i. IPv4 域名: $ip:$listen_port --> $remote_ip:$remote_port"
                else
                    echo "$i. IPv6 域名: [$ipv6]:$listen_port --> $remote_ip:$remote_port"
                fi
                ((i++))
            fi
        done <<< "$configs"
    fi
    
    if [ "$has_domain" == "false" ]; then
        echo -e "${Red}当前没有活动的域名转发。${Font}"
        return
    fi
    
    read -p "请输入要修改监控频率的域名转发编号: " num
    if [ -z "$num" ] || ! [[ $num =~ ^[0-9]+$ ]] || [ $num -lt 1 ] || [ $num -gt ${#domain_entries[@]} ]; then
        echo -e "${Red}无效的编号。${Font}"
        return
    fi
    
    local index=$((num-1))
    IFS=' ' read -r port domain type remote_port <<< "${domain_entries[$index]}"
    
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

# 显示Socat管理子菜单
manage_socat_menu() {
    while true; do
        clear_screen
        echo -e "${Green}
   _____                 __
  / ___/____  _________ _/ /_ 
  \__ \/ __ \/ ___/ __ \`/ __/ 
 ___/ / /_/ / /__/ /_/ / /_ 
/____/\____/\___/\__,_/\__/  ${Yellow}Socat管理${Font}"
        echo -e "${Blue}==========================================${Font}"
        echo -e "${Yellow}1.${Font} 开启Socat"
        echo -e "${Yellow}2.${Font} 关闭Socat"
        echo -e "${Yellow}3.${Font} 重启Socat"
        echo -e "${Yellow}4.${Font} 卸载Socat"
        echo -e "${Yellow}5.${Font} 返回主菜单"
        echo -e "${Blue}==========================================${Font}"
        read -p "请输入选项 [1-5]: " choice
        case $choice in
            1)
                echo -e "${Green}开启Socat...${Font}"
                open_socat
                ;; 
            2)
                echo -e "${Green}终止所有 Socat 进程...${Font}"
                kill_all_socat
                ;; 
            3)
                echo -e "${Green}重启Socat...${Font}"
                re_socat
                ;; 
            4)
                echo -e "${Green}卸载Socat...${Font}"
                uninstall_socat
                return
                ;; 
            5)
                return
                ;; 
            *)
                echo -e "${Red}无效的选项，请重新输入。${Font}"
                sleep 2
                ;; 
        esac
    done
}

# 开启/重新加载socat
open_socat(){

    restore_forwards

}

# 强制终止所有Socat进程
kill_all_socat() {
    echo -e "${Yellow}正在终止所有 Socat 进程...${Font}"
    # 停止并禁用所有socat服务
    for service_file in /etc/systemd/system/socat-*.service; do
    if [ -f "$service_file" ]; then
        service_name=$(basename "$service_file" .service)
        systemctl stop "$service_name"
        systemctl disable "$service_name"
    fi
done
    rm -f /etc/systemd/system/socat-*.service
    systemctl daemon-reload
    pkill -9 -f "$(which socat)"
    #pkill -9 -f "$0"
    sleep 2
    if pgrep -f socat > /dev/null; then
        echo -e "${Red}警告：某些 Socat 进程可能仍在运行。请考虑手动检查。${Font}"
    else
        echo -e "${Green}所有 Socat 进程已成功终止。${Font}"
    fi
    if [[ "$1" == "uninstall" ]]; then
        > "$CONFIG_FILE"
        echo -e "${Green}已清空转发配置文件${Font}"
    elif [[ "$1" != "noconfirm" ]]; then
        read -p "是否清除Socat转发配置文件？[y/N]: " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            > "$CONFIG_FILE"
            echo -e "${Green}已清空转发配置文件${Font}"
        else
            echo -e "${Yellow}已保留转发配置文件${Font}"
        fi
    else
        echo -e "${Yellow}正在执行重启操作${Font}"
    fi
    echo -e "${Green}已从配置和开机自启动中移除所有 Socat 转发${Font}"
}

# 重启socat
re_socat(){
    kill_all_socat "noconfirm"
    sleep 2
    restore_forwards
}

# 改进的卸载socat
uninstall_socat() {
    if ! command -v socat >/dev/null 2>&1; then
        echo -e "${Red}错误：系统中未安装Socat，无需执行卸载操作${Font}"
        return 1
    fi
    
    echo -e "${Yellow}正在执行彻底卸载操作...${Font}"
    
    # 停止并清理所有服务
    kill_all_socat "uninstall"
    
    # 删除系统服务文件
    rm -f /etc/systemd/system/socat-*.{service,timer}
    systemctl daemon-reload
    
    # 删除配置目录和文件
    rm -rf "$SOCATS_DIR"
    [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"
    
    # 使用检测到的包管理器卸载
    local uninstall_success=0
    case "$PKG_MANAGER" in
        "apt")
            echo -e "${Yellow}正在通过apt卸载Socat...${Font}"
            apt-get remove -y socat && apt-get autoremove -y && uninstall_success=1
            ;;
        "yum")
            echo -e "${Yellow}正在通过yum卸载Socat...${Font}"
            yum remove -y socat && yum autoremove -y && uninstall_success=1
            ;;
        "dnf")
            echo -e "${Yellow}正在通过dnf卸载Socat...${Font}"
            dnf remove -y socat && dnf autoremove -y && uninstall_success=1
            ;;
        "pacman")
            echo -e "${Yellow}正在通过pacman卸载Socat...${Font}"
            pacman -Rns --noconfirm socat && uninstall_success=1
            ;;
        *)
            # 手动删除
            local socat_path=$(command -v socat 2>/dev/null)
            if [[ -n "$socat_path" ]]; then
                rm -f "$socat_path"
                [[ ! -f "$socat_path" ]] && uninstall_success=1
            fi
            ;;
    esac
    
    if [[ $uninstall_success -eq 1 ]] && ! command -v socat >/dev/null 2>&1; then
        echo -e "${Green}✅ Socat卸载验证通过${Font}"
    else
        echo -e "${Red}⚠️  Socat卸载未完成，请手动检查：${Font}"
        echo -e "${Yellow}1. which socat\n2. 残留进程: pgrep -f socat${Font}"
    fi
    
    echo -e "${Green}已成功卸载Socat及所有相关文件${Font}"
    
    # 询问是否同时卸载jq
    read -p "是否同时卸载jq？[y/N]: " uninstall_jq_confirm
    if [[ $uninstall_jq_confirm =~ ^[Yy]$ ]]; then
        echo -e "${Yellow}正在卸载jq...${Font}"
        uninstall_jq
    fi
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
    echo -e "${Yellow}3.${Font} Socat管理"
    echo -e "${Yellow}4.${Font} 开启端口转发加速"
    echo -e "${Yellow}5.${Font} 关闭端口转发加速"
    echo -e "${Yellow}6.${Font} 查看加速状态"
    echo -e "${Yellow}7.${Font} 设置域名监控频率"
    echo -e "${Yellow}8.${Font} 配置文件JSON格式化 ($([ "$JSON_FORMAT_ENABLED" -eq 1 ] && echo "开启" || echo "关闭"))"
    echo -e "${Yellow}9.${Font} 退出脚本"
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
    install_jq

    ip=$(get_ip)
    ipv6=$(get_ipv6)

    # 加载JSON格式化设置
    if [ -f "$SOCATS_DIR/.json_format" ]; then
        source "$SOCATS_DIR/.json_format"
    fi
    
    # 初始化标记检查
    if [ ! -f "$SOCATS_DIR/.initialized" ]; then
    init_config
    restore_forwards
    clear_screen
    touch "$SOCATS_DIR/.initialized"
    echo -e "${Green}所有配置和日志文件将保存在: $SOCATS_DIR${Font}"
    fi
    clear_screen
    

    #echo -e "${Green}所有配置和日志文件将保存在: $SOCATS_DIR${Font}"
    
    
    while true; do
        show_menu
        read -p "请输入选项 [1-9]: " choice
        clear_screen
        case $choice in
            1)
                if config_socat; then
                    start_socat
                    echo -e "${Green}Socat配置完成并成功启动！${Font}"
                    press_any_key
                elif [ $? -eq 1 ]; then
                    # 用户主动取消，不显示错误
                    echo -e "${Yellow}已取消配置操作${Font}"
                    clear_screen
                else
                    echo -e "${Red}配置失败，未能启动 Socat${Font}"
                    press_any_key
                fi
                
                ;;
            2)
                view_delete_forward
                press_any_key
                ;;
            3)
                manage_socat_menu
                clear_screen
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
                show_acceleration_status
                press_any_key
                ;;
            7)
                change_monitor_interval
                press_any_key
                ;;
            8)
                toggle_json_format
                press_any_key
                ;;
            9)
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
