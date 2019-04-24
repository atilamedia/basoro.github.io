#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

Backup_Site()
{
	startTime=`date +%s`
	myDate=`date +"%Y%m%d_%H%M%S"`
	zipName=${1}_${myDate}.zip
	backupDir=${backup_path}/site
	fileName=$backupDir/$zipName
	tmp=`$Sql_Exec -e "SELECT id,path FROM bt_sites WHERE name='$1'"`;
	pid=`echo $tmp|awk '{print $3}'`
	sitePath=`echo $tmp|awk '{print $4}'`
	
	if [ "$pid" == '' ];then
		endDate=`date +"%Y-%m-%d %H:%M:%S"`
		log="Website [$1] does not exist!"
		echo "★[$endDate] $log"
		echo '----------------------------------------------------------------------------'
		exit
	fi
	
	if [ ! -d $backupDir ];then
		mkdir -p $backupDir
	fi
	
	oldIFS=$IFS
	IFS=/
	nameArr=($sitePath)
	pathName=${nameArr[@]: -1};
	IFS=$oldIFS
	
	cd $sitePath
	cd ..
	zip -r $fileName $pathName > /dev/null
	
	if [ ! -f $fileName ];then
		endDate=`date +"%Y-%m-%d %H:%M:%S"`
		log="Website [$1] backup failed!"
		echo "★[$endDate] $log"
		echo '----------------------------------------------------------------------------'
		exit
	fi
	
	endDate=`date +"%Y-%m-%d %H:%M:%S"`
	endTime=`date +%s`
	((outTime=($endTime-$startTime)))
	
	log="Website [$1] backup success, time [$outTime] seconds"
	$Sql_Exec -e "INSERT INTO  bt_backup(type,name,pid,filename,addtime) VALUES(0,'$zipName',$pid,'$fileName','$endDate')"
	$Sql_Exec -e "INSERT INTO  bt_logs(type,log,addtime) VALUES('Scheduled Tasks','$log','$endDate')"
	echo "★[$endDate] $log"
	echo "|---Keep the latest [$2] backups"
	echo "|---File name : $fileName"
	
	tmp=`$Sql_Exec -e "SELECT COUNT(*) FROM bt_backup WHERE type=0 AND pid=$pid"`;
	count=`echo $tmp|awk '{print $2}'`
	((sum=($count-$2)))
	if [ $sum -gt 0 ];then
		str=`$Sql_Exec -e "SELECT filename FROM bt_backup WHERE type=0 AND pid=$pid ORDER BY id ASC LIMIT $sum"`
		str=`echo $str|sed "s#filename##"|sed "s# ##"`
		oldIFS=$IFS
		IFS=' '
		arr=($str)
		for s in ${arr[@]}
		do
			if [ -f $s ];then
				rm -f $s
			fi
			echo "|---The expired backup file has been cleaned up ：$s"
			$Sql_Exec -e "DELETE FROM bt_backup WHERE filename='$s'" > /dev/null
		done
		IFS=$oldIFS
	fi
	
	echo '----------------------------------------------------------------------------'
}

Backup_Database()
{
	startTime=`date +%s`
	mysqlRoot=`echo $select |grep mysql_root|awk '{print $3}'`
	myDate=`date +"%Y%m%d_%H%M%S"`
	sqlName=${1}_${myDate}.sql
	zipName=${1}_${myDate}.zip
	backupDir=${backup_path}/database
	tmp=`$Sql_Exec -e "SELECT id FROM bt_databases WHERE name='$1'"`;
	pid=`echo $tmp|awk '{print $2}'`
	
	if [ "$pid" == '' ];then
		endDate=`date +"%Y-%m-%d %H:%M:%S"`
		log="Database [$1] does not exist!"
		echo "★[$endDate] $log"
		echo '----------------------------------------------------------------------------'
		exit
	fi
	
	if [ ! -d $backupDir ];then
		mkdir -p $backupDir
	fi
	
	
	#sed -i "s###"
	isWrite=`cat /etc/my.cnf|grep 'user=root'`
	if [ "${isWrite}" == '' ];then
		echo -e "\n[mysqldump]\nuser=root\npassword=$mysqlRoot" >> /etc/my.cnf
	else
		sed -i "s#password=.*#password=$mysqlRoot#" /etc/my.cnf
	fi
	
	cd $backupDir
	/www/server/mysql/bin/mysqldump -uroot -p$mysqlRoot -R $1 > $sqlName
	
	sed -i "/\[mysqldump\]/d" /etc/my.cnf
	sed -i "/user=root/d" /etc/my.cnf
	sed -i "/password=.*/d" /etc/my.cnf
	sed -i "s/quick/\[mysqldump\]\nquick/" /etc/my.cnf
	
	
	if [ ! -f $sqlName ];then
		endDate=`date +"%Y-%m-%d %H:%M:%S"`
		log="Database [$1] backup failed!"
		echo "★[$endDate] $log"
		echo '----------------------------------------------------------------------------'
		exit
	fi
	
	zip -r $zipName $sqlName > /dev/null
	rm -f $sqlName
	
	endDate=`date +"%Y-%m-%d %H:%M:%S"`
	endTime=`date +%s`
	((outTime=($endTime-$startTime)))
	fileName=$backupDir/$zipName
	log="Database [$1] backup succeeded, using [$outTime] seconds"
	$Sql_Exec -e "INSERT INTO  bt_backup(type,name,pid,filename,addtime) VALUES(1,'$zipName',$pid,'$fileName','$endDate')" > /dev/null
	$Sql_Exec -e "INSERT INTO  bt_logs(type,log,addtime) VALUES('计划任务','$log','$endDate')" > /dev/null
	echo "★[$endDate] $log"
	echo "|---Keep the latest [$2] backups"
	echo "|---File name : $fileName"
	
	tmp=`$Sql_Exec -e "SELECT COUNT(*) FROM bt_backup WHERE type=1 AND pid=$pid"`;
	count=`echo $tmp|awk '{print $2}'`
	((sum=($count-$2)))
	if [ $sum -gt 0 ];then
		str=`$Sql_Exec -e "SELECT filename FROM bt_backup WHERE type=1 AND pid=$pid ORDER BY id ASC LIMIT $sum"`
		str=`echo $str|sed "s#filename##"|sed "s# ##"`
		oldIFS=$IFS
		IFS=' '
		arr=($str)
		for s in ${arr[@]}
		do
			if [ -f $s ];then
				rm -f $s
			fi
			echo "|---The expired backup file has been cleaned up ：$s"
			$Sql_Exec -e "DELETE FROM bt_backup WHERE filename='$s'" > /dev/null
		done
		IFS=$oldIFS
	fi
	echo '----------------------------------------------------------------------------'
}


action=$1
name=$2
num=$3
dbPwd=`cat /www/server/panel/conf/sql.config.php |grep 'DB_PWD'|awk '{print $3}'|sed "s#'##g"|sed "s#,##g"`
dbName='bt_default'
Sql_Exec="/www/server/mysql/bin/mysql -u$dbName -p$dbPwd --default-character-set=utf8 -D $dbName"
select=`$Sql_Exec -e "SELECT mysql_root,backup_path FROM bt_config WHERE id=1"`
backup_path=`echo $select |grep backup_path|awk '{print $4}'`

case "${action}" in
	'site')
		Backup_Site $name $num
		;;
	'database')
		Backup_Database $name $num
		;;
esac

