#!/bin/bash

bbrNetfilter(){

	apt update
	if [ ! `command -v vim` ] ; then
		apt purge vim-common -y
		apt install vim -y
	fi
	#开启BBR
	if ! lsmod | grep bbr > /dev/null ; then
		bash -c 'echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf'
		bash -c 'echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf'
		sysctl -p
	fi
	#删除组件
	apt-get purge netfilter-persistent -y
	#清空规则
	iptables -F
	#创建保存新规则
	cat > /etc/iptables.rules <<iptablesRules
# Generated by iptables-save v1.8.4
*filter
:INPUT DROP
:FORWARD ACCEPT
:OUTPUT ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m multiport --dports 22,80,443 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 7080 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 8088 -j ACCEPT
COMMIT
# Completed
iptablesRules

	#创建重启自动加载规则
	cat > /etc/rc.local <<rcL
#!/bin/bash
/sbin/iptables-restore < /etc/iptables.rules
exit 0
rcL
	chmod +x /etc/rc.local
	#启动服务
	systemctl start rc-local
	echo "本次操作需要重启"
	reboot
}


installOls(){

	if [ -e /usr/local/lsws/bin/lswsctrl ] ; then
		echo "OpenLiteSpeed 已存在"
		exit 0
	fi
	#添加存储库
	wget -O - http://rpms.litespeedtech.com/debian/enable_lst_debian_repo.sh | bash
	#
	apt install openlitespeed -y
	#
	if [ -e /usr/local/lsws/lsphp74/bin/lsphp ] ; then
		#wordpress 必须组件 
		apt install lsphp74-imagick lsphp74-curl lsphp74-intl -y
	fi
	
	cd ~
	wget https://github.com/mina998/wtools/raw/lsws/scripts/vm2.sh
	chmod +x vm2.sh

	cat /usr/local/lsws/adminpasswd
	cp /usr/local/lsws/adminpasswd ./webAdmin
}


#申请SSL证书
certSSL(){
	# 
	if [ ! -x /usr/bin/socat ] ; then 
		apt install socat -y
	fi
	# 安装curl
	if [ ! `command -v curl` ] ; then 
		apt install curl -y
	fi
	# 判断是否安装定时任务工具
	if [ ! `command -v crontab` ] ; then
	    apt-get install cron -y
	    service cron restart
	fi
	# 安装PING命令
	if [ ! `command -v ping` ] ; then
	    apt install iputils-ping -y
	fi
	# 下载安装证书签发程序
	if [ ! -f "/root/.acme.sh/acme.sh" ] ; then 
		curl https://get.acme.sh | sh -s email=my@example.com
	fi
	# 获取网站根目录
	read -p "请输入网站文档根目录(eg:/usr/local/lsws/wordpress/html):" siteDocRoot
	if [ ! -d $siteDocRoot ] ; then
		echo '目录不存在!'
		exit 0
	fi
	# 获取证书保存目录
	read -p "请输入证书保存目录(eg:/usr/local/lsws/wordpress/ssl):" sslSaveRoot
	if [ ! -d $sslSaveRoot ] ; then
		mkdir -p $sslSaveRoot
	fi
	# 获取域名
	read -p "请输入域名(eg:www.demo.com):" domain
	if [ -z $domain ] ; then
		echo '域名不能为空!'
		exit 0
	fi
	# 获取本机IP
	local2_ip=$(curl -s https://api.ip.sb/ip -A Mozilla)
	# 获取域名解析IP
	domain_ip=$(ping "${domain}" -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
	# 判断是否解析成功
	if [ $localh_ip=$domain_ip ] ; then
		echo "域名dns解析IP: $domain_ip"
	else
		echo "域名解析失败."
		exit 2
	fi

	# 开使申请证书
	~/.acme.sh/acme.sh --issue -d $domain --webroot $siteDocRoot
	#~/.acme.sh/acme.sh --issue -d $domain -d www.$domain --webroot $siteDocRoot
	# 证书签发是否成功
	if [ ! -f "/root/.acme.sh/$domain/fullchain.cer" ] ; then 
		echo "证书签发失败."
		exit 0
	fi
	# copy/安装 证书
	~/.acme.sh/acme.sh --install-cert -d $domain --cert-file $sslSaveRoot/cert.pem --key-file $sslSaveRoot/key.pem --fullchain-file $sslSaveRoot/fullchain.pem --reloadcmd "service lsws force-reload"
	# 
	echo "证书文件: $sslSaveRoot/cert.pem"
	echo "私钥文件: $sslSaveRoot/key.pem"
	echo "证书全链: $sslSaveRoot/fullchain.pem"
}

# 安装MariaDB数据库
installMariaDB(){

	if [ -e /usr/bin/mariadb ] ; then
		echo "MariaDB 已存在"
		exit 0
	fi
	# 安装依赖
	apt-get install software-properties-common dirmngr -y
	# 添加密钥
	apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
	# 选择系统
	echo "(1)ubuntu 18.04 (2)ubuntu 20.04 (3)debian 9 (4)debian 10 (5)debian 11"
	read -p "请选择:" num
	if [ $num -eq 1 ]; then
		# ubuntu 18.04
		add-apt-repository 'deb [arch=amd64,arm64,ppc64el] https://mirrors.gigenet.com/mariadb/repo/10.5/ubuntu bionic main'
	elif [ $num -eq 2 ] ; then
		# ubuntu 20.04
		add-apt-repository 'deb [arch=amd64,arm64,ppc64el,s390x] https://mirrors.gigenet.com/mariadb/repo/10.5/ubuntu focal main'
	elif [ $num -eq 3 ]; then
		# debian 9
		add-apt-repository 'deb [arch=amd64,i386,ppc64el,arm64] https://mirrors.gigenet.com/mariadb/repo/10.5/debian stretch main'
	elif [ $num -eq 4 ]; then
		# debian 10
		add-apt-repository 'deb [arch=amd64,arm64,ppc64el] https://mirrors.gigenet.com/mariadb/repo/10.5/debian buster main'
	elif [ $num -eq 5 ]; then
		# debian 11
		add-apt-repository 'deb [arch=amd64,i386,arm64,ppc64el] https://mirrors.gigenet.com/mariadb/repo/10.5/debian bullseye main'
	else
		echo "无效输入"
		exit 0
	fi

	apt update
	apt install mariadb-server -y
	# 重启防止出错
	systemctl restart mariadb

	echo "向导说明"
	echo "Enter current password for root (enter for none):   #提示你输入root密码, 没有密码, 直接回车"
	echo "Switch to unix_socket authentication [Y/n] n        #是否切换到unix套接字身份验证"
	echo "Change the root password? [Y/n] Y                   #是否为 root 用户设置密码"
	echo "Remove anonymous users? [Y/n] Y                     #删除匿名用户"
	echo "Disallow root login remotely? [Y/n] Y               #禁止root用户远程登陆"
	echo "Remove test database and access to it? [Y/n] Y      #删除测试数据库"
	echo "Reload privilege tables now? [Y/n] Y                #重新加载权限表"

	# 运行配置向导
	mysql_secure_installation

}


# 下载最新版WordPress程序
wordpressGet(){
	cd ~
	if [ -e latest.tar.gz ] ; then
		rm latest.tar.gz
	fi
	wget https://wordpress.org/latest.tar.gz
	ls ~
}


menu(){
	echo "(1)系统设置(防火墙,编辑器,BBR)"
	echo "(2)安装OpenLiteSpeed"
	echo "(3)安装MariaDB"
	echo "(4)申请SSL证书"
	echo "(5)下载最新版WordPress程序"
	read -p "请选择:" num
	if [ $num -eq 1 ]; then
		bbrNetfilter
	elif [ $num -eq 2 ] ; then
		installOls
	elif [ $num -eq 3 ] ; then
		installMariaDB
	elif [ $num -eq 4 ] ; then
		certSSL
	elif [ $num -eq 5 ] ; then
		wordpressGet
	else
		echo "输入无效"
		exit 0
	fi
}
menu
