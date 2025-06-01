#!/bin/bash

# SOCKS5 环境自动安装脚本
# 使用方法: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | bash

set -e

echo "开始安装 SOCKS5 环境..."

# 创建临时目录
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# GitHub仓库信息
GITHUB_USER="Blazerain"
REPO_NAME="yourrepo"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH"

echo "正在下载配置文件..."

# 创建必要目录
sudo mkdir -p /etc/yum.repos.d.backup
sudo mkdir -p /etc/pki/rpm-gpg

# 备份现有repo配置
echo "备份现有YUM配置..."
sudo cp -r /etc/yum.repos.d/* /etc/yum.repos.d.backup/ 2>/dev/null || true

# 清理现有repo
sudo rm -rf /etc/yum.repos.d/*

# 下载并安装repo文件
echo "安装YUM源配置..."
curl -sSL $BASE_URL/repos/epel.repo -o epel.repo
curl -sSL $BASE_URL/repos/CentOS7-ctyun.repo -o CentOS7-ctyun.repo  
curl -sSL $BASE_URL/repos/epel-testing.repo -o epel-testing.repo

sudo mv epel.repo /etc/yum.repos.d/
sudo mv CentOS7-ctyun.repo /etc/yum.repos.d/
sudo mv epel-testing.repo /etc/yum.repos.d/

# 下载并安装GPG密钥
echo "安装GPG密钥..."
curl -sSL $BASE_URL/keys/RPM-GPG-KEY-EPEL-7 -o RPM-GPG-KEY-EPEL-7
sudo mv RPM-GPG-KEY-EPEL-7 /etc/pki/rpm-gpg/

# 创建配置文件
echo "创建配置文件..."
echo "2" > ipdajian1.txt
echo "c6eae20845cf8b6e02b8657f74c531b1" > ipdajian2.txt

# 安装必要软件
echo "安装依赖软件..."
sudo yum clean all
sudo yum makecache
sudo yum -y install jq

# 下载并执行主安装脚本
echo "下载主安装脚本..."
curl -sSL $BASE_URL/scripts/install2.sh -o install2.sh
chmod +x install2.sh

echo "执行主安装脚本..."
./install2.sh

# 清理临时文件
cd /
rm -rf $TEMP_DIR

echo "安装完成！"

