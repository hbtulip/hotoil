#!/usr/bin/env bash
#自动部署代理脚本，支持war/jar/docker方式
#2019.2 disp
#

pgm=`basename $0`
USAGE() {
	echo "USAGE: $pgm <cluster_name> <prject_name>"
	echo "       cluster_name, 	操作集群文件类别，A：A集群，B：B集群"
	echo "       prject_name, 	重启本机指定服务（暂不支持ALL）"	
	echo
}

#检查操作用户
curuser=`whoami`
if [ "$curuser" != "bluestar" ];then
    echo "<<< 不支持当前用户（$curuser）的操作"
    exit 250
fi

#检查输入参数
if [ "$#" -ne 2 ];then
    echo "<<< 参数个数有误"
    USAGE ; exit 250
fi

#设置相关路径等
cluster_name=$1
project_name=$2
clustera_project_warpath='/usr/local/mnt/soft/clustera'
clusterb_project_warpath='/usr/local/mnt/soft/clusterb'
tomcat_path="/usr/local/tomcat"

#选择集群类别
project_warpath=''
if [ $cluster_name == 'A' ];then	
	project_warpath=$clustera_project_warpath;

elif [ $cluster_name == 'B' ];then	
	project_warpath=$clusterb_project_warpath;

else
    echo "<<< 集群文件类别输入错误"
    exit 250
fi

#基于tomcat和war包
function startup4war() 
{
	#检查当前机器是否安装对应tomcat
	echo "<<< 当前服务名称：$project_name"
	if [ ! -d "${tomcat_path}/${project_name}" ]; then
		 echo "<<< 指定服务的tomcat目录不存在" 
		 exit 250
	fi

	cd ${tomcat_path}/${project_name}
	./bin/shutdown.sh -force
	rm logs/catalina.out
	rm webapps/$project_name.war
	cp $project_warpath/$project_name.war webapps/
	./bin/startup.sh

    return 0
}

#基于可执行的jar包
function startup4jar() 
{
	PID=$(ps -ef | grep $project_name | grep -v grep | awk '{ print $2 }')
 
	#判断PID是否为空，停止进程
	if [ -z "$PID" ]; then
	    : # echo App is already stopped
	else
	    kill -9 $PID
	fi
	
	#启动进程
	appjar = $project_warpath/$project_name.jar
	nohup java -jar $appjar > app.log 2>&1 &
	
	return 0
}

#基于docker
function startup4docker() 
{
	container_id = $(docker ps -a | grep $project_name:v1 | awk '{print $1}')

	#判断container_id是否为空，删除容器
	if [ "$container_id" ]; then
		docker stop $container_id		
		docker rm -f  $container_id
	fi

	#拉取最新镜像
	docker pull 39.100.xx.xx:5800/oilunion/$project_name:v1
	#删除名称为none的中间镜像
	docker rmi  $(docker images|grep none| awk '{print $3}')
	#启动容器
	#docker run --cpus=0.6 -m 4G  -dt -v /Users/disp/xxx:/root/xxx -p $project_port:8080 oilunion/$project_name:v1
	docker run  -dt oilunion/$project_name:v1
	
    return 0
}

#重启服务
startup4war
if [ $? != 0 ]; then
	echo "<<< 服务启动失败"
	exit 1  #参数错误，退出状态1
fi

echo "<<< 服务启动完成"

