#!/bin/bash

# PostgreSQL网络连接问题故障排除脚本
# 专门用于诊断和修复容器间无法通过"postgres"主机名连接的问题

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置变量
NETWORK_NAME="yuyingbao-network"
CONTAINER_NAME="yuyingbao-server"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  PostgreSQL网络连接故障排除脚本${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# 检查容器状态
check_containers() {
    echo -e "${BLUE}🔍 检查容器状态...${NC}"
    
    echo -e "${CYAN}应用容器状态:${NC}"
    if docker ps | grep -q "${CONTAINER_NAME}"; then
        echo -e "${GREEN}✅ 应用容器正在运行${NC}"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "${CONTAINER_NAME}"
    else
        echo -e "${RED}❌ 应用容器未运行${NC}"
        if docker ps -a | grep -q "${CONTAINER_NAME}"; then
            echo "容器存在但已停止，查看最近日志："
            docker logs --tail=10 "${CONTAINER_NAME}"
        fi
    fi
    
    echo ""
    echo -e "${CYAN}数据库容器状态:${NC}"
    if docker ps | grep -q "yuyingbao-postgres"; then
        echo -e "${GREEN}✅ 数据库容器正在运行${NC}"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "yuyingbao-postgres"
    else
        echo -e "${RED}❌ 数据库容器未运行${NC}"
        if docker ps -a | grep -q "yuyingbao-postgres"; then
            echo "容器存在但已停止，查看最近日志："
            docker logs --tail=10 "yuyingbao-postgres"
        fi
    fi
    echo ""
}

# 检查网络配置
check_network() {
    echo -e "${BLUE}🌐 检查Docker网络配置...${NC}"
    
    # 检查网络是否存在
    if docker network ls | grep -q "${NETWORK_NAME}"; then
        echo -e "${GREEN}✅ 网络存在: ${NETWORK_NAME}${NC}"
        
        # 显示网络详情
        echo -e "${CYAN}网络配置:${NC}"
        docker network inspect ${NETWORK_NAME} --format='Driver: {{.Driver}}, Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}'
        
        # 检查容器是否在网络中
        echo -e "${CYAN}网络中的容器:${NC}"
        local containers_in_network=$(docker network inspect ${NETWORK_NAME} --format='{{range .Containers}}{{.Name}} {{end}}')
        
        if [[ -n "$containers_in_network" ]]; then
            echo "  $containers_in_network"
            
            # 检查每个重要容器
            if echo "$containers_in_network" | grep -q "yuyingbao-postgres"; then
                echo -e "  ${GREEN}✅ PostgreSQL容器在网络中${NC}"
            else
                echo -e "  ${RED}❌ PostgreSQL容器不在网络中${NC}"
            fi
            
            if echo "$containers_in_network" | grep -q "${CONTAINER_NAME}"; then
                echo -e "  ${GREEN}✅ 应用容器在网络中${NC}"
            else
                echo -e "  ${RED}❌ 应用容器不在网络中${NC}"
            fi
        else
            echo -e "  ${RED}❌ 网络中没有容器${NC}"
        fi
    else
        echo -e "${RED}❌ 网络不存在: ${NETWORK_NAME}${NC}"
    fi
    echo ""
}

# 测试网络连接
test_connectivity() {
    echo -e "${BLUE}🔌 测试网络连接...${NC}"
    
    # 检查容器是否都在运行
    if ! docker ps | grep -q "yuyingbao-postgres"; then
        echo -e "${RED}❌ PostgreSQL容器未运行，无法测试连接${NC}"
        return 1
    fi
    
    if ! docker ps | grep -q "${CONTAINER_NAME}"; then
        echo -e "${RED}❌ 应用容器未运行，无法测试连接${NC}"
        return 1
    fi
    
    # 获取PostgreSQL容器IP地址
    local postgres_ip=$(docker inspect yuyingbao-postgres --format="{{.NetworkSettings.Networks.${NETWORK_NAME}.IPAddress}}")
    if [[ -z "$postgres_ip" || "$postgres_ip" == "<no value>" ]]; then
        postgres_ip=$(docker inspect yuyingbao-postgres --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
    fi
    echo -e "${CYAN}PostgreSQL容器IP地址: ${postgres_ip}${NC}"
    
    # 检查应用容器的hosts配置
    echo -e "${CYAN}检查应用容器的DNS解析:${NC}"
    docker exec "${CONTAINER_NAME}" cat /etc/hosts | grep -E "(postgres|yuyingbao-postgres)" || echo "未找到postgres相关的hosts映射"
    
    # 从应用容器测试连接
    echo -e "${CYAN}从应用容器测试连接到数据库:${NC}"
    
    # 测试DNS解析 - 使用实际的容器名
    echo -n "  DNS解析测试 (yuyingbao-postgres): "
    if docker exec "${CONTAINER_NAME}" nslookup yuyingbao-postgres &>/dev/null; then
        echo -e "${GREEN}✅ 成功${NC}"
        # 显示解析结果
        local resolved_ip=$(docker exec "${CONTAINER_NAME}" nslookup yuyingbao-postgres | grep "Address:" | tail -1 | awk '{print $2}')
        echo "    解析IP: $resolved_ip"
        if [[ "$resolved_ip" == "$postgres_ip" ]]; then
            echo -e "    ${GREEN}✅ IP地址匹配正确${NC}"
        else
            echo -e "    ${YELLOW}⚠️  IP地址不匹配（期望: $postgres_ip，实际: $resolved_ip）${NC}"
        fi
    else
        echo -e "${RED}❌ 失败${NC}"
    fi
    
    # 测试ping
    echo -n "  Ping测试: "
    if docker exec "${CONTAINER_NAME}" ping -c 2 yuyingbao-postgres &>/dev/null; then
        echo -e "${GREEN}✅ 成功${NC}"
    else
        echo -e "${RED}❌ 失败${NC}"
    fi
    
    # 测试端口连接
    echo -n "  端口连接测试 (5432): "
    if docker exec "${CONTAINER_NAME}" nc -z yuyingbao-postgres 5432 &>/dev/null; then
        echo -e "${GREEN}✅ 成功${NC}"
    else
        echo -e "${RED}❌ 失败${NC}"
    fi
    
    # 测试PostgreSQL连接
    echo -n "  PostgreSQL连接测试: "
    if docker exec "${CONTAINER_NAME}" pg_isready -h yuyingbao-postgres -p 5432 -U yuyingbao -d yuyingbao &>/dev/null; then
        echo -e "${GREEN}✅ 成功${NC}"
    else
        echo -e "${RED}❌ 失败${NC}"
    fi
    
    echo ""
}

# 修复网络问题
fix_network_issues() {
    echo -e "${BLUE}🔧 尝试修复网络问题...${NC}"
    
    # 确保网络存在
    if ! docker network ls | grep -q "${NETWORK_NAME}"; then
        echo "创建网络: ${NETWORK_NAME}"
        docker network create "${NETWORK_NAME}"
    fi
    
    # 确保PostgreSQL容器在网络中
    if docker ps | grep -q "yuyingbao-postgres"; then
        if ! docker network inspect ${NETWORK_NAME} | grep -q "yuyingbao-postgres"; then
            echo "将PostgreSQL容器加入网络..."
            docker network connect "${NETWORK_NAME}" yuyingbao-postgres
            sleep 3
        fi
    fi
    
    # 确保应用容器在网络中
    if docker ps | grep -q "${CONTAINER_NAME}"; then
        if ! docker network inspect ${NETWORK_NAME} | grep -q "${CONTAINER_NAME}"; then
            echo "将应用容器加入网络..."
            docker network connect "${NETWORK_NAME}" "${CONTAINER_NAME}"
            sleep 3
        fi
    fi
    
    echo -e "${GREEN}✅ 网络修复尝试完成${NC}"
    echo ""
}

# 显示解决建议
show_recommendations() {
    echo -e "${BLUE}💡 问题解决建议:${NC}"
    echo ""
    
    echo -e "${YELLOW}如果问题持续存在，尝试以下步骤:${NC}"
    echo "1. 使用增强hosts映射的部署脚本:"
    echo "   ./deploy-ecs.sh stop-all"
    echo "   ./deploy-ecs.sh deploy  # 现在包含 --add-host 参数"
    echo ""
    echo "2. 手动重新创建应用容器并添加hosts映射:"
    echo "   # 获取PostgreSQL IP地址"
    echo "   POSTGRES_IP=\$(docker inspect yuyingbao-postgres --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
    echo "   echo \"数据库IP: \$POSTGRES_IP\""
    echo "   "
    echo "   # 停止并删除应用容器"
    echo "   docker stop yuyingbao-server && docker rm yuyingbao-server"
    echo "   "
    echo "   # 重新创建带hosts映射的容器"
    echo "   docker run -d --name yuyingbao-server \\"
    echo "     --network yuyingbao-network \\"
    echo "     --add-host=\"postgres:\$POSTGRES_IP\" \\"
    echo "     --env-file .env -p 8080:8080 \\"
    echo "     [YOUR_IMAGE_NAME]"
    echo ""
    echo "3. 检查应用配置:"
    echo "   确保数据库主机名配置为 'postgres'"
    echo "   检查 .env 文件中的 DB_HOST=postgres"
    echo ""
    echo "4. 查看详细日志:"
    echo "   docker logs -f yuyingbao-server"
    echo "   docker logs -f yuyingbao-postgres"
    echo ""
    echo "5. 网络诊断:"
    echo "   ./deploy-ecs.sh diagnose"
    echo "   ./fix-postgres-connection.sh"
    echo ""
    echo "6. 完全重置 (注意：会删除所有数据):"
    echo "   ./deploy-ecs.sh reset-data"
    echo ""
}

# 主执行流程
main() {
    check_containers
    check_network
    test_connectivity
    fix_network_issues
    
    # 再次测试
    echo -e "${BLUE}🔄 修复后重新测试...${NC}"
    test_connectivity
    
    show_recommendations
}

main