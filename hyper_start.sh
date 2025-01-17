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
    local max=20
    local delay=10
    while true; do
        "$@" && return 0
        if (( n == max )); then
            return 1
        else
            log_message "第 $n/$max 次尝试失败！将在 $delay 秒后重试..."
            sleep $delay
        fi
        ((n++))
    done
}

# 显示Logo的函数（已替换为新的curl命令）
display_logo() {
    log_message "${GREEN}正在显示Logo...${RESET}"
    curl -s https://raw.githubusercontent.com/ziqing888/logo.sh/refs/heads/main/logo.sh | bash || handle_error "获取Logo脚本失败。"
}

# 处理错误的函数
handle_error() {
    log_message "$1"
    exit 1
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
        retry apt-get update -y || handle_error "更新apt包列表失败。"
        retry apt-get install -y apt-transport-https ca-certificates curl software-properties-common || handle_error "安装依赖包失败。"
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - || handle_error "添加Docker GPG密钥失败。"
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" || handle_error "添加Docker仓库失败。"
        retry apt update -y || handle_error "更新apt包列表失败。"
        retry apt install -y docker-ce || handle_error "安装Docker CE失败。"
        systemctl start docker || handle_error "启动Docker失败。"
        systemctl enable docker || handle_error "设置Docker开机自启失败。"
        log_message "${GREEN}Docker已安装并启动。${RESET}"
    else
        log_message "${GREEN}Docker已安装。${RESET}"
    fi
}

# 启动Docker容器的函数
start_container() {
    log_message "${BLUE}正在启动Docker容器...${RESET}"
    retry docker run -d --name aios-container --restart unless-stopped -v /root:/root kartikhyper/aios /app/aios-cli start || handle_error "启动Docker容器失败。"
    log_message "${GREEN}Docker容器已启动。${RESET}"
}

# 等待容器初始化的函数
wait_for_container_to_start() {
    log_message "${CYAN}正在等待容器初始化...${RESET}"
    sleep 60
}

# 检查守护进程状态的函数
check_daemon_status() {
    log_message "${BLUE}正在检查容器内的守护进程状态...${RESET}"
    docker exec -i aios-container /app/aios-cli status
    if [[ $? -ne 0 ]]; then
        log_message "${RED}守护进程未运行，正在重启...${RESET}"
        docker exec -i aios-container /app/aios-cli kill
        sleep 2
        docker exec -i aios-container /app/aios-cli start
        log_message "${GREEN}守护进程已重启。${RESET}"
    else
        log_message "${GREEN}守护进程正在运行。${RESET}"
    fi
}

# 安装本地模型的函数（增加重试逻辑）
install_local_model() {
    log_message "${BLUE}正在安装本地模型...${RESET}"
    local n=1
    local max=5
    local delay=10
    while true; do
        docker exec -i aios-container /app/aios-cli models add hf:TheBloke/Mistral-7B-Instruct-v0.1-GGUF:mistral-7b-instruct-v0.1.Q4_K_S.gguf && \
        log_message "${GREEN}本地模型已成功安装。${RESET}" && return 0
        
        log_message "安装本地模型失败，第 $n 次尝试失败！将在 $delay 秒后重试..."
        sleep $delay
        ((n++))
        if (( n > max )); then
            handle_error "安装本地模型失败，重试次数超限。"
        fi
    done
}

# 运行推理的函数
run_infer() {
    log_message "${BLUE}正在运行推理...${RESET}"
    retry docker exec -i aios-container /app/aios-cli infer --model hf:TheBloke/Mistral-7B-Instruct-v0.1-GGUF:mistral-7b-instruct-v0.1.Q4_K_S.gguf --prompt "What is 'Artificial Intelligence'?" || handle_error "推理任务失败。"
    log_message "${GREEN}推理任务成功完成。${RESET}"
}

# 登录Hive的函数
hive_login() {
    log_message "${CYAN}正在登录Hive...${RESET}"
    local n=1
    local max=5
    local delay=10
    while true; do
        docker exec -i aios-container /app/aios-cli hive import-keys /root/my.pem && \
        docker exec -i aios-container /app/aios-cli hive login && \
        docker exec -i aios-container /app/aios-cli hive connect && \
        log_message "${GREEN}Hive登录成功。${RESET}" && return 0
        
        log_message "Hive登录失败，第 $n 次尝试失败！将在 $delay 秒后重试..."
        sleep $delay
        ((n++))
        if (( n > max )); then
            handle_error "Hive登录失败，重试次数超限。"
        fi
    done
}

# 运行Hive推理的函数
run_hive_infer() {
    log_message "${BLUE}正在运行Hive推理...${RESET}"
    retry docker exec -i aios-container /app/aios-cli hive infer --model hf:TheBloke/Mistral-7B-Instruct-v0.1-GGUF:mistral-7b-instruct-v0.1.Q4_K_S.gguf --prompt "Explain what a server is in simple terms." || handle_error "Hive推理任务失败。"
    log_message "${GREEN}Hive推理任务成功完成。${RESET}"
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
    docker exec -i aios-container /app/aios-cli hive whoami || handle_error "获取当前登录的密钥失败。"
}

# 清理包列表的函数
cleanup_package_lists() {
    log_message "${BLUE}正在清理包列表...${RESET}"
    sudo rm -rf /var/lib/apt/lists/* || handle_error "清理包列表失败。"
}

# 主脚本流程
display_logo
check_and_install_docker
get_private_key
start_container
wait_for_container_to_start
check_daemon_status
install_local_model
run_infer
hive_login
run_hive_infer
check_hive_points
get_current_signed_in_keys
cleanup_package_lists

log_message "${GREEN}所有步骤已成功完成！${RESET}"

# 每小时重复执行的循环
while true; do
    log_message "${CYAN}每1小时重启一次进程...${RESET}"

    docker exec -i aios-container /app/aios-cli kill || log_message "${RED}杀死守护进程失败。${RESET}"

    docker exec -i aios-container /app/aios-cli status
    if [[ $? -ne 0 ]]; then
        log_message "${RED}守护进程启动失败，正在重试...${RESET}"
    else
        log_message "${GREEN}守护进程正在运行，状态已检查。${RESET}"
    fi

    sleep 3600
done
