#swap设置
System_swap_settings(){
	swapSize=$(awk '/SwapTotal/{print $2}' /proc/meminfo)
	if [ "$swapSize" == 0 ];then
		while true; do
			echo -e "1) 512M\n2) 1G\n3) 2G\n4) 4G\n5) 8G\n"
			read -p "please select your swap size: " swapSelect			
			case $swapSelect in
				1) swapSize=524288;break;;
				2) swapSize=1048576;break;;
				3) swapSize=2097152;break;;
				4) swapSize=4194304;break;;
				*) echo "input error,please reinput."
			esac
		done

		swapLocationDefault="/swapfile"
		read -p "please input the swap file location(default:${swapLocationDefault},leave blank for default.): " swapLocation
		swapLocation=${swapLocation:=$swapLocationDefault}
		swapLocation=`filter_location ${swapLocation}`

		echo "start setting system swap..."
		mkdir -p `dirname $swapLocation`
		dd if=/dev/zero of=${swapLocation} bs=1024 count=${swapSize}
		mkswap ${swapLocation}
		swapon ${swapLocation}
		! grep "${swapLocation} swap swap defaults 0 0" /etc/fstab && echo "${swapLocation} swap swap defaults 0 0" >> /etc/fstab

		echo "swap settings complete."
		free -m
		exit

	else
		echo "Your system swap had been enabled,exit."
		exit
	fi	
}

#自定义mysql配置文件生成
make_mysql_my_cnf(){
	local memory=$1
	local storage=$2
	local mysqlDataLocation=$3
	local binlog=$4
	local replica=$5
	local my_cnf_location=$6

	case $memory in
		256M)innodb_log_file_size=32M;innodb_buffer_pool_size=64M;key_buffer_size=64M;open_files_limit=512;table_definition_cache=50;table_open_cache=200;max_connections=50;;
		512M)innodb_log_file_size=32M;innodb_buffer_pool_size=128M;key_buffer_size=128M;open_files_limit=512;table_definition_cache=50;table_open_cache=200;max_connections=100;;
		1G)innodb_log_file_size=64M;innodb_buffer_pool_size=256M;key_buffer_size=256M;open_files_limit=1024;table_definition_cache=100;table_open_cache=400;max_connections=200;;
		2G)innodb_log_file_size=64M;innodb_buffer_pool_size=1G;key_buffer_size=512M;open_files_limit=1024;table_definition_cache=100;table_open_cache=400;max_connections=300;;
		4G)innodb_log_file_size=128M;innodb_buffer_pool_size=2G;key_buffer_size=1G;open_files_limit=2048;table_definition_cache=200;table_open_cache=800;max_connections=400;;
		8G)innodb_log_file_size=256M;innodb_buffer_pool_size=4G;key_buffer_size=2G;open_files_limit=4096;table_definition_cache=400;table_open_cache=1600;max_connections=400;;
		16G)innodb_log_file_size=512M;innodb_buffer_pool_size=10G;key_buffer_size=4G;open_files_limit=8192;table_definition_cache=600;table_open_cache=2000;max_connections=500;;
		32G)innodb_log_file_size=512M;innodb_buffer_pool_size=20G;key_buffer_size=10G;open_files_limit=65535;table_definition_cache=1024;table_open_cache=2048;max_connections=1000;;
		*) echo "input error,please input a number";;						
	esac

	#二进制日志
	if $binlog;then
		binlog="# BINARY LOGGING #\nlog-bin                        = ${mysqlDataLocation}/mysql-bin\nexpire-logs-days               = 14\nsync-binlog                    = 1"
		binlog=$(echo -e $binlog)
	else
		binlog=""
	fi	

	#复制节点
	if $replica;then
		replica="# REPLICATION #\nrelay-log                      = ${mysqlDataLocation}/relay-bin\nslave-net-timeout              = 60"
		replica=$(echo -e $replica)
	else
		replica=""
	fi	

	#设置myisam及innodb内存
	if [ "$storage" == "InnoDB" ];then
		key_buffer_size=32M
	elif [ "$storage" == "MyISAM" ]; then
		innodb_log_file_size=32M
		innodb_buffer_pool_size=8M
	fi

	echo "generate my.cnf..."
	sleep 1
	generate_time=$(date +%Y-%m-%d' '%H:%M:%S)
	cat >${my_cnf_location} <<EOF
# Generated by EZHTTP at $generate_time

[mysql]

# CLIENT #
port                           = 3306
socket                         = /tmp/mysql.sock

[mysqld]

# GENERAL #
user                           = mysql
default-storage-engine         = ${storage}
socket                         = /tmp/mysql.sock
pid-file                       = ${mysqlDataLocation}/mysql.pid

# MyISAM #
key-buffer-size                = ${key_buffer_size}
myisam-recover                 = FORCE,BACKUP

# INNODB #
innodb-flush-method            = O_DIRECT
innodb-log-files-in-group      = 2
innodb-log-file-size           = ${innodb_log_file_size}
innodb-flush-log-at-trx-commit = 1
innodb-file-per-table          = 1
innodb-buffer-pool-size        = ${innodb_buffer_pool_size}

# CACHES AND LIMITS #
tmp-table-size                 = 32M
max-heap-table-size            = 32M
query-cache-type               = 0
query-cache-size               = 0
max-connections                = ${max_connections}
thread-cache-size              = 50
open-files-limit               = ${open_files_limit}
table-definition-cache         = ${table_definition_cache}
table-open-cache               = ${table_open_cache}


# SAFETY #
max-allowed-packet             = 16M
max-connect-errors             = 1000000

# DATA STORAGE #
datadir                        = ${mysqlDataLocation}

# LOGGING #
log-error                      = ${mysqlDataLocation}/mysql-error.log
log-queries-not-using-indexes  = 1
slow-query-log                 = 1
slow-query-log-file            = ${mysqlDataLocation}/mysql-slow.log

${binlog}

${replica}

EOF

	echo "generate done.my.cnf at ${my_cnf_location}"

}

#mysql配置文件生成工具
Generate_mysql_my_cnf(){
	#输入内存
	while true; do
		echo -e "1) 256M\n2) 512M\n3) 1G\n4) 2G\n5) 4G\n6) 8G\n7) 16G\n8) 32G\n"
		read -p "please input mysql server memory(ie.1 2 3): " mysqlMemory
		case $mysqlMemory in
			1) mysqlMemory=256M;break;;
			2) mysqlMemory=512M;break;;
			3) mysqlMemory=1G;break;;
			4) mysqlMemory=2G;break;;
			5) mysqlMemory=4G;break;;
			6) mysqlMemory=8G;break;;
			7) mysqlMemory=16G;break;;
			8) mysqlMemory=32G;break;;
			*) echo "input error,please input a number";;
		esac

	done

	#输入存储引擎
	while true; do
		echo -e "1) InnoDB(recommended)\n2) MyISAM\n"
		read -p "please input the default storage(ie.1 2): " storage
		case $storage in
			1) storage="InnoDB";break;;
			2) storage="MyISAM";break;;
			*) echo "input error,please input ie.1 2";;
		esac
	done

	#输入mysql data位置
	read -p "please input the mysql data location(default:/usr/local/mysql/data): " mysqlDataLocation
	mysqlDataLocation=${mysqlDataLocation:=/usr/local/mysql/data}
	mysqlDataLocation=`filter_location $mysqlDataLocation`

	#是否开启二进制日志
	yes_or_no "enable binlog [Y/n]: " "binlog=true;echo 'you select y,enable binlog'" "binlog=false;echo 'you select n,disable binlog.'"

	#是否为复制节点
	yes_or_no "mysql server will be a replica [N/y]: " "replica=true;echo 'you select y,setup replica config.'" "replica=false;echo 'you select n.'"

	make_mysql_my_cnf "$mysqlMemory" "$storage" "$mysqlDataLocation" "$binlog" "$replica" "$cur_dir/my.cnf"
	echo "you should copy this file to the right location."
	exit
}

#生成spec文件
make_rpm(){
	local name=$1
	local version=$2
	local location=$3
	local filesPackage=($4)
	local postCmd=$5
	local summary=$6
	local description=$7
	local preun=$8

	local release=`uname -r | awk -F'.' '{print $4}'`
	local arch=`uname -r | awk -F'.' '{print $5}'`

	local rpmExportPath=$HOME/rpmbuild/BUILDROOT/${name}-${version}-${release}.${arch}/
	mkdir -p $HOME/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
	mkdir -p $rpmExportPath

	#复制文件
	echo "copying files to rpm location..."
	local filesList=''
	for file in ${filesPackage[@]};do
		cp --parents -a $file $rpmExportPath
		filesList="$file\n$filesList"
	done

	filesList=$(echo -e $filesList)

	cd $HOME/rpmbuild/SPECS

	cat >${name}.spec << EOF
Summary: ${summary}
License: 2-clause BSD-like license
Name: ${name}
Version: $version
Release: $release
Distribution: Linux
Packager: zhumaohai <admin@www.centos.bz>
%description
${description}
%post
${postCmd}
%files
$filesList
%preun
$preun
EOF

echo "creating ${name} rpm package,please wait for a while..."
rpmbuild -bb ${name}.spec

echo "${name} rpm create done.rpm is locate at $HOME/rpmbuild/RPMS/$arch/"
echo 
echo "you can excute below command to install rpm package: "
if [[ $name == "apache" ]];then
	echo "yum -x httpd -y install ${name}-${version}-${release}.${arch}.rpm"
else
	echo "yum -y install ${name}-${version}-${release}.${arch}.rpm"
fi
}

#生成nginx rpm包
create_nginx_rpm(){
	local name="nginx"
	local version=`${nginx_location}/sbin/nginx -v 2>&1 | awk -F'/' '{print $2}'`
	local location="${nginx_location}"
	local filesPackage="${nginx_location} /etc/init.d/nginx /home/wwwroot/ /usr/bin/ez /tmp/ezhttp_info_do_not_del"
	local postCmd="groupadd www\nuseradd -M -s /bin/false -g www www\n/etc/init.d/nginx start"
	postCmd=$(echo -e $postCmd)
	local summary="nginx web server"
	local description="nginx web server"
	local preun="/etc/init.d/nginx stop"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"
}

#生成apache rpm包
create_apache_rpm(){
	local name="apache"
	local version=`${apache_location}/bin/httpd -v | awk -F'[/ ]' 'NR==1{print $4}'`
	local location="${apache_location}"
	local filesPackage="${apache_location} /etc/init.d/httpd /home/wwwroot/ /usr/bin/ez /tmp/ezhttp_info_do_not_del"
	local postCmd="groupadd www\nuseradd -M -s /bin/false -g www www\n/etc/init.d/httpd start"
	postCmd=$(echo -e $postCmd)
	local summary="apache web server"
	local description="apache web server"
	local preun="/etc/init.d/httpd stop"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"

}

#生成php rpm包
create_php_rpm(){

	local name="php"
	local version=`${php_location}/bin/php -v | awk 'NR==1{print $2}'`
	local location="${php_location}"
	local filesPackage=''
	local postCmd=''
	local preun=''
	if ${php_location}/bin/php -ini | grep -q "with-apxs";then
		filesPackage="${php_location} /usr/bin/ez /tmp/ezhttp_info_do_not_del"
	else
		filesPackage="${php_location} /etc/init.d/php-fpm /usr/bin/ez /tmp/ezhttp_info_do_not_del"
		postCmd="groupadd www\nuseradd -M -s /bin/false -g www www\n/etc/init.d/php-fpm start"
		preun="/etc/init.d/php-fpm stop"
	fi

	if is_64bit;then
		filesPackage="$filesPackage /usr/lib64/libiconv.so.2* /usr/lib64/libmcrypt.so.4* /usr/lib/libiconv.so.2* /usr/lib/libmcrypt.so.4* "
	else
		filesPackage="$filesPackage /usr/lib/libiconv.so.2* /usr/lib/libmcrypt.so.4*"
	fi	
	postCmd=$(echo -e $postCmd)
	local summary="php engine"
	local description="php engine"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"

}

#生成mysql rpm包
create_mysql_rpm(){
	local name="mysql"
	local version=`${mysql_location}/bin/mysql -V | awk '{print $5}' | tr -d ','`
	local location="${mysql_location}"
	local filesPackage=''
	for file in `ls ${mysql_location} | grep -v -E "data|mysql-test|sql-bench"`;do
		filesPackage="$filesPackage ${mysql_location}/$file"
	done

	filesPackage="$filesPackage /etc/init.d/mysqld /usr/bin/mysql /usr/bin/mysqldump /usr/bin/ez /tmp/ezhttp_info_do_not_del"
	local mysql_data_location=`${mysql_location}/bin/mysqld --print-defaults  | sed -r -n 's#.*datadir=([^ ]+).*#\1#p'`

	local postCmd="useradd  -M -s /bin/false mysql\n${mysql_location}/scripts/mysql_install_db --basedir=${mysql_location} --datadir=${mysql_data_location}  --defaults-file=${mysql_location}/etc/my.cnf --user=mysql\nchown -R mysql ${mysql_data_location}\n/etc/init.d/mysqld start"
	if echo $version | grep -q "^5\.1\.";then
		postCmd="useradd  -M -s /bin/false mysql\n${mysql_location}/bin/mysql_install_db --basedir=${mysql_location} --datadir=${mysql_data_location}  --defaults-file=${mysql_location}/etc/my.cnf --user=mysql\nchown -R mysql ${mysql_data_location}\n/etc/init.d/mysqld start"
	fi

	postCmd=$(echo -e $postCmd)
	local summary="mysql server"
	local description="mysql server"
	local preun="/etc/init.d/mysqld stop"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"

}

#生成memcached rpm包
create_memcached_rpm(){
	local name="memcached"
	local version=`${memcached_location}/bin/memcached -h | awk 'NR==1{print $2}'`
	local location="${memcached_location}"
	local filesPackage="${memcached_location} /etc/init.d/memcached"
	local postCmd="/etc/init.d/memcached start"
	local summary="memcached cache server"
	local description="memcached cache server"
	local preun="/etc/init.d/memcached stop"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"

}

#生成pureftpd rpm包
create_pureftpd_rpm(){

	local name="pureftpd"
	local version=`${pureftpd_location}/sbin/pure-ftpd -h | awk 'NR==1{print $2}' | tr -d v`
	local location="${pureftpd_location}"
	local filesPackage="${pureftpd_location} /etc/init.d/pureftpd /usr/bin/ez /tmp/ezhttp_info_do_not_del"
	local postCmd="/etc/init.d/pureftpd start"
	local summary="pureftpd ftp server"
	local description="pureftpd ftp server"
	local preun="/etc/init.d/pureftpd stop"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"

}


#rpm生成工具
Create_rpm_package(){
	if ! check_sys_version centos;then
		echo "create rpm package tool is only support system centos/redhat."
		exit
	fi

	#安装rpmbuild工具
	echo "start install rpmbuild tool,please wait for a few seconds..."
	echo
	yum -y install rpm-build

	#检测rpmbuild命令是否存在
	check_command_exist "rpmbuild"

	echo "available software can be created rpm below:"
	for ((i=1;i<=${#rpm_support_arr[@]};i++ )); do echo -e "$i) ${rpm_support_arr[$i-1]}"; done
	echo
	packages_prompt="please select which software you would like to create rpm(ie.1 2 3): "
	while true
	do
		read -p "${packages_prompt}" rpmCreate
		rpmCreate=(${rpmCreate})
		unset packages wrong
		for i in ${rpmCreate[@]}
		do
			if [ "${rpm_support_arr[$i-1]}" == "" ];then
				packages_prompt="input errors,please input numbers(ie.1 2 3): ";
				wrong=1
				break
			else	
				packages="$packages ${rpm_support_arr[$i-1]}"
				wrong=0
			fi
		done
		[ "$wrong" == 0 ] && break
	done
	echo -e "your packages selection ${packages}"

	#输入nginx location
	if if_in_array Nginx "$packages";then
		while true; do
			read -p "please input nginx location(default:/usr/local/nginx): " nginx_location
			nginx_location=${nginx_location:=/usr/local/nginx}
			nginx_location=`filter_location $nginx_location`
			if [ ! -d "$nginx_location" ];then
				echo "$nginx_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "nginx location: $nginx_location"
	fi

	#输入apache location
	if if_in_array Apache "$packages";then
		while true; do
			read -p "please input apache location(default:/usr/local/apache): " apache_location
			apache_location=${apache_location:=/usr/local/apache}
			apache_location=`filter_location $apache_location`
			if [ ! -d "$apache_location" ];then
				echo "$apache_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "apache location: $apache_location"
	fi

	#输入php location
	if if_in_array PHP "$packages";then
		while true; do
			read -p "please input php location(default:/usr/local/php): " php_location
			php_location=${php_location:=/usr/local/php}
			php_location=`filter_location $php_location`
			if [ ! -d "$php_location" ];then
				echo "$php_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "php location: $php_location"
	fi

	#输入mysql location
	if if_in_array MySQL "$packages";then
		while true; do
			read -p "please input mysql location(default:/usr/local/mysql): " mysql_location
			mysql_location=${mysql_location:=/usr/local/mysql}
			mysql_location=`filter_location $mysql_location`
			if [ ! -d "$mysql_location" ];then
				echo "$mysql_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "mysql location: $mysql_location"
	fi

	#输入memcached location
	if if_in_array Memcached "$packages";then
		while true; do
			read -p "please input memcached location(default:/usr/local/memcached): " memcached_location
			memcached_location=${memcached_location:=/usr/local/memcached}
			memcached_location=`filter_location $memcached_location`
			if [ ! -d "$memcached_location" ];then
				echo "$memcached_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "memcached location: $memcached_location"
	fi

	#输入pureftpd location
	if if_in_array PureFTPd "$packages";then
		while true; do
			read -p "please input pureftpd location(default:/usr/local/pureftpd): " pureftpd_location
			pureftpd_location=${pureftpd_location:=/usr/local/pureftpd}
			pureftpd_location=`filter_location $pureftpd_location`
			if [ ! -d "$pureftpd_location" ];then
				echo "$pureftpd_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "pureftpd location: $pureftpd_location"
	fi			

	eval 
	if_in_array Nginx "$packages" &&  create_nginx_rpm
	if_in_array Apache "$packages" && create_apache_rpm
	if_in_array PHP "$packages" && create_php_rpm
	if_in_array MySQL "$packages" && create_mysql_rpm
	if_in_array Memcached "$packages" && create_memcached_rpm
	if_in_array PureFTPd "$packages" && create_pureftpd_rpm

	exit
}

#percona xtrabackup工具安装
Percona_xtrabackup_install(){
	if check_sys_version ubuntu || check_sys_version debian;then
		apt-key adv --keyserver keys.gnupg.net --recv-keys 1C4CBDCDCD2EFD2A
		local version=`awk -F''= '/DISTRIB_CODENAME/{print $2}' /etc/lsb-release`
		if ! grep -q "http://repo.percona.com/apt" /etc/apt/sources.list;then
			echo -e "deb http://repo.percona.com/apt $version main\ndeb-src http://repo.percona.com/apt $version main\n" >>  /etc/apt/sources.list
		fi
		
		apt-get -y update
		apt-get -y install percona-xtrabackup

	elif check_sys_version centos;then
		if is_64bit;then
			rpm -Uhv http://www.percona.com/downloads/percona-release/percona-release-0.0-1.x86_64.rpm
		else
			rpm -Uhv http://www.percona.com/downloads/percona-release/percona-release-0.0-1.i386.rpm
		fi

		yum -y install percona-xtrabackup
	else
		echo "sorry,the percona xtrabackup install tool do not support your system,please let me know and make it support."
	fi

	exit

}

#更改ssh server端口
Change_sshd_port(){
	local listenPort=`netstat -nlpt | awk -F'[: ]+' '/sshd/{if ($5 ~/[0-9]/) print $5}'`
	local configPort=`grep -v "^#" /etc/ssh/sshd_config | sed -n -r 's/^Port\s+([0-9]+).*/\1/p'`
	configPort=${configPort:=22}

	echo "the ssh server is listenning at port $listenPort."
	echo "the /etc/ssh/sshd_config is configured port $configPort."

	local newPort=''
	while true; do
		read -p "please input your new ssh server port(range 0-65535,greater than 1024 is recommended.): " newPort
		if verify_port "$newPort";then
			break
		else
			echo "input error,must be a number(range 0-65535)."
		fi
	done

	#备份配置文件
	echo "backup sshd_config to sshd_config_original..."
	cp /etc/ssh/sshd_config /etc/ssh/sshd_config_original

	#开始改端口
	if grep -q -E "^Port\b" /etc/ssh/sshd_config;then
		sed -i -r "s/^Port\s+.*/Port $newPort/" /etc/ssh/sshd_config
	elif grep -q -E "#Port\b" /etc/ssh/sshd_config; then
		sed -i -r "s/#Port\s+.*/Port $newPort/" /etc/ssh/sshd_config
	else
		echo "Port $newPort" >> /etc/ssh/sshd_config
	fi
	
	#重启sshd
	local restartCmd=''
	if check_sys_version debian || check_sys_version ubuntu; then
		restartCmd="/etc/init.d/ssh restart"
	else
		restartCmd="/etc/init.d/sshd restart"
	fi
	$restartCmd

	#验证是否成功
	local nowPort=`netstat -nlpt | awk -F'[: ]+' '/sshd/{if ($5 ~/[0-9]/) print $5}'`
	if [[ "$nowPort" == "$newPort" ]]; then
		echo "change ssh server port to $newPort successfully."
	else
		echo "fail to change ssh server port to $newPort."
		echo "rescore the backup file /etc/ssh/sshd_config_original to /etc/ssh/sshd_config..."
		\cp /etc/ssh/sshd_config_original /etc/ssh/sshd_config
		$restartCmd
	fi

	exit
}

#清空iptables表
clean_iptables_rule(){
	iptables -P INPUT ACCEPT
	iptables -P OUTPUT ACCEPT
	iptables -X
	iptables -F
}

#iptables首次设置
iptables_init(){
	yes_or_no "we'll clean all rules before configure iptables,are you sure?[Y/n]: " "clean_iptables_rule" "Iptables_settings"

	echo "start to add a iptables rule..."
	echo

	#列出监听端口
	echo "the server is listenning below address:"
	echo 
	netstat -nlpt | awk -F'[/ ]+' 'BEGIN{printf("%-20s %-20s\n%-20s %-20s\n","Program name","Listen Address","------------","--------------")} $1 ~ /tcp/{printf("%-20s %-20s\n",$8,$4)}'
	echo
	#端口选择
	local ports=''
	local ports_arr=''
	while true; do
		read -p "please input one or more ports allowed(ie.22 80 3306): " ports
		ports_arr=($ports)
		local step=false
		for p in ${ports_arr[@]};do
			if ! verify_port "$p";then
				echo "your input is invalid."
				step=false
				break
			fi
			step=true
		done
		$step && break
		[ "$ports" == "" ] && echo "input can not be empty."
	done

	#检查端口是否包含ssh端口,否则自动加入,防止无法连接ssh
	local sshPort=`netstat -nlpt | awk -F'[: ]+' '/sshd/{if ($5 ~/[0-9]/) print $5}'`
	local sshNotInput=true
	for p in ${ports_arr[@]};do
		if [[ $p == "$sshPort" ]];then
			sshNotInput=false
		fi
	done

	$sshNotInput && ports="$ports $sshPort"

	#开始设置防火墙
	iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
	ports_arr=($ports)
	for p in ${ports_arr[@]};do
		iptables -A INPUT -p tcp -m tcp --dport $p -j ACCEPT
	done

	iptables -A INPUT -i lo -j ACCEPT
	iptables -A INPUT -p icmp -m icmp --icmp-type 8
	iptables -A INPUT -p icmp -m icmp --icmp-type 11
	iptables -P INPUT DROP

	if check_sys_version ubuntu || check_sys_version debian;then
		iptables-save > /etc/iptables.rule
	elif check_sys_version centos;then
		/etc/init.d/iptables save
	fi
	list_iptables
	echo "configure iptables done."
}

#增加规则
add_iptables_rule(){
	#协议选择
	while true; do
		echo -e "1) tcp\n2) udp\n"
		read -p "please specify the Protocol(default:tcp): " protocol
		protocol=${protocol:=1}
		case  $protocol in
			1) protocol=tcp;break;;
			2) protocol=udp;break;;
			*) echo "input error,please input a number(ie.1 2 3)";;
		esac
	done

	#来源ip选择
	while true; do
		read -p "please input the source ip address(ie. 8.8.8.8 192.168.0.0/24,leave blank for all.): " sourceIP
		if [[ $sourceIP != "" ]];then
			local ip=`echo $sourceIP | awk -F'/' '{print $1}'`
			local mask=`echo $sourceIP | awk -F'/' '{print $2}'`
			local step1=false
			local step2=false
			if [[ $mask != "" ]];then
				if echo $mask | grep -q -E "^[0-9]+$" && [[ $mask -ge 0 ]] && [[ $mask -le 32 ]];then
					step1=true
				fi	
			else
				step1=true
			fi	
			
			if verify_ip "$ip";then
				step2=true
			fi
			
			if $step1 && $step2;then
				sourceIP="-s $sourceIP"
				break
			else
				echo "the ip is invalid."
			fi
		else
			break
		fi		
	done

	#端口选择
	local port=''
	while true; do
		read -p "please input one or more ports allowed(ie.3306): " port
		if  verify_port "$port";then
			break
		else
			echo "your input is invalid."
		fi	
	done

	#动作选择
	while true; do
		echo -e "1) ACCEPT\n2) DROP\n"
		read -p "select action(default:ACCEPT): " action
		action=${action:=1}
		case $action in
			1) action=ACCEPT;break;;
			2) action=DROP;break;;
			*) echo "input error,please input a number(ie.1 2)."
		esac
	done

	#开始添加记录
	local cmd='-A'
	if [[ "$action" == "ACCEPT" ]];then
		cmd="-A"
	elif [[ "$action" == "DROP" ]]; then
		cmd="-I"
	fi
	
	if iptables $cmd INPUT -p $protocol $sourceIP --dport $port -j $action;then
		echo "add iptables rule successfully."
	else
		echo "add iptables rule failed."
	fi
	list_iptables
}

#删除规则
delete_iptables_rule(){
	iptables -nL INPUT --line-number
	echo
	while true; do
		read -p "please input the number according to the first column: " number
		if echo "$number" | grep -q -E "^[0-9]+$";then
			break
		else
			echo "input error,please input a number."
		fi		
	done

	#开始删除规则
	if iptables -D INPUT $number;then
		echo "delete the iptables rule successfully."
	else
		echo "delete the iptables rule failed."
	fi
	list_iptables
}

#停止ipables
stop_iptables(){
	#保存规则
	if check_sys_version ubuntu || check_sys_version debian;then
		iptables-save > /etc/iptables.rule
	elif check_sys_version centos;then
		/etc/init.d/iptables save
	fi

	clean_iptables_rule
	list_iptables
}

#恢复iptables
rescore_iptables(){

	if check_sys_version ubuntu || check_sys_version debian;then
		if [ -s "/etc/iptables.rule" ];then
			iptables-restore < /etc/iptables.rule
			echo "rescore iptables done."
		else
			echo "/etc/iptables.rule not found,can not be rescore iptables."
		fi	
	elif check_sys_version centos;then
		/etc/init.d/iptables restart
		echo "rescore iptables done."
	fi
	list_iptables
}

#列出iptables
list_iptables(){
	iptables -nL INPUT
}
#iptales设置
Iptables_settings(){
	check_command_exist "iptables"
	local select=''
	while true; do
		echo -e "1) clear all record,setting from nothing.\n2) add a iptables rule.\n3) delete any rule.\n4) backup rules and stop iptables.\n5) rescore iptables\n6) list iptables rules\n" 
		read -p "please input your select(ie 1 2 3): " select
		case  $select in
			1) iptables_init;break;;
			2) add_iptables_rule;break;;
			3) delete_iptables_rule;break;;
			4) stop_iptables;break;;
			5) rescore_iptables;break;;
			6) list_iptables;break;;
			*) echo "input error,please input a number.";;
		esac
	done

	exit
}

#开启或关闭共享扩展
Enable_disable_php_extension(){
	#获取php路径
	if [[ $php_location == "" ]];then
		while true; do
			read -p "please input the php location(default:/usr/local/php): " php_location
			php_location=${php_location:=/usr/local/php}
			php_location=`filter_location "$php_location"`
			if [[ -s $php_location/bin/php ]];then
				break
			else
				echo "input error,$php_location/bin/php not found."
			fi
		done
	fi	

	enabled_extensions=`${php_location}/bin/php -m | awk '$0 ~/^[a-z]/{printf $0" " }'`
	extension_dir=`${php_location}/bin/php-config --extension-dir`
	shared_extensions=`cd $extension_dir;ls *.so | awk -F'.' '{print $1}'`
	shared_extensions_arr=($shared_extensions)
	echo "extension          state"
	echo "---------          -----"
	for extension in ${shared_extensions_arr[@]};do 
		if if_in_array $extension "$enabled_extensions";then
			state="enabled"
		else
			state="disabled"
		fi
		printf "%-15s%9s\n" $extension $state	

	done

	#输入扩展
	while true; do
		echo
		read -p "please input the extension you'd like to enable or disable(ie. curl): " extensionName
		if [[ $extensionName == "" ]];then
			echo "input can not be empty."
		elif if_in_array $extensionName "$shared_extensions";then
			break
		else
			echo "sorry,the extension $extensionName is not found."
		fi	
	done

	#开始启用或关闭扩展
	if if_in_array $extensionName "$enabled_extensions";then
		#关闭扩展
		sed -i "/extension=$extensionName.so/d" ${php_location}/etc/php.ini
		enabled_extensions=`${php_location}/bin/php -m | awk '$0 ~/^[a-z]/{printf $0" " }'`
		if if_in_array $extensionName "$enabled_extensions";then
			echo "disable extension $extensionName failed."
		else
			echo "disable extension $extensionName successfully."
		fi		
	else
		#开启扩展
		echo "extension=${extensionName}.so" >> ${php_location}/etc/php.ini
		enabled_extensions=`${php_location}/bin/php -m | awk '$0 ~/^[a-z]/{printf $0" " }'`
		if if_in_array $extensionName "$enabled_extensions";then
			echo "enable extension $extensionName successfully."
		else
			echo "enable extension $extensionName failed."
		fi
	fi	

	yes_or_no "do you want to continue enable or disable php extensions[Y/n]: " "Enable_disable_php_extension" "echo 'restarting php to take modifies affect...';restart_php;exit"
}

#工具设置
tools_setting(){
	clear
	display_menu tools
	if [ "$tools" == "Back_to_main_menu" ];then
		clear
		pre_setting
	else
		eval $tools
	fi	

}