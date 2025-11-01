#!/bin/bash
# filepath: f:\roger\script_v2.sh

# 定义颜色常量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NODE_INFO_FILE="$HOME/.xray_nodes_info"
PROJECT_DIR="python-xray-argo"

# 生成UUID函数（优先使用uuidgen，其次python3，最后使用/dev/urandom）
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command -v python3 &> /dev/null; then
        python3 -c "import uuid; print(uuid.uuid4())"
    else
        hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom | \
        sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/' | \
        tr '[:upper:]' '[:lower:]'
    fi
}

# 显示节点信息并退出
view_nodes() {
    if [ -f "$NODE_INFO_FILE" ]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}           节点信息查看               ${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo
        cat "$NODE_INFO_FILE"
        echo
    else
        echo -e "${RED}未找到节点信息文件${NC}"
        echo -e "${YELLOW}请先运行部署脚本生成节点信息${NC}"
    fi
    exit 0
}

# 如果传参为 -v 则直接显示节点信息
if [ "$1" == "-v" ]; then
    view_nodes
fi

clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    Python Xray Argo 一键部署脚本    ${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}项目地址: ${YELLOW}https://github.com/eooce/python-xray-argo${NC}"
echo -e "${BLUE}脚本仓库: ${YELLOW}https://github.com/byJoey/free-vps-py${NC}"
echo
echo -e "${GREEN}基于 eooce 大佬的项目开发，集极速配置和完整配置模式${NC}"
echo -e "${GREEN}支持自动UUID生成、后台启动、节点信息保存及YouTube分流配置${NC}"
echo

# 主菜单选择
echo -e "${YELLOW}请选择操作:${NC}"
echo -e "${BLUE}1) 极速模式 - 仅变更UUID并启动${NC}"
echo -e "${BLUE}2) 完整模式 - 配置全部选项${NC}"
echo -e "${BLUE}3) 查看节点信息${NC}"
echo
read -p "请输入选项 (1/2/3): " MODE

# 如果选择查看节点信息
if [ "$MODE" == "3" ]; then
    view_nodes
    # 若未部署，则询问是否开始部署
    echo -e "${BLUE}是否重新部署? (y/n)${NC}"
    read -p "> " deploy_choice
    if [[ "$deploy_choice" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}请选择部署模式:${NC}"
        echo -e "${BLUE}1) 极速模式${NC}"
        echo -e "${BLUE}2) 完整模式${NC}"
        read -p "请输入选项 (1/2): " MODE
    else
        echo -e "${GREEN}退出脚本${NC}"
        exit 0
    fi
fi

check_installations() {
    echo -e "${BLUE}检查依赖环境...${NC}"
    if ! command -v python3 &> /dev/null; then
        echo -e "${YELLOW}检测到无Python3，正在安装...${NC}"
        sudo apt-get update && sudo apt-get install -y python3 python3-pip
    fi
    if ! python3 -c "import requests" &> /dev/null; then
        echo -e "${YELLOW}安装requests模块...${NC}"
        pip3 install requests
    fi
}

download_project() {
    if [ ! -d "$PROJECT_DIR" ]; then
        echo -e "${BLUE}下载项目仓库...${NC}"
        if command -v git &> /dev/null; then
            git clone https://github.com/eooce/python-xray-argo.git
        else
            echo -e "${YELLOW}Git未安装，尝试wget...${NC}"
            wget -q https://github.com/eooce/python-xray-argo/archive/refs/heads/main.zip -O project.zip
            if command -v unzip &> /dev/null; then
                unzip -q project.zip
                mv python-xray-argo-main "$PROJECT_DIR"
                rm project.zip
            else
                echo -e "${YELLOW}安装unzip...${NC}"
                sudo apt-get install -y unzip
                unzip -q project.zip
                mv python-xray-argo-main "$PROJECT_DIR"
                rm project.zip
            fi
        fi

        if [ $? -ne 0 ] || [ ! -d "$PROJECT_DIR" ]; then
            echo -e "${RED}项目下载失败，请检查网络连接${NC}"
            exit 1
        fi
    fi
}

# 执行依赖检查和下载项目
check_installations
download_project
cd "$PROJECT_DIR" || exit 1

# 检查 app.py 是否存在
if [ ! -f "app.py" ]; then
    echo -e "${RED}未找到app.py文件！${NC}"
    exit 1
fi

# 备份app.py
cp app.py app.py.bak
echo -e "${YELLOW}已备份app.py为 app.py.bak${NC}"

update_file() {
    # 参数：更新类型 UUID/NAME/PORT/CFIP/CFPORT/ARGO_PORT/ARGO_DOMAIN/ARGO_AUTH
    local key="$1"
    local value="$2"
    local pattern=""
    local repl=""
    case "$key" in
        UUID)
            pattern="UUID = os.environ.get('UUID', '[^']*')"
            repl="UUID = os.environ.get('UUID', '$value')"
            ;;
        NAME)
            pattern="NAME = os.environ.get('NAME', '[^']*')"
            repl="NAME = os.environ.get('NAME', '$value')"
            ;;
        PORT)
            pattern="PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or [0-9]*)"
            repl="PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or $value)"
            ;;
        CFIP)
            pattern="CFIP = os.environ.get('CFIP', '[^']*')"
            repl="CFIP = os.environ.get('CFIP', '$value')"
            ;;
        CFPORT)
            pattern="CFPORT = int(os.environ.get('CFPORT', '[^']*'))"
            repl="CFPORT = int(os.environ.get('CFPORT', '$value'))"
            ;;
        ARGO_PORT)
            pattern="ARGO_PORT = int(os.environ.get('ARGO_PORT', '[^']*'))"
            repl="ARGO_PORT = int(os.environ.get('ARGO_PORT', '$value'))"
            ;;
        ARGO_DOMAIN)
            pattern="ARGO_DOMAIN = os.environ.get('ARGO_DOMAIN', '[^']*')"
            repl="ARGO_DOMAIN = os.environ.get('ARGO_DOMAIN', '$value')"
            ;;
        ARGO_AUTH)
            pattern="ARGO_AUTH = os.environ.get('ARGO_AUTH', '[^']*')"
            repl="ARGO_AUTH = os.environ.get('ARGO_AUTH', '$value')"
            ;;
        *)
            return
            ;;
    esac
    sed -i "s/$pattern/$repl/" app.py
}

# 极速模式操作
if [ "$MODE" == "1" ]; then
    echo -e "${BLUE}【极速模式】${NC}"
    current_uuid=$(grep "UUID = " app.py | head -1 | cut -d"'" -f2)
    echo -e "${YELLOW}当前UUID: $current_uuid${NC}"
    read -p "请输入新UUID（留空自动生成）： " new_uuid
    if [ -z "$new_uuid" ]; then
        new_uuid=$(generate_uuid)
        echo -e "${GREEN}自动生成UUID: $new_uuid${NC}"
    fi
    update_file UUID "$new_uuid"
    update_file CFIP "joeyblog.net"
    echo -e "${GREEN}UUID和优选IP均已设置完成${NC}"

# 完整模式操作
elif [ "$MODE" == "2" ]; then
    echo -e "${BLUE}【完整模式】${NC}"
    current_uuid=$(grep "UUID = " app.py | head -1 | cut -d"'" -f2)
    echo -e "${YELLOW}当前UUID： $current_uuid${NC}"
    read -p "请输入新UUID（留空自动生成）： " new_uuid
    if [ -z "$new_uuid" ]; then
        new_uuid=$(generate_uuid)
        echo -e "${GREEN}自动生成UUID: $new_uuid${NC}"
    fi
    update_file UUID "$new_uuid"
    
    current_name=$(grep "NAME = " app.py | head -1 | cut -d"'" -f2)
    echo -e "${YELLOW}当前节点名称: $current_name${NC}"
    read -p "请输入新节点名称（留空保持不变）： " new_name
    if [ -n "$new_name" ]; then
        update_file NAME "$new_name"
    fi

    port_val=$(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)
    echo -e "${YELLOW}当前服务端口: $port_val${NC}"
    read -p "请输入服务端口（留空保持不变）： " new_port
    if [ -n "$new_port" ]; then
        update_file PORT "$new_port"
    fi

    current_cfip=$(grep "CFIP = " app.py | cut -d"'" -f2)
    echo -e "${YELLOW}当前优选IP: $current_cfip${NC}"
    read -p "请输入优选IP/域名（留空使用默认）： " new_cfip
    [ -z "$new_cfip" ] && new_cfip="joeyblog.net"
    update_file CFIP "$new_cfip"

    current_cfport=$(grep "CFPORT = " app.py | cut -d"'" -f2)
    echo -e "${YELLOW}当前优选端口: $current_cfport${NC}"
    read -p "请输入优选端口（留空保持不变）： " new_cfport
    if [ -n "$new_cfport" ]; then
        update_file CFPORT "$new_cfport"
    fi

    current_argo_port=$(grep "ARGO_PORT = " app.py | cut -d"'" -f2)
    echo -e "${YELLOW}当前Argo端口: $current_argo_port${NC}"
    read -p "请输入Argo端口（留空保持不变）： " new_argo_port
    if [ -n "$new_argo_port" ]; then
        update_file ARGO_PORT "$new_argo_port"
    fi

    read -p "是否配置高级选项? (y/n): " adv_choice
    if [[ "$adv_choice" =~ ^[Yy]$ ]]; then
        current_domain=$(grep "ARGO_DOMAIN = " app.py | cut -d"'" -f2)
        echo -e "${YELLOW}当前Argo域名: $current_domain${NC}"
        read -p "请输入固定隧道域名（留空保持不变）： " new_domain
        if [ -n "$new_domain" ]; then
            update_file ARGO_DOMAIN "$new_domain"
            current_auth=$(grep "ARGO_AUTH = " app.py | cut -d"'" -f2)
            echo -e "${YELLOW}当前Argo密钥: $current_auth${NC}"
            read -p "请输入固定隧道密钥: " new_auth
            if [ -n "$new_auth" ]; then
                update_file ARGO_AUTH "$new_auth"
            fi
            echo -e "${GREEN}固定隧道参数已更新${NC}"
        fi
    fi
    echo -e "${GREEN}完整配置完成${NC}"
fi

# 显示配置摘要
echo -e "${YELLOW}=== 当前配置信息 ===${NC}"
echo -e "UUID: $(grep "UUID = " app.py | head -1 | cut -d"'" -f2)"
echo -e "节点名称: $(grep "NAME = " app.py | head -1 | cut -d"'" -f2)"
echo -e "服务端口: $(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)"
echo -e "优选IP: $(grep "CFIP = " app.py | cut -d"'" -f2)"
echo -e "优选端口: $(grep "CFPORT = " app.py | cut -d"'" -f2)"
echo -e "${YELLOW}========================${NC}"
echo

# 添加YouTube分流和80端口节点补丁
echo -e "${BLUE}正在更新YouTube分流及80端口配置…${NC}"
cat > patch_yt.sh << 'EOF_PATCH'
#!/bin/bash
# 读取并替换文件中的配置内容
FILE="app.py"
content=$(< "$FILE")

# 定义原始配置块与新的配置块（注意这里需要匹配完整字符串）
old_config="config ={\"log\":{\"access\":\"/dev/null\",\"error\":\"/dev/null\",\"loglevel\":\"none\",},\"inbounds\":[{\"port\":ARGO_PORT ,\"protocol\":\"vless\",\"settings\":{\"clients\":[{\"id\":UUID ,\"flow\":\"xtls-rprx-vision\",},],\"decryption\":\"none\",\"fallbacks\":[{\"dest\":3001 },{\"path\":\"/vless-argo\",\"dest\":3002 },{\"path\":\"/vmess-argo\",\"dest\":3003 },{\"path\":\"/trojan-argo\",\"dest\":3004 },],},\"streamSettings\":{\"network\":\"tcp\",},},{\"port\":3001 ,\"listen\":\"127.0.0.1\",\"protocol\":\"vless\",\"settings\":{\"clients\":[{\"id\":UUID },],\"decryption\":\"none\"},\"streamSettings\":{\"network\":\"ws\",\"security\":\"none\"}},{\"port\":3002 ,\"listen\":\"127.0.0.1\",\"protocol\":\"vless\",\"settings\":{\"clients\":[{\"id\":UUID ,\"level\":0 }],\"decryption\":\"none\"},\"streamSettings\":{\"network\":\"ws\",\"security\":\"none\",\"wsSettings\":{\"path\":\"/vless-argo\"}},\"sniffing\":{\"enabled\":True ,\"destOverride\":[\"http\",\"tls\",\"quic\"],\"metadataOnly\":False }},{\"port\":3003 ,\"listen\":\"127.0.0.1\",\"protocol\":\"vmess\",\"settings\":{\"clients\":[{\"id\":UUID ,\"alterId\":0 }]},\"streamSettings\":{\"network\":\"ws\",\"wsSettings\":{\"path\":\"/vmess-argo\"}},\"sniffing\":{\"enabled\":True ,\"destOverride\":[\"http\",\"tls\",\"quic\"],\"metadataOnly\":False }},{\"port\":3004 ,\"listen\":\"127.0.0.1\",\"protocol\":\"trojan\",\"settings\":{\"clients\":[{\"password\":UUID },]},\"streamSettings\":{\"network\":\"ws\",\"security\":\"none\",\"wsSettings\":{\"path\":\"/trojan-argo\"}},\"sniffing\":{\"enabled\":True ,\"destOverride\":[\"http\",\"tls\",\"quic\"],\"metadataOnly\":False }}],\"outbounds\":[{\"protocol\":\"freedom\",\"tag\": \"direct\" },{\"protocol\":\"blackhole\",\"tag\":\"block\"}]}"
new_config="config = {
        \"log\": {
            \"access\": \"/dev/null\",
            \"error\": \"/dev/null\",
            \"loglevel\": \"none\"
        },
        \"inbounds\": [
            {
                \"port\": ARGO_PORT,
                \"protocol\": \"vless\",
                \"settings\": {
                    \"clients\": [{\"id\": UUID, \"flow\": \"xtls-rprx-vision\"}],
                    \"decryption\": \"none\",
                    \"fallbacks\": [
                        {\"dest\": 3001},
                        {\"path\": \"/vless-argo\", \"dest\": 3002},
                        {\"path\": \"/vmess-argo\", \"dest\": 3003},
                        {\"path\": \"/trojan-argo\", \"dest\": 3004}
                    ]
                },
                \"streamSettings\": {\"network\": \"tcp\"}
            },
            {
                \"port\": 3001,
                \"listen\": \"127.0.0.1\",
                \"protocol\": \"vless\",
                \"settings\": {
                    \"clients\": [{\"id\": UUID}],
                    \"decryption\": \"none\"
                },
                \"streamSettings\": {\"network\": \"ws\", \"security\": \"none\"}
            },
            {
                \"port\": 3002,
                \"listen\": \"127.0.0.1\",
                \"protocol\": \"vless\",
                \"settings\": {
                    \"clients\": [{\"id\": UUID, \"level\": 0}],
                    \"decryption\": \"none\"
                },
                \"streamSettings\": {
                    \"network\": \"ws\",
                    \"security\": \"none\",
                    \"wsSettings\": {\"path\": \"/vless-argo\"}
                },
                \"sniffing\": {
                    \"enabled\": true,
                    \"destOverride\": [\"http\", \"tls\", \"quic\"],
                    \"metadataOnly\": false
                }
            },
            {
                \"port\": 3003,
                \"listen\": \"127.0.0.1\",
                \"protocol\": \"vmess\",
                \"settings\": {
                    \"clients\": [{\"id\": UUID, \"alterId\": 0}]
                },
                \"streamSettings\": {
                    \"network\": \"ws\",
                    \"wsSettings\": {\"path\": \"/vmess-argo\"}
                },
                \"sniffing\": {
                    \"enabled\": true,
                    \"destOverride\": [\"http\", \"tls\", \"quic\"],
                    \"metadataOnly\": false
                }
            },
            {
                \"port\": 3004,
                \"listen\": \"127.0.0.1\",
                \"protocol\": \"trojan\",
                \"settings\": {
                    \"clients\": [{\"password\": UUID}]
                },
                \"streamSettings\": {
                    \"network\": \"ws\",
                    \"security\": \"none\",
                    \"wsSettings\": {\"path\": \"/trojan-argo\"}
                },
                \"sniffing\": {
                    \"enabled\": true,
                    \"destOverride\": [\"http\", \"tls\", \"quic\"],
                    \"metadataOnly\": false
                }
            }
        ],
        \"outbounds\": [
            {\"protocol\": \"freedom\", \"tag\": \"direct\"},
            {
                \"protocol\": \"vmess\",
                \"tag\": \"youtube\",
                \"settings\": {
                    \"vnext\": [{
                        \"address\": \"172.233.171.224\",
                        \"port\": 16416,
                        \"users\": [{
                            \"id\": \"8c1b9bea-cb51-43bb-a65c-0af31bbbf145\",
                            \"alterId\": 0
                        }]
                    }]
                },
                \"streamSettings\": {\"network\": \"tcp\"}
            },
            {\"protocol\": \"blackhole\", \"tag\": \"block\"}
        ],
        \"routing\": {
            \"domainStrategy\": \"IPIfNonMatch\",
            \"rules\": [
                {
                    \"type\": \"field\",
                    \"domain\": [
                        \"youtube.com\",
                        \"googlevideo.com\",
                        \"ytimg.com\",
                        \"gstatic.com\",
                        \"googleapis.com\",
                        \"ggpht.com\",
                        \"googleusercontent.com\"
                    ],
                    \"outboundTag\": \"youtube\"
                }
            ]
        }
    }"
content=${content//$old_config/$new_config}

# 替换 generate_links 函数
old_gen_func="# Generate links and subscription content
async def generate_links(argo_domain):
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('\"')
    ISP = f\"{meta_info[25]}-{meta_info[17]}\".replace(' ', '_').strip()
    time.sleep(2)
    VMESS = {\"v\": \"2\", \"ps\": f\"{NAME}-{ISP}\", \"add\": CFIP, \"port\": CFPORT, \"id\": UUID, \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": argo_domain, \"path\": \"/vmess-argo?ed=2560\", \"tls\": \"tls\", \"sni\": argo_domain, \"alpn\": \"\", \"fp\": \"chrome\"}
    list_txt = f\"\"\"
vless://{UUID}@{CFIP}:{CFPORT}?encryption=none&security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{NAME}-{ISP}
vmess://{ base64.b64encode(json.dumps(VMESS).encode('utf-8')).decode('utf-8')}
trojan://{UUID}@{CFIP}:{CFPORT}?security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{NAME}-{ISP}
    \"\"\"
    with open(os.path.join(FILE_PATH, 'list.txt'), 'w', encoding='utf-8') as list_file:
        list_file.write(list_txt)
    sub_txt = base64.b64encode(list_txt.encode('utf-8')).decode('utf-8')
    with open(os.path.join(FILE_PATH, 'sub.txt'), 'w', encoding='utf-8') as sub_file:
        sub_file.write(sub_txt)
    print(sub_txt)
    print(f\"{FILE_PATH}/sub.txt saved successfully\")
    send_telegram()
    upload_nodes()
    return sub_txt"
new_gen_func="# Generate links and subscription content
async def generate_links(argo_domain):
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('\"')
    ISP = f\"{meta_info[25]}-{meta_info[17]}\".replace(' ', '_').strip()
    time.sleep(2)
    VMESS_TLS = {\"v\": \"2\", \"ps\": f\"{NAME}-{ISP}-TLS\", \"add\": CFIP, \"port\": CFPORT, \"id\": UUID, \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": argo_domain, \"path\": \"/vmess-argo?ed=2560\", \"tls\": \"tls\", \"sni\": argo_domain, \"alpn\": \"\", \"fp\": \"chrome\"}
    VMESS_80 = {\"v\": \"2\", \"ps\": f\"{NAME}-{ISP}-80\", \"add\": CFIP, \"port\": \"80\", \"id\": UUID, \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": argo_domain, \"path\": \"/vmess-argo?ed=2560\", \"tls\": \"\", \"sni\": \"\", \"alpn\": \"\", \"fp\": \"\"}
    list_txt = f\"\"\"
vless://{UUID}@{CFIP}:{CFPORT}?encryption=none&security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{NAME}-{ISP}-TLS
vmess://{ base64.b64encode(json.dumps(VMESS_TLS).encode('utf-8')).decode('utf-8')}
trojan://{UUID}@{CFIP}:{CFPORT}?security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{NAME}-{ISP}-TLS
vless://{UUID}@{CFIP}:80?encryption=none&security=none&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{NAME}-{ISP}-80
vmess://{ base64.b64encode(json.dumps(VMESS_80).encode('utf-8')).decode('utf-8')}
trojan://{UUID}@{CFIP}:80?security=none&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{NAME}-{ISP}-80
    \"\"\"
    with open(os.path.join(FILE_PATH, 'list.txt'), 'w', encoding='utf-8') as list_file:
        list_file.write(list_txt)
    sub_txt = base64.b64encode(list_txt.encode('utf-8')).decode('utf-8')
    with open(os.path.join(FILE_PATH, 'sub.txt'), 'w', encoding='utf-8') as sub_file:
        sub_file.write(sub_txt)
    print(sub_txt)
    print(f\"{FILE_PATH}/sub.txt saved successfully\")
    send_telegram()
    upload_nodes()
    return sub_txt"
content=${content//$old_gen_func/$new_gen_func}
echo "$content" > "$FILE"
echo "YouTube分流及80端口配置已更新"
EOF_PATCH

chmod +x patch_yt.sh
./patch_yt.sh
rm patch_yt.sh

# 启动服务前先杀掉旧进程
pkill -f "python3 app.py" > /dev/null 2>&1
sleep 2

# 后台启动服务，并记录日志和PID
nohup python3 app.py > app.log 2>&1 &
APP_PID=$!

# 尝试获取进程PID
if [ -z "$APP_PID" ] || [ "$APP_PID" -eq 0 ]; then
    sleep 2
    APP_PID=$(pgrep -f "python3 app.py" | head -1)
    if [ -z "$APP_PID" ]; then
        echo -e "${RED}服务启动失败！${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}服务启动成功，PID: $APP_PID${NC}"
echo -e "${YELLOW}日志文件路径: $(pwd)/app.log${NC}"

# 等待服务启动及节点信息生成
echo -e "${BLUE}等待服务启动并生成节点信息...${NC}"
MAX_WAIT=600  # 最大等待时间600秒
WAITED=0
NODE_INFO=""
while [ $WAITED -lt $MAX_WAIT ]; do
    if [ -f ".cache/sub.txt" ]; then
        NODE_INFO=$(cat .cache/sub.txt)
    elif [ -f "sub.txt" ]; then
        NODE_INFO=$(cat sub.txt)
    fi
    if [ -n "$NODE_INFO" ]; then
        echo -e "${GREEN}节点信息已生成${NC}"
        break
    fi
    if [ $((WAITED % 30)) -eq 0 ]; then
        echo -e "${YELLOW}已等待 ${WAITED}s，继续等待...${NC}"
    fi
    sleep 5
    WAITED=$((WAITED+5))
done

if [ -z "$NODE_INFO" ]; then
    echo -e "${RED}等待超时，未生成节点信息${NC}"
    exit 1
fi

# 显示服务和节点信息
SERVICE_PORT=$(grep "PORT = int" app.py | grep -o "or [0-9]*" | cut -d" " -f2)
CURRENT_UUID=$(grep "UUID = " app.py | head -1 | cut -d"'" -f2)
SUB_PATH=$(grep "SUB_PATH = " app.py | cut -d"'" -f2)

echo -e "${YELLOW}========= 服务信息 =========${NC}"
echo -e "状态: ${GREEN}运行中${NC}"
echo -e "PID: ${BLUE}$APP_PID${NC}"
echo -e "服务端口: ${BLUE}$SERVICE_PORT${NC}"
echo -e "UUID: ${BLUE}$CURRENT_UUID${NC}"
echo -e "${YELLOW}============================${NC}"
echo

echo -e "${YELLOW}========= 节点信息 =========${NC}"
DECODED_NODES=$(echo "$NODE_INFO" | base64 -d 2>/dev/null || echo "$NODE_INFO")
echo -e "${GREEN}$DECODED_NODES${NC}"
echo

# 保存节点信息至文件
SAVE_INFO="========================================
           节点信息保存
========================================

部署时间: $(date)
UUID: $CURRENT_UUID
服务端口: $SERVICE_PORT
订阅路径: /$SUB_PATH

=== 访问地址 ==="
if command -v curl &> /dev/null; then
    PUBLIC_IP=$(curl -s https://api.ipify.org || echo "未知")
    SAVE_INFO="${SAVE_INFO}
订阅地址: http://$PUBLIC_IP:$SERVICE_PORT/$SUB_PATH
管理面板: http://$PUBLIC_IP:$SERVICE_PORT"
fi
SAVE_INFO="${SAVE_INFO}
本地订阅: http://localhost:$SERVICE_PORT/$SUB_PATH
本地面板: http://localhost:$SERVICE_PORT

=== 节点配置 ===
$DECODED_NODES

=== 管理命令 ===
查看日志: tail -f $(pwd)/app.log
停止服务: kill $APP_PID
重启服务: kill $APP_PID && nohup python3 app.py > app.log 2>&1 &
查看进程: ps aux | grep python3

=== 分流说明 ===
- 系统已自动添加YouTube分流及80端口节点"
echo "$SAVE_INFO" > "$NODE_INFO_FILE"
echo -e "${GREEN}节点信息保存至: $NODE_INFO_FILE${NC}"
echo -e "${GREEN}部署完成！感谢使用！${NC}"

exit 0
