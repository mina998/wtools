#!/bin/bash

#分布式远程数据库版
#需要root公钥登陆
#如果运行报错请替换Wondows换行符
# sed -i 's/\r$//' web.sh
#手动备份还原网站脚本(LiteSpeed)

#数据库名
db_name=wordpress2
#数据库账号
db_user=soroy
#数据库密码
db_pass=463888
#数据库服务器地址
db_host=192.168.5.240
#本机地址
localip=192.168.5.52
#网站根目录 后缀不加/
web_dir=/usr/local/lsws/wp.iosss.cc
#备份文件保存目录 后缀不加/
# backup=/root/backup
backup=$(pwd)/backup


#备份网站保存名称
web_save_name=$(date +%Y-%m-%d.%H%M%S).web.tar.gz
# 判断本地备份目录，不存在则创建
if [ ! -d $backup ] ; then
    mkdir -p $backup
fi
# 输出错误信息
err(){
    echo $1
    exit 0
}
# 删除数据库所有表
dropDB(){

ssh -tt root@$db_host << remoteSSH
conn="mysql -D$db_name -u$db_user -p$db_pass -s -e"
drop=\$(\$conn "SELECT concat('DROP TABLE IF EXISTS ', table_name, ';') FROM information_schema.tables WHERE table_schema = '${db_name}'")
\$(\$conn "\${drop}")
exit
remoteSSH

}
# 备份数据
backup(){
    # 切换工作目录
    cd $web_dir
    # 远程导出MySQL数据库
    ssh -tt root@$db_host "mysqldump -u$db_user -p$db_pass $db_name > $db_name.sql"
    # 传回远程文件
    ssh -tt root@$db_host "scp ./$db_name.sql root@$localip:$web_dir"
    # 删除远程备份文件
    ssh -tt root@$db_host "rm $db_name.sql"
    # 测数据库是否导出成功
    ! test -e $db_name.sql && err '备份数据库失败' 
    # 切换目录
    cd $backup
    # 打包本地网站数据,这里用--exclude排除文件及无用的目录
    tar -C $web_dir -zcf $web_save_name ./
    # 测数网站是否备份成功
    ! test -e $web_save_name && err '网站备份失败'
    # 删除
    rm $web_dir/$db_name.sql
}
# 恢复数据
huifu(){
    cd $backup
    # 查看
    ls -lrthgG
    read -p "请输入要还原的文件名:" site
    # 检查文件是否存在
    ! test -e $site && err '文件不存在'
    # 判断临时目录
    if [ -d temp ] ; then
        rm -rf temp
    fi
    # 创建临时目录
    mkdir temp
    # 解压备份文件
    tar -zxf $site -C ./temp
    #
    cd temp
    # 判断数据库文件是否存在
    ! test -e $db_name.sql && err '找不到SQL文件'
    # 远程删除数据库中的所有表
    dropDB
    # 上传文件到远程
    scp ./$db_name.sql root@$db_host:/root/
    # 远程导入备份数据
    ssh -tt root@$db_host "mysql -u$db_user -p$db_pass $db_name < /root/$db_name.sql"
    # 删除远程文件
    ssh -tt root@$db_host "rm /root/$db_name.sql"
    # 删除本地SQL
    rm $db_name.sql
    # 删除网站文件
    rm -rf $web_dir/*
    # 还原备份文件
    mv ./* $web_dir/
    # 删除临时目录
    cd .. && rm -rf temp
    # 切换工作目录
    cd $web_dir
    # 修改所有者
    chown -R nobody:nogroup wordpress/
    # 修改目录权限
    find wordpress/ -type d -exec chmod 750 {} \;
    # 修改文件权限
    find wordpress/ -type f -exec chmod 640 {} \;
}

menu(){
    echo "备份(1)  还原(2)"
    read -p "请选择:" num
    if [ $num -eq 1 ]; then
        backup
    else
        huifu
    fi
}
menu
