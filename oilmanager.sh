#!/usr/bin/env bash
#打包部署指定微服务，支持将服务部署到集群中指定节点，支持动态扩展服务副本个数
#2019.2 disp
#

#定义微服务列表，10个
array_project[0]=oil-marketing-web
array_project[1]=oil-wechat-web
array_project[2]=oil-platform-web
array_project[3]=oil-service-001
array_project[4]=oil-service-002
array_project[5]=oil-service-003
array_project[6]=oil-service-004
array_project[7]=oil-service-005
array_project[8]=oil-service-006
array_project[9]=oil-service-007

#定义集群节点列表，5个
ecs1_info=(39.100.88.1 20001 bluestar password)
#各个节点挂载nfs，或者访问docker私有仓库
ecs1_nfspath='/usr/local/mnt/soft/'
ecs2_info=(39.100.88.2 20002 bluestar password)
ecs3_info=(39.100.88.3 20003 bluestar password)
ecs4_info=(39.100.88.4 20004 bluestar password)
ecs5_info=(39.100.88.5 20005 bluestar password)


#配置服务集群每个节点ecs上的部署情况,填写定义的服务编号 0～9
#service004,005,006部署3个副本，其他部署2个副本
ecs1_array_prj=(0 1 2 3 4)
ecs2_array_prj=(0 1 2 3 4)
ecs3_array_prj=(5 6 7 8 9)
ecs4_array_prj=(5 6 7 8 9)
ecs5_array_prj=(4 5 6)

pgm=`basename $0`
USAGE() {
	echo "USAGE: $pgm <project_name>"
	echo "       project_name, 	需要重新部署的指定服务名称，若为all，则重新部署当前集群的所有服务"	
	echo

}

#检查操作用户
curuser=`whoami`
if [ "$curuser" != "bluestar" ];then
    echo "不支持当前用户（$curuser）的操作"
    exit 250
fi

#检查输入参数
if [ "$#" -ne 1 ];then
    echo "参数个数有误"
    USAGE ; exit 250
fi
#while getopts tvph OPTIONS ; do
#     case $OPTIONS in
#     h) USAGE; exit 2
#         ;;
#     esac
#done

#设置相关路径等
project_name=$1
project_homepath='/home/bluestar/oilunion'
project_branch='group-master'
outwar_path='/home/bluestar/release'

#拉取gitlab上项目源代码
echo "拉取代码分支 ：$project_branch "
cd $project_homepath
#从代码库gitlab中克隆项目代码
#git clone -b group-master https://bluestar:12345678@github.bluestar.com.cn/Group_oilunion/oilunion.git
#git checkout -b group-master origin/group-master
#强制用远程版本覆盖本地
#git fetch --all
#git reset --hard origin/group-master

git checkout $project_branch
git pull origin $project_branch
git branch -vv
echo "代码更新完成"


#maven编译打包, 多模块工程
echo "当前服务名称：$project_name"
if [ $project_name == 'all' ] || [ $project_name == 'ALL' ];then	
	
	echo "支持的服务个数：${#array_project[@]}"
	mvn clean package -am -Dmaven.test.skip=true -Pprod

	for var in ${array_project[@]};
	do
		if [ "$var" == "oil-icbc-server" ] || [ "$var" == "oil-yepay-server" ]; then
			#如果为支付类模块
			cp $project_homepath/oilunion-pay/$var/target/$var.war $outwar_path/
		else
			cp $project_homepath/$var/target/$var.war $outwar_path/
		fi
	done

elif [ "$var" == "oil-icbc-server" ] || [ "$var" == "oil-yepay-server" ]; then
	#如果为支付类模块
	mvn clean package -pl oilunion-pay/$project_name -am -Dmaven.test.skip=true -Pprod			
	cp $project_homepath/oilunion-pay/$project_name/target/$project_name.war $outwar_path/
else
	mvn clean package -pl $project_name -am -Dmaven.test.skip=true -Pprod
	cp $project_homepath/$project_name/target/$project_name.war $outwar_path/
fi

echo "代码编译完成"


#scp（war/jar）到指定nfs共享目录
if [ $project_name == 'all' ] || [ $project_name == 'ALL' ];then

	#sshpass -p password scp -P 22 -r $outwar_path bluestar@47.92.xx.xx:/usr/local/mnt/soft/
	sshpass -p ${ecs1_info[3]} scp -P ${ecs1_info[1]} -r $outwar_path ${ecs1_info[2]}@${ecs1_info[0]}:${ecs1_nfspath}

else
	#截取右边字符，用于组装完整路径
	outbase=${outwar_path##*/}
	echo "截取结果：$outbase"
	#sshpass -p password scp -P 22 $outwar_path/$project_name.war bluestar@47.92.xx.xx:/usr/local/mnt/soft/$outbase/
	sshpass -p ${ecs1_info[3]} scp -P ${ecs1_info[1]} $outwar_path/$project_name.war ${ecs1_info[2]}@${ecs1_info[0]}:${ecs1_nfspath}${outbase}/

fi
echo "输出共享目录完成"

# 或者基于Docker打包镜像，并推送到私有仓库Harbor或registry:2
#echo "开始构建镜像，并上传到私有仓库"
#tag=v1.$(($RANDOM%1000+1))
#docker build  --force-rm -f ./mydockerfile -t oilunion/$project_name:v1 .
#docker login 39.100.xx.xx:5800 -u admin -p Harbor12345
#docker tag oilunion/$project_name:v1 39.100.xx.xx:5800/oilunion/$project_name:v1
#docker push 39.100.xx.xx:5800/oilunion/$project_name:v1
#[ $? != 0 ] && echoRed "请注意，在执行push上传时出错，故而退出！" && exit 1
#docker rmi 39.100.xx.xx:5800/oilunion/$project_name:v1
#docker logout 39.100.xx.xx:5800
#echo "打包镜像并推送完成"


#执行远程脚本，不同服务部署在不同的机器，且启动个数不同
if [ $project_name == 'all' ] || [ $project_name == 'ALL' ];then
	echo "开始重新启动集群..."
	echo "暂不支持此功能"
	
else
	#待优化
	prjnum=${#array_project[@]}
	agentcom="/home/bluestar/oilagent.sh B $project_name"

	for var in ${ecs1_array_prj[@]};
	do
		if [ "$var" -ge "0" ] && [ "$var" -lt "$prjnum" ] && [ ${array_project[$var]} == $project_name ]; then
			echo "开始重启ecs1指定服务"
			sshpass -p ${ecs1_info[3]} ssh -p ${ecs1_info[1]} ${ecs1_info[2]}@${ecs1_info[0]} $agentcom
			break
		fi
	done

	for var in ${ecs2_array_prj[@]};
	do
		if [ "$var" -ge "0" ] && [ "$var" -lt "$prjnum" ] && [ ${array_project[$var]} == $project_name ]; then
			echo "开始重启ecs2指定服务"
			sleep 5s
			sshpass -p ${ecs2_info[3]} ssh -p ${ecs2_info[1]} ${ecs2_info[2]}@${ecs2_info[0]} $agentcom
			break
		fi
	done

	for var in ${ecs3_array_prj[@]};
	do
		if [ "$var" -ge "0" ] && [ "$var" -lt "$prjnum" ] && [ ${array_project[$var]} == $project_name ]; then
			echo "开始重启ecs3指定服务"
			sleep 5s
			sshpass -p ${ecs3_info[3]} ssh -p ${ecs3_info[1]} ${ecs3_info[2]}@${ecs3_info[0]} $agentcom
			break
		fi
	done	

	for var in ${ecs4_array_prj[@]};
	do
		if [ "$var" -ge "0" ] && [ "$var" -lt "$prjnum" ] && [ ${array_project[$var]} == $project_name ]; then
			echo "开始重启ecs4指定服务"
			sleep 5s
			sshpass -p ${ecs4_info[3]} ssh -p ${ecs4_info[1]} ${ecs4_info[2]}@${ecs4_info[0]} $agentcom
			break
		fi
	done	

	for var in ${ecs5_array_prj[@]};
	do
		if [ "$var" -ge "0" ] && [ "$var" -lt "$prjnum" ] && [ ${array_project[$var]} == $project_name ]; then
			echo "开始重启ecs5指定服务"
			sleep 5s
			sshpass -p ${ecs5_info[3]} ssh -p ${ecs5_info[1]} ${ecs5_info[2]}@${ecs5_info[0]} $agentcom
			break
		fi
	done	

	echo "指定服务重启完成"



fi

echo "服务部署完成"



