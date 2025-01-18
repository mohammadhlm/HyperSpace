#!/bin/bash

# 定义颜色变量
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RESET='\033[0m'

# 日志文件路径
LOG_FILE="/root/script_progress.log"

# 记录日志的函数
log_message() {
    echo -e "$1"
    echo "$(date): $1" >> $LOG_FILE
}

# 重试函数
retry() {
    local n=1
    local delay=10
    while true; do
        "$@" && return 0
        log_message "第 $n 次尝试失败！将在 $delay 秒后重试..."
        sleep $delay
        ((n++))
    done
}

# 获取私钥的函数
get_private_key() {
    log_message "${CYAN}准备私钥...${RESET}"
    read -p "请输入你的私钥: " private_key
    echo -e "$private_key" > /root/my.pem
    chmod 600 /root/my.pem
    log_message "${GREEN}私钥已保存为 my.pem，并设置了正确的权限。${RESET}"
}

# 检查并安装Docker的函数
check_and_install_docker() {
    if ! command -v docker &> /dev/null; then
        log_message "${RED}未找到Docker。正在安装Docker...${RESET}"
        retry apt-get update -y
        retry apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        retry apt update -y
        retry apt install -y docker-ce
        systemctl start docker
        systemctl enable docker
        log_message "${GREEN}Docker已安装并启动。${RESET}"
    else
        log_message "${GREEN}Docker已安装。${RESET}"
    fi
}

# 启动Docker容器的函数
start_container() {
    log_message "${BLUE}正在启动Docker容器...${RESET}"
    retry docker run -d --name aios-container --restart unless-stopped -v /root:/root kartikhyper/aios /app/aios-cli start
    log_message "${GREEN}Docker容器已启动。${RESET}"
}

# 等待容器初始化的函数
wait_for_container_to_start() {
    log_message "${CYAN}正在等待容器初始化...${RESET}"
    sleep 60
}

# 安装本地模型的函数（增加重试逻辑）
install_local_model() {
    log_message "${BLUE}正在安装本地模型...${RESET}"
    # retry docker exec -i aios-container /app/aios-cli models add hf:TheBloke/Mistral-7B-Instruct-v0.1-GGUF:mistral-7b-instruct-v0.1.Q4_K_S.gguf
    retry docker exec -i aios-container /app/aios-cli models add hf:afrideva/Tiny-Vicuna-1B-GGUF:tiny-vicuna-1b.q4_k_m.gguf
    log_message "${GREEN}本地模型已成功安装。${RESET}"
}

# 登录Hive的函数
hive_login() {
    log_message "${CYAN}正在登录Hive...${RESET}"
    
    # 将登录和连接步骤视为一个整体，重试整个过程
    n=1
    delay=10
    while true; do
        docker exec -i aios-container /app/aios-cli kill && \
        docker exec -i aios-container /app/aios-cli hive import-keys /root/my.pem && \
        docker exec -i aios-container /app/aios-cli hive login && \
        docker exec -i aios-container /app/aios-cli hive select-tier 3 && \
        docker exec -i aios-container /app/aios-cli hive allocate 8 && \
        docker exec -i aios-container /app/aios-cli start --connect && \
        log_message "${GREEN}Hive登录成功。${RESET}" && return 0

        ((n++))
        log_message "Hive登录和连接失败，第 $n 次尝试失败！将在 $delay 秒后重试..."
        sleep $delay
        
    done
}

# 检查Hive积分的函数
check_hive_points() {
    log_message "${BLUE}正在检查Hive积分...${RESET}"
    docker exec -i aios-container /app/aios-cli hive points || log_message "${RED}无法获取Hive积分。${RESET}"
    log_message "${GREEN}Hive积分检查完成。${RESET}"
}

# 获取当前登录的密钥的函数
get_current_signed_in_keys() {
    log_message "${BLUE}正在获取当前登录的密钥...${RESET}"
    docker exec -i aios-container /app/aios-cli hive whoami
}

# 清理包列表的函数
cleanup_package_lists() {
    log_message "${BLUE}正在清理包列表...${RESET}"
    sudo rm -rf /var/lib/apt/lists/*
}

while true; do

    # 主脚本流程
    check_and_install_docker
    get_private_key
    start_container
    wait_for_container_to_start
    install_local_model
    hive_login
    check_hive_points
    get_current_signed_in_keys
    cleanup_package_lists

    log_message "${CYAN}已成功启动，休眠20分钟...${RESET}"
    sleep 1200  # 20分钟（1200秒）
done


log_message "${GREEN}所有步骤已成功完成！${RESET}"


