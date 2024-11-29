#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HOSTNAME=$(hostname -f)
PASSV_PORT="50000:50100";
PASSV_MIN=$(echo $PASSV_PORT | cut -d':' -f1)
PASSV_MAX=$(echo $PASSV_PORT | cut -d':' -f2)
ISVPS=$(((dmidecode -t system 2>/dev/null | grep "Manufacturer" | grep -i 'VMware\|KVM\|Bochs\|Virtual\|HVM' > /dev/null) || [ -f /proc/vz/veinfo ]) && echo "SI" || echo "NO")

echo "██╗    ██╗███╗   ██╗██████╗  ██████╗ ██╗    ██╗███████╗██████╗     ██████╗ ██████╗ ███╗   ███╗"
echo "██║    ██║████╗  ██║██╔══██╗██╔═══██╗██║    ██║██╔════╝██╔══██╗   ██╔════╝██╔═══██╗████╗ ████║"
echo "██║ █╗ ██║██╔██╗ ██║██████╔╝██║   ██║██║ █╗ ██║█████╗  ██████╔╝   ██║     ██║   ██║██╔████╔██║"
echo "██║███╗██║██║╚██╗██║██╔═══╝ ██║   ██║██║███╗██║██╔══╝  ██╔══██╗   ██║     ██║   ██║██║╚██╔╝██║"
echo "╚███╔███╔╝██║ ╚████║██║     ╚██████╔╝╚███╔███╔╝███████╗██║  ██║██╗╚██████╗╚██████╔╝██║ ╚═╝ ██║"
echo " ╚══╝╚══╝ ╚═╝  ╚═══╝╚═╝      ╚═════╝  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝"

echo ""
echo "             ####################### cPanel Configurator #######################              "
echo ""
echo ""

if [ ! -f /etc/redhat-release ]; then
	echo "No se detectó CentOS. Abortando."
	exit 0
fi

echo "Este script instala y pre-configura cPanel sobre un servidor recién instalado"
echo "NO EJECUTAR EN UN SERVIDOR CON cPanel YA FUNCIONANDO (CTRL + C para cancelar)"
sleep 30

echo "####### CONFIGURANDO CENTOS #######"
wget https://raw.githubusercontent.com/wnpower/Linux-Config/master/configure_linux.sh -O "$CWD/configure_linux.sh" && bash "$CWD/configure_linux.sh"

echo "####### PRE-CONFIGURACION CPANEL ##########"
echo "Desactivando yum-cron..."
yum erase yum-cron -y 2>/dev/null # CentOS
yum erase dnf-automatic -y 2>/dev/null # Almalinux

echo "######### FIN CONFIGURANDO DNS Y RED ########"

echo "####### DESACTIVANDO SELINUX #######"

# PRE-REQUISITOS PARA INSTALAR cPANEL
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/sysconfig/selinux 2>/dev/null
setenforce 0
yum remove setroubleshoot* -y
yum install crontabs cronie cronie-anacron -y
yum install openldap-compat -y # Lo necesita servicio cpanel_php_fpm AL9

echo "####### FIN DESACTIVANDO SELINUX #######"

echo "####### INSTALANDO CPANEL #######"
if [ -f /usr/local/cpanel/cpanel ]; then
        echo "cPanel ya detectado, no se instala, sólo se configura (CTRL + C para cancelar)"
        sleep 10
else
	hostname -f > /root/hostname

	# INSTALAR MARIADB 10.6 POR DEFECTO https://cloudlinux.zendesk.com/hc/en-us/articles/360020599839
	mkdir -p /root/cpanel_profile/
	echo "mysql-version=10.6" >> /root/cpanel_profile/cpanel.config

	cd /home && curl -o latest -L https://securedownloads.cpanel.net/latest && sh latest --skip-cloudlinux

	echo "Esperando 5 minutos a que termine de instalar paquetes remanentes en segundo plano para continuar..."
	sleep 300
fi
echo "####### FIN INSTALANDO CPANEL #######"

echo "####### VERIFICANDO LICENCIA #######"
i=0
while ! (curl -m 10 -L "https://verify.cpanel.net?ip=$(curl -m 10 -L checkip.amazonaws.com 2>/dev/null)" 2>/dev/null | grep -v "active on" | grep "active" > /dev/null); do
	if [ $i -gt 30 ]; then
        	echo "Se reintentó más de $i veces, no se puede seguir. Licenciá la IP y luego ejecutá este script de nuevo."
        	exit 1
	fi
        
	echo "Licencia de cPanel no detectada, se reintenta en 5 minutos..."
        sleep 300
        ((i=i+1))
done
/usr/local/cpanel/cpkeyclt

echo "####### FIN VERIFICANDO LICENCIA #######"

whmapi1 sethostname hostname=$(cat /root/hostname) # Fix cambio de hostname por cprapid.com cpanel v90 https://docs.cpanel.net/knowledge-base/dns/automatically-issued-hostnames/
hostnamectl set-hostname $(cat /root/hostname)
rm -f /root/hostname

# Forzar MariaDB en vez de MySQL 8
if grep "mysql-version=8.0" /var/cpanel/cpanel.config > /dev/null; then
        dnf -y remove mysql-community-*
        rm -rf /var/lib/mysql
        sed -i 's/mysql-version=8.0/mysql-version=10.6/g' /var/cpanel/cpanel.config
        whmapi1 start_background_mysql_upgrade version=10.6

        sleep 600
fi

# SWAP
if ! free | awk '/^Swap:/ {exit (!$2 || ($2<4194300))}'; then
	echo "SWAP no detectada o menos de 4GB. Configurando..."
	/usr/local/cpanel/bin/create-swap --size 4G -v # Por defecto 4GB
fi

echo "####### CONFIGURANDO CSF #######"
if [ ! -d /etc/csf ]; then
        echo "csf no detectado, descargando!"
	touch /etc/sysconfig/iptables
	touch /etc/sysconfig/iptables6
	systemctl start iptables
	systemctl start ip6tables
	systemctl enable iptables
	systemctl enable ip6tables

	echo "Desactivando Firewalld..."
        systemctl disable firewalld
        systemctl stop firewalld

        yum remove firewalld -y
        yum -y install iptables-services wget perl unzip net-tools perl-libwww-perl perl-LWP-Protocol-https perl-GDGraph

	cd /root && rm -f ./csf.tgz; wget https://download.configserver.com/csf.tgz && tar xvfz ./csf.tgz && cd ./csf && sh ./install.sh
fi

echo " Configurando CSF..."
yum remove firewalld -y
yum -y install iptables-services wget perl unzip net-tools perl-libwww-perl perl-LWP-Protocol-https perl-GDGraph

sed -i 's/^TESTING = .*/TESTING = "0"/g' /etc/csf/csf.conf
sed -i 's/^ICMP_IN = .*/ICMP_IN = "0"/g' /etc/csf/csf.conf
sed -i 's/^IPV6 = .*/IPV6 = "0"/g' /etc/csf/csf.conf
sed -i 's/^DENY_IP_LIMIT = .*/DENY_IP_LIMIT = "400"/g' /etc/csf/csf.conf
sed -i 's/^SAFECHAINUPDATE = .*/SAFECHAINUPDATE = "1"/g' /etc/csf/csf.conf
sed -i 's/^CC_DENY = .*/CC_DENY = ""/g' /etc/csf/csf.conf
sed -i 's/^CC_IGNORE = .*/CC_IGNORE = ""/g' /etc/csf/csf.conf
sed -i 's/^SMTP_BLOCK = .*/SMTP_BLOCK = "1"/g' /etc/csf/csf.conf
sed -i 's/^LF_FTPD = .*/LF_FTPD = "30"/g' /etc/csf/csf.conf
sed -i 's/^LF_SMTPAUTH = .*/LF_SMTPAUTH = "90"/g' /etc/csf/csf.conf
sed -i 's/^LF_EXIMSYNTAX = .*/LF_EXIMSYNTAX = "0"/g' /etc/csf/csf.conf
sed -i 's/^LF_POP3D = .*/LF_POP3D = "100"/g' /etc/csf/csf.conf
sed -i 's/^LF_IMAPD = .*/LF_IMAPD = "100"/g' /etc/csf/csf.conf
sed -i 's/^LF_HTACCESS = .*/LF_HTACCESS = "40"/g' /etc/csf/csf.conf
sed -i 's/^LF_CPANEL = .*/LF_CPANEL = "40"/g' /etc/csf/csf.conf
sed -i 's/^LF_MODSEC = .*/LF_MODSEC = "100"/g' /etc/csf/csf.conf
sed -i 's/^LF_CXS = .*/LF_CXS = "10"/g' /etc/csf/csf.conf
sed -i 's/^LT_POP3D =  .*/LT_POP3D = "180"/g' /etc/csf/csf.conf
sed -i 's/^CT_SKIP_TIME_WAIT = .*/CT_SKIP_TIME_WAIT = "1"/g' /etc/csf/csf.conf
sed -i 's/^PT_LIMIT = .*/PT_LIMIT = "0"/g' /etc/csf/csf.conf
sed -i 's/^ST_MYSQL = .*/ST_MYSQL = "1"/g' /etc/csf/csf.conf
sed -i 's/^ST_APACHE = .*/ST_APACHE = "1"/g' /etc/csf/csf.conf
sed -i 's/^CONNLIMIT = .*/CONNLIMIT = "80;70,110;50,993;50,143;50,25;30"/g' /etc/csf/csf.conf
sed -i 's/^LF_PERMBLOCK_INTERVAL = .*/LF_PERMBLOCK_INTERVAL = "14400"/g' /etc/csf/csf.conf
sed -i 's/^LF_INTERVAL = .*/LF_INTERVAL = "900"/g' /etc/csf/csf.conf
sed -i 's/^PS_INTERVAL = .*/PS_INTERVAL = "60"/g' /etc/csf/csf.conf
sed -i 's/^PS_LIMIT = .*/PS_LIMIT = "60"/g' /etc/csf/csf.conf

echo "Deshabilitando alertas..."

sed -i 's/^LF_PERMBLOCK_ALERT = .*/LF_PERMBLOCK_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^LF_NETBLOCK_ALERT = .*/LF_NETBLOCK_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^LF_EMAIL_ALERT = .*/LF_EMAIL_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^LF_CPANEL_ALERT = .*/LF_CPANEL_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^LF_QUEUE_ALERT = .*/LF_QUEUE_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^LF_DISTFTP_ALERT = .*/LF_DISTFTP_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^LF_DISTSMTP_ALERT = .*/LF_DISTSMTP_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^LT_EMAIL_ALERT = .*/LT_EMAIL_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^RT_RELAY_ALERT = .*/RT_RELAY_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^RT_AUTHRELAY_ALERT = .*/RT_AUTHRELAY_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^RT_POPRELAY_ALERT = .*/RT_POPRELAY_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^RT_LOCALRELAY_ALERT = .*/RT_LOCALRELAY_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^RT_LOCALHOSTRELAY_ALERT = .*/RT_LOCALHOSTRELAY_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^CT_EMAIL_ALERT = .*/CT_EMAIL_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^PT_USERKILL_ALERT = .*/PT_USERKILL_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^PS_EMAIL_ALERT = .*/PS_EMAIL_ALERT = "0"/g' /etc/csf/csf.conf
sed -i 's/^PT_USERMEM = .*/PT_USERMEM = "0"/g' /etc/csf/csf.conf
sed -i 's/^PT_USERTIME = .*/PT_USERTIME = "0"/g' /etc/csf/csf.conf
sed -i 's/^PT_USERPROC = .*/PT_USERPROC = "0"/g' /etc/csf/csf.conf
sed -i 's/^PT_USERRSS = .*/PT_USERRSS = "0"/g' /etc/csf/csf.conf

echo "Activando rango pasivo FTP..."
# IPv4
CURR_CSF_IN=$(grep "^TCP_IN" /etc/csf/csf.conf | cut -d'=' -f2 | sed 's/\ //g' | sed 's/\"//g' | sed "s/,$PASSV_PORT,/,/g" | sed "s/,$PASSV_PORT//g" | sed "s/$PASSV_PORT,//g" | sed "s/,,//g")
sed -i "s/^TCP_IN.*/TCP_IN = \"$CURR_CSF_IN,$PASSV_PORT\"/" /etc/csf/csf.conf

CURR_CSF_OUT=$(grep "^TCP_OUT" /etc/csf/csf.conf | cut -d'=' -f2 | sed 's/\ //g' | sed 's/\"//g' | sed "s/,$PASSV_PORT,/,/g" | sed "s/,$PASSV_PORT//g" | sed "s/$PASSV_PORT,//g" | sed "s/,,//g")
sed -i "s/^TCP_OUT.*/TCP_OUT = \"$CURR_CSF_OUT,$PASSV_PORT\"/" /etc/csf/csf.conf

# IPv6
CURR_CSF_IN6=$(grep "^TCP6_IN" /etc/csf/csf.conf | cut -d'=' -f2 | sed 's/\ //g' | sed 's/\"//g' | sed "s/,$PASSV_PORT,/,/g" | sed "s/,$PASSV_PORT//g" | sed "s/$PASSV_PORT,//g" | sed "s/,,//g")
sed -i "s/^TCP6_IN.*/TCP6_IN = \"$CURR_CSF_IN6,$PASSV_PORT\"/" /etc/csf/csf.conf

CURR_CSF_OUT6=$(grep "^TCP6_OUT" /etc/csf/csf.conf | cut -d'=' -f2 | sed 's/\ //g' | sed 's/\"//g' | sed "s/,$PASSV_PORT,/,/g" | sed "s/,$PASSV_PORT//g" | sed "s/$PASSV_PORT,//g" | sed "s/,,//g")
sed -i "s/^TCP6_OUT.*/TCP6_OUT = \"$CURR_CSF_OUT6,$PASSV_PORT\"/" /etc/csf/csf.conf

echo "Habilitando listas negras..."
sed -i '/^#SPAMDROP/s/^#//' /etc/csf/csf.blocklists
sed -i '/^#SPAMEDROP/s/^#//' /etc/csf/csf.blocklists
sed -i '/^#DSHIELD/s/^#//' /etc/csf/csf.blocklists
sed -i '/^#HONEYPOT/s/^#//' /etc/csf/csf.blocklists
#sed -i '/^#MAXMIND/s/^#//' /etc/csf/csf.blocklists FALSOS POSITIVOS
sed -i '/^#BDE|/s/^#//' /etc/csf/csf.blocklists

sed -i '/^SPAMDROP/s/|0|/|300|/' /etc/csf/csf.blocklists
sed -i '/^SPAMEDROP/s/|0|/|300|/' /etc/csf/csf.blocklists
sed -i '/^DSHIELD/s/|0|/|300|/' /etc/csf/csf.blocklists
sed -i '/^HONEYPOT/s/|0|/|300|/' /etc/csf/csf.blocklists
#sed -i '/^MAXMIND/s/|0|/|300|/' /etc/csf/csf.blocklists # FALSOS POSITIVOS
sed -i '/^BDE|/s/|0|/|300|/' /etc/csf/csf.blocklists

sed -i '/^TOR/s/^TOR/#TOR/' /etc/csf/csf.blocklists
sed -i '/^ALTTOR/s/^ALTTOR/#ALTTOR/' /etc/csf/csf.blocklists
sed -i '/^CIARMY/s/^CIARMY/#CIARMY/' /etc/csf/csf.blocklists
sed -i '/^BFB/s/^BFB/#BFB/' /etc/csf/csf.blocklists
sed -i '/^OPENBL/s/^OPENBL/#OPENBL/' /etc/csf/csf.blocklists
sed -i '/^BDEALL/s/^BDEALL/#BDEALL/' /etc/csf/csf.blocklists
	
cat > /etc/csf/csf.rignore << EOF
.cpanel.net
.googlebot.com
.crawl.yahoo.net
.search.msn.com
EOF

echo "Abriendo puertos en CSF para TCP_OUT migraciones cPanel..."
CPANEL_PORTS="2082,2083"
CURR_CSF_OUT=$(grep "^TCP_OUT" /etc/csf/csf.conf | cut -d'=' -f2 | sed 's/\ //g' | sed 's/\"//g' | sed "s/,$CPANEL_PORTS,/,/g" | sed "s/,$CPANEL_PORTS//g" | sed "s/$CPANEL_PORTS,//g" | sed "s/,,//g")
sed -i "s/^TCP_OUT.*/TCP_OUT = \"$CURR_CSF_OUT,$CPANEL_PORTS\"/" /etc/csf/csf.conf

echo "Activando DYNDNS..."
sed -i 's/^DYNDNS = .*/DYNDNS = "300"/g' /etc/csf/csf.conf
sed -i 's/^DYNDNS_IGNORE = .*/DYNDNS_IGNORE = "1"/g' /etc/csf/csf.conf

echo "Agregando a csf.dyndns..."
sed -i '/gmail.com/d' /etc/csf/csf.dyndns
sed -i '/public.pyzor.org/d' /etc/csf/csf.dyndns
echo "tcp|out|d=25|d=smtp.gmail.com" >> /etc/csf/csf.dyndns
echo "tcp|out|d=465|d=smtp.gmail.com" >> /etc/csf/csf.dyndns
echo "tcp|out|d=587|d=smtp.gmail.com" >> /etc/csf/csf.dyndns
echo "tcp|out|d=995|d=imap.gmail.com" >> /etc/csf/csf.dyndns
echo "tcp|out|d=993|d=imap.gmail.com" >> /etc/csf/csf.dyndns
echo "tcp|out|d=143|d=imap.gmail.com" >> /etc/csf/csf.dyndns
echo "udp|out|d=24441|d=public.pyzor.org" >> /etc/csf/csf.dyndns

csf -r
service lfd restart

echo "####### FIN CONFIGURANDO CSF #######"
echo "####### CONFIGURANDO CPANEL #######"

if [ ! -d /usr/local/cpanel ]; then
	echo "cPanel no detectado. Abortando."
	exit 0
fi

HOSTNAME_LONG=$(hostname -d)

echo "Bajando TTL de DNS a 15 minutos..."
sed -i 's/^TTL .*/TTL 900/' /etc/wwwacct.conf

echo "Cambiando mail de contacto..."
sed -i '/^CONTACTEMAIL\ .*/d' /etc/wwwacct.conf
echo "CONTACTEMAIL hostmaster@$HOSTNAME_LONG" >> /etc/wwwacct.conf

echo "Cambiando default DNSs..."
sed -i '/^NS\ .*/d' /etc/wwwacct.conf
sed -i '/^NS2\ .*/d' /etc/wwwacct.conf
sed -i '/^NS3\ .*/d' /etc/wwwacct.conf
echo "NS ns1.$HOSTNAME_LONG" >> /etc/wwwacct.conf
echo "NS2 ns2.$HOSTNAME_LONG" >> /etc/wwwacct.conf

echo "Configurando FTP..."
sed -i '/^MaxClientsPerIP:.*/d' /var/cpanel/conf/pureftpd/local > /dev/null; echo "MaxClientsPerIP: 30" >> /var/cpanel/conf/pureftpd/local
sed -i '/^RootPassLogins:.*/d' /var/cpanel/conf/pureftpd/local > /dev/null; echo "RootPassLogins: 'no'" >> /var/cpanel/conf/pureftpd/local
sed -i '/^PassivePortRange:.*/d' /var/cpanel/conf/pureftpd/local > /dev/null; echo "PassivePortRange: $PASSV_MIN $PASSV_MAX" >> /var/cpanel/conf/pureftpd/local
sed -i '/^TLSCipherSuite:.*/d' /var/cpanel/conf/pureftpd/local > /dev/null; echo 'TLSCipherSuite: "HIGH:MEDIUM:+TLSv1:!SSLv2:+SSLv3"' >> /var/cpanel/conf/pureftpd/local
sed -i '/^LimitRecursion:.*/d' /var/cpanel/conf/pureftpd/local > /dev/null; echo "LimitRecursion: 50000 12" >> /var/cpanel/conf/pureftpd/local

/usr/local/cpanel/scripts/setupftpserver pure-ftpd --force

echo "Activando módulo ip_conntrack_ftp..."
modprobe ip_conntrack_ftp
echo "modprobe ip_conntrack_ftp" >> /etc/rc.modules
chmod +x /etc/rc.modules

echo "Configurando Tweak Settings..."
whmapi1 set_tweaksetting key=allowremotedomains value=1
whmapi1 set_tweaksetting key=allowunregistereddomains value=1
whmapi1 set_tweaksetting key=chkservd_check_interval value=120
whmapi1 set_tweaksetting key=defaultmailaction value=fail
whmapi1 set_tweaksetting key=email_send_limits_max_defer_fail_percentage value=25
whmapi1 set_tweaksetting key=email_send_limits_min_defer_fail_to_trigger_protection value=15
whmapi1 set_tweaksetting key=maxemailsperhour value=200
whmapi1 set_tweaksetting key=permit_unregistered_apps_as_root value=1
whmapi1 set_tweaksetting key=requiressl value=0
whmapi1 set_tweaksetting key=skipanalog value=1
whmapi1 set_tweaksetting key=skipboxtrapper value=1
whmapi1 set_tweaksetting key=skipwebalizer value=1
whmapi1 set_tweaksetting key=smtpmailgidonly value=0
whmapi1 set_tweaksetting key=eximmailtrap value=1
whmapi1 set_tweaksetting key=use_information_schema value=0
whmapi1 set_tweaksetting key=cookieipvalidation value=disabled
whmapi1 set_tweaksetting key=notify_expiring_certificates value=0
whmapi1 set_tweaksetting key=cpaddons_notify_owner value=0
whmapi1 set_tweaksetting key=cpaddons_notify_root value=0
whmapi1 set_tweaksetting key=enable_piped_logs value=1
whmapi1 set_tweaksetting key=email_outbound_spam_detect_action value=block
whmapi1 set_tweaksetting key=email_outbound_spam_detect_enable value=1
whmapi1 set_tweaksetting key=email_outbound_spam_detect_threshold value=120
whmapi1 set_tweaksetting key=skipspambox value=0
whmapi1 set_tweaksetting key=skipmailman value=1
whmapi1 set_tweaksetting key=jaildefaultshell value=1
whmapi1 set_tweaksetting key=php_post_max_size value=100
whmapi1 set_tweaksetting key=php_upload_max_filesize value=100
whmapi1 set_tweaksetting key=empty_trash_days value=30
whmapi1 set_tweaksetting key=publichtmlsubsonly value=0
whmapi1 set_tweaksetting key=proxysubdomainsoverride value=0

# DESACTIVAR RESET DE PASSWORD POR MAIL
whmapi1 set_tweaksetting key=resetpass value=0
whmapi1 set_tweaksetting key=resetpass_sub value=0

sed -i 's/^phpopenbasedirhome=.*/phpopenbasedirhome=1/' /var/cpanel/cpanel.config
sed -i 's/^minpwstrength=.*/minpwstrength=70/' /var/cpanel/cpanel.config

/usr/local/cpanel/etc/init/startcpsrvd

# CONFIGURACIONES QUE NO SE PUEDEN HACER POR CONSOLA
echo "Configurando lo inconfigurable desde consola..."
yum install -y curl

touch $CWD/wpwhmcookie.txt
SESS_CREATE=$(whmapi1 create_user_session user=root service=whostmgrd)
SESS_TOKEN=$(echo "$SESS_CREATE" | grep "cp_security_token:" | cut -d':' -f2- | sed 's/ //')
SESS_QS=$(echo "$SESS_CREATE" | grep "session:" | cut -d':' -f2- | sed 's/ //' | sed 's/ /%20/g;s/!/%21/g;s/"/%22/g;s/#/%23/g;s/\$/%24/g;s/\&/%26/g;s/'\''/%27/g;s/(/%28/g;s/)/%29/g;s/:/%3A/g')

curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/login/?session=$SESS_QS" --cookie-jar $CWD/wpwhmcookie.txt > /dev/null

echo "Deshabilitando compilers..."
curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/scripts2/tweakcompilers" --cookie $CWD/wpwhmcookie.txt --data 'action=Disable+Compilers' > /dev/null
echo "Deshabilitando SMTP Restrictions (se usa CSF)..."
curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/scripts2/smtpmailgidonly?action=Disable" --cookie $CWD/wpwhmcookie.txt > /dev/null
echo "Deshabilitando Shell Fork Bomb Protection..."
curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/scripts2/modlimits?limits=0" --cookie $CWD/wpwhmcookie.txt > /dev/null
echo "Habilitando Background Process Killer..."
curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/json-api/configurebackgroundprocesskiller" --cookie $CWD/wpwhmcookie.txt --data 'api.version=1&processes_to_kill=BitchX&processes_to_kill=bnc&processes_to_kill=eggdrop&processes_to_kill=generic-sniffers&processes_to_kill=guardservices&processes_to_kill=ircd&processes_to_kill=psyBNC&processes_to_kill=ptlink&processes_to_kill=services&force=1' > /dev/null

echo "Configurando Apache..."
# CONF BASICA
curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/scripts2/saveglobalapachesetup" --cookie $CWD/wpwhmcookie.txt --data 'module=Apache&find=&___original_sslciphersuite=ECDHE-ECDSA-AES256-GCM-SHA384%3AECDHE-RSA-AES256-GCM-SHA384%3AECDHE-ECDSA-CHACHA20-POLY1305%3AECDHE-RSA-CHACHA20-POLY1305%3AECDHE-ECDSA-AES128-GCM-SHA256%3AECDHE-RSA-AES128-GCM-SHA256%3AECDHE-ECDSA-AES256-SHA384%3AECDHE-RSA-AES256-SHA384%3AECDHE-ECDSA-AES128-SHA256%3AECDHE-RSA-AES128-SHA256&sslciphersuite_control=default&___original_sslprotocol=TLSv1.2&sslprotocol_control=default&___original_loglevel=warn&loglevel=warn&___original_traceenable=Off&traceenable=Off&___original_serversignature=Off&serversignature=Off&___original_servertokens=ProductOnly&servertokens=ProductOnly&___original_fileetag=None&fileetag=None&___original_root_options=&root_options=FollowSymLinks&root_options=IncludesNOEXEC&root_options=SymLinksIfOwnerMatch&___original_startservers=5&startservers_control=default&___original_minspareservers=5&minspareservers_control=default&___original_maxspareservers=10&maxspareservers_control=default&___original_optimize_htaccess=search_homedir_below&optimize_htaccess=search_homedir_below&___original_serverlimit=256&serverlimit_control=default&___original_maxclients=150&maxclients_control=other&maxclients_other=100&___original_maxrequestsperchild=10000&maxrequestsperchild_control=default&___original_keepalive=On&keepalive=1&___original_keepalivetimeout=5&keepalivetimeout_control=3&___original_maxkeepaliverequests=100&maxkeepaliverequests_control=20&___original_timeout=300&timeout_control=default&___original_symlink_protect=Off&symlink_protect=0&its_for_real=1' > /dev/null

# DIRECTORYINDEX
curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/scripts2/save_apache_directoryindex" --cookie $CWD/wpwhmcookie.txt --data 'valid_submit=1&dirindex=index.php&dirindex=index.php5&dirindex=index.php4&dirindex=index.php3&dirindex=index.perl&dirindex=index.pl&dirindex=index.plx&dirindex=index.ppl&dirindex=index.cgi&dirindex=index.jsp&dirindex=index.jp&dirindex=index.phtml&dirindex=index.shtml&dirindex=index.xhtml&dirindex=index.html&dirindex=index.htm&dirindex=index.wml&dirindex=Default.html&dirindex=Default.htm&dirindex=default.html&dirindex=default.htm&dirindex=home.html&dirindex=home.htm&dirindex=index.js' > /dev/null

curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/scripts2/save_apache_mem_limits" --cookie $CWD/wpwhmcookie.txt --data 'newRLimitMem=enabled&newRLimitMemValue=1024&restart_apache=on&btnSave=1' > /dev/null

/scripts/rebuildhttpdconf
service httpd restart

# DOVECOT
curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/scripts2/savedovecotsetup" --cookie $CWD/wpwhmcookie.txt --data 'protocols_enabled_imap=on&protocols_enabled_pop3=on&ipv6=on&enable_plaintext_auth=yes&ssl_cipher_list=ECDHE-ECDSA-CHACHA20-POLY1305%3AECDHE-RSA-CHACHA20-POLY1305%3AECDHE-ECDSA-AES128-GCM-SHA256%3AECDHE-RSA-AES128-GCM-SHA256%3AECDHE-ECDSA-AES256-GCM-SHA384%3AECDHE-RSA-AES256-GCM-SHA384%3ADHE-RSA-AES128-GCM-SHA256%3ADHE-RSA-AES256-GCM-SHA384%3AECDHE-ECDSA-AES128-SHA256%3AECDHE-RSA-AES128-SHA256%3AECDHE-ECDSA-AES128-SHA%3AECDHE-RSA-AES256-SHA384%3AECDHE-RSA-AES128-SHA%3AECDHE-ECDSA-AES256-SHA384%3AECDHE-ECDSA-AES256-SHA%3AECDHE-RSA-AES256-SHA%3ADHE-RSA-AES128-SHA256%3ADHE-RSA-AES128-SHA%3ADHE-RSA-AES256-SHA256%3ADHE-RSA-AES256-SHA%3AECDHE-ECDSA-DES-CBC3-SHA%3AECDHE-RSA-DES-CBC3-SHA%3AEDH-RSA-DES-CBC3-SHA%3AAES128-GCM-SHA256%3AAES256-GCM-SHA384%3AAES128-SHA256%3AAES256-SHA256%3AAES128-SHA%3AAES256-SHA%3ADES-CBC3-SHA%3A%21DSS&ssl_min_protocol=TLSv1&max_mail_processes=512&mail_process_size=512&protocol_imap.mail_max_userip_connections=20&protocol_imap.imap_idle_notify_interval=24&protocol_pop3.mail_max_userip_connections=3&login_processes_count=2&login_max_processes_count=50&login_process_size=128&auth_cache_size=1M&auth_cache_ttl=3600&auth_cache_negative_ttl=3600&login_process_per_connection=no&config_vsz_limit=2048&mailbox_idle_check_interval=30&mdbox_rotate_size=10M&mdbox_rotate_interval=0&incoming_reached_quota=bounce&lmtp_process_min_avail=0&lmtp_process_limit=500&lmtp_user_concurrency_limit=4&expire_trash=1&expire_trash_ttl=30&include_trash_in_quota=1'

# EXIM
curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/scripts2/saveeximtweaks" --cookie $COOKIE_FILE --data 'in_tab=1&module=Mail&find=&___original_acl_deny_spam_score_over_int=&___undef_original_acl_deny_spam_score_over_int=1&acl_deny_spam_score_over_int_control=undef&___original_acl_dictionary_attack=1&acl_dictionary_attack=1&___original_acl_primary_hostname_bl=0&acl_primary_hostname_bl=0&___original_acl_spam_scan_secondarymx=1&acl_spam_scan_secondarymx=1&___original_acl_ratelimit=1&acl_ratelimit=1&___original_acl_ratelimit_spam_score_over_int=&___undef_original_acl_ratelimit_spam_score_over_int=1&acl_ratelimit_spam_score_over_int_control=undef&___original_acl_slow_fail_block=1&acl_slow_fail_block=1&___original_acl_requirehelo=1&acl_requirehelo=1&___original_acl_delay_unknown_hosts=1&acl_delay_unknown_hosts=1&___original_acl_dont_delay_greylisting_trusted_hosts=1&acl_dont_delay_greylisting_trusted_hosts=1&___original_acl_dont_delay_greylisting_common_mail_providers=0&acl_dont_delay_greylisting_common_mail_providers=0&___original_acl_requirehelonoforge=1&acl_requirehelonoforge=1&___original_acl_requirehelonold=0&acl_requirehelonold=0&___original_acl_requirehelosyntax=1&acl_requirehelosyntax=1&___original_acl_dkim_disable=1&acl_dkim_disable=1&___original_acl_dkim_bl=0&___original_acl_deny_rcpt_soft_limit=&___undef_original_acl_deny_rcpt_soft_limit=1&acl_deny_rcpt_soft_limit_control=undef&___original_acl_deny_rcpt_hard_limit=&___undef_original_acl_deny_rcpt_hard_limit=1&acl_deny_rcpt_hard_limit_control=undef&___original_spammer_list_ips_button=&___undef_original_spammer_list_ips_button=1&___original_sender_verify_bypass_ips_button=&___undef_original_sender_verify_bypass_ips_button=1&___original_trusted_mail_hosts_ips_button=&___undef_original_trusted_mail_hosts_ips_button=1&___original_skip_smtp_check_ips_button=&___undef_original_skip_smtp_check_ips_button=1&___original_backup_mail_hosts_button=&___undef_original_backup_mail_hosts_button=1&___original_trusted_mail_users_button=&___undef_original_trusted_mail_users_button=1&___original_blocked_domains_button=&___undef_original_blocked_domains_button=1&___original_filter_emails_by_country_button=&___undef_original_filter_emails_by_country_button=1&___original_per_domain_mailips=1&per_domain_mailips=1&___original_custom_mailhelo=0&___original_custom_mailips=0&___original_systemfilter=%2Fetc%2Fcpanel_exim_system_filter&systemfilter_control=default&___original_filter_attachments=1&filter_attachments=1&___original_filter_spam_rewrite=1&filter_spam_rewrite=1&___original_filter_fail_spam_score_over_int=&___undef_original_filter_fail_spam_score_over_int=1&filter_fail_spam_score_over_int_control=undef&___original_spam_header=***SPAM***&spam_header_control=default&___original_acl_0tracksenders=0&acl_0tracksenders=0&___original_callouts=0&callouts=0&___original_smarthost_routelist=&smarthost_routelist_control=default&___original_smarthost_autodiscover_spf_include=1&smarthost_autodiscover_spf_include=1&___original_spf_include_hosts=&spf_include_hosts_control=default&___original_rewrite_from=disable&rewrite_from=disable&___original_hiderecpfailuremessage=0&hiderecpfailuremessage=0&___original_malware_deferok=1&malware_deferok=1&___original_senderverify=1&senderverify=1&___original_setsenderheader=0&setsenderheader=0&___original_spam_deferok=1&spam_deferok=1&___original_srs=0&srs=0&___original_query_apache_for_nobody_senders=1&query_apache_for_nobody_senders=1&___original_trust_x_php_script=1&trust_x_php_script=1&___original_dsn_advertise_hosts=&___undef_original_dsn_advertise_hosts=1&dsn_advertise_hosts_control=undef&___original_smtputf8_advertise_hosts=&___undef_original_smtputf8_advertise_hosts=1&smtputf8_advertise_hosts_control=undef&___original_manage_rbls_button=&___undef_original_manage_rbls_button=1&___original_acl_spamcop_rbl=1&acl_spamcop_rbl=1&___original_acl_spamhaus_rbl=1&acl_spamhaus_rbl=1&___original_rbl_whitelist_neighbor_netblocks=1&rbl_whitelist_neighbor_netblocks=1&___original_rbl_whitelist_greylist_common_mail_providers=1&rbl_whitelist_greylist_common_mail_providers=1&___original_rbl_whitelist_greylist_trusted_netblocks=0&rbl_whitelist_greylist_trusted_netblocks=0&___original_rbl_whitelist=&rbl_whitelist=&___original_allowweakciphers=1&allowweakciphers=1&___original_require_secure_auth=0&require_secure_auth=0&___original_openssl_options=+%2Bno_sslv2+%2Bno_sslv3&openssl_options_control=other&openssl_options_other=+%2Bno_sslv2+%2Bno_sslv3&___original_tls_require_ciphers=ECDHE-ECDSA-CHACHA20-POLY1305%3AECDHE-RSA-CHACHA20-POLY1305%3AECDHE-ECDSA-AES128-GCM-SHA256%3AECDHE-RSA-AES128-GCM-SHA256%3AECDHE-ECDSA-AES256-GCM-SHA384%3AECDHE-RSA-AES256-GCM-SHA384%3ADHE-RSA-AES128-GCM-SHA256%3ADHE-RSA-AES256-GCM-SHA384%3AECDHE-ECDSA-AES128-SHA256%3AECDHE-RSA-AES128-SHA256%3AECDHE-ECDSA-AES128-SHA%3AECDHE-RSA-AES256-SHA384%3AECDHE-RSA-AES128-SHA%3AECDHE-ECDSA-AES256-SHA384%3AECDHE-ECDSA-AES256-SHA%3AECDHE-RSA-AES256-SHA%3ADHE-RSA-AES128-SHA256%3ADHE-RSA-AES128-SHA%3ADHE-RSA-AES256-SHA256%3ADHE-RSA-AES256-SHA%3AECDHE-ECDSA-DES-CBC3-SHA%3AECDHE-RSA-DES-CBC3-SHA%3AEDH-RSA-DES-CBC3-SHA%3AAES128-GCM-SHA256%3AAES256-GCM-SHA384%3AAES128-SHA256%3AAES256-SHA256%3AAES128-SHA%3AAES256-SHA%3ADES-CBC3-SHA%3A%21DSS&tls_require_ciphers_control=other&tls_require_ciphers_other=ECDHE-ECDSA-CHACHA20-POLY1305%3AECDHE-RSA-CHACHA20-POLY1305%3AECDHE-ECDSA-AES128-GCM-SHA256%3AECDHE-RSA-AES128-GCM-SHA256%3AECDHE-ECDSA-AES256-GCM-SHA384%3AECDHE-RSA-AES256-GCM-SHA384%3ADHE-RSA-AES128-GCM-SHA256%3ADHE-RSA-AES256-GCM-SHA384%3AECDHE-ECDSA-AES128-SHA256%3AECDHE-RSA-AES128-SHA256%3AECDHE-ECDSA-AES128-SHA%3AECDHE-RSA-AES256-SHA384%3AECDHE-RSA-AES128-SHA%3AECDHE-ECDSA-AES256-SHA384%3AECDHE-ECDSA-AES256-SHA%3AECDHE-RSA-AES256-SHA%3ADHE-RSA-AES128-SHA256%3ADHE-RSA-AES128-SHA%3ADHE-RSA-AES256-SHA256%3ADHE-RSA-AES256-SHA%3AECDHE-ECDSA-DES-CBC3-SHA%3AECDHE-RSA-DES-CBC3-SHA%3AEDH-RSA-DES-CBC3-SHA%3AAES128-GCM-SHA256%3AAES256-GCM-SHA384%3AAES128-SHA256%3AAES256-SHA256%3AAES128-SHA%3AAES256-SHA%3ADES-CBC3-SHA%3A%21DSS&___original_globalspamassassin=0&globalspamassassin=0&___original_max_spam_scan_size=1000&max_spam_scan_size_control=default&___original_acl_outgoing_spam_scan=0&acl_outgoing_spam_scan=0&___original_acl_outgoing_spam_scan_over_int=&___undef_original_acl_outgoing_spam_scan_over_int=1&acl_outgoing_spam_scan_over_int_control=undef&___original_no_forward_outbound_spam=0&no_forward_outbound_spam=0&___original_no_forward_outbound_spam_over_int=&___undef_original_no_forward_outbound_spam_over_int=1&no_forward_outbound_spam_over_int_control=undef&___original_spamassassin_plugin_BAYES_POISON_DEFENSE=1&spamassassin_plugin_BAYES_POISON_DEFENSE=1&___original_spamassassin_plugin_P0f=1&spamassassin_plugin_P0f=1&___original_spamassassin_plugin_KAM=1&spamassassin_plugin_KAM=1&___original_spamassassin_plugin_CPANEL=1&spamassassin_plugin_CPANEL=1'

# ACTIVAR BIND EN VEZ DE POWERDNS
/scripts/setupnameserver bind --force

# REMOVE COOKIE
rm -f $CWD/wpwhmcookie.txt

echo "Configurando exim..."
sed -i 's/^acl_spamhaus_rbl=.*/acl_spamhaus_rbl=1/' /etc/exim.conf.localopts
sed -i 's/^acl_spamcop_rbl=.*/acl_spamcop_rbl=1/' /etc/exim.conf.localopts
sed -i 's/^require_secure_auth=.*/require_secure_auth=0/' /etc/exim.conf.localopts
sed -i 's/^acl_spamcop_rbl=.*/acl_spamcop_rbl=1/' /etc/exim.conf.localopts
sed -i 's/^allowweakciphers=.*/allowweakciphers=1/' /etc/exim.conf.localopts
sed -i 's/^per_domain_mailips=.*/per_domain_mailips=1/' /etc/exim.conf.localopts # AL PARECER TIENE UN BUG, SE CONFIGURA CON LLAMADA CURL
sed -i 's/^max_spam_scan_size=.*/max_spam_scan_size=1000/' /etc/exim.conf.localopts
sed -i 's/^openssl_options=.*/openssl_options= +no_sslv2 +no_sslv3/' /etc/exim.conf.localopts
sed -i 's/^tls_require_ciphers=.*/tls_require_ciphers=ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS/' /etc/exim.conf.localopts
sed -i 's/^message_linelength_limit=.*/message_linelength_limit=4096/' /etc/exim.conf.localopts # https://support.cpanel.net/hc/en-us/articles/4420121088919-Exim-4-95-message-has-lines-too-long-for-transport-Error

# LIMITE DE ATTACHMENTS (SE PONE 40M PARA TENER UN LIMITE DE 25M POR BUG https://support.cpanel.net/hc/en-us/articles/360052199934--SMTP-Error-Message-exceeds-server-limit-when-email-attachment-is-smaller-than-limit)
sed -i '/^message_size_limit.*/d' /etc/exim.conf.local
if grep "@CONFIG@" /etc/exim.conf.local > /dev/null; then
        sed -i '/@CONFIG@/ a message_size_limit = 40M' /etc/exim.conf.local
else
        echo "@CONFIG@" >> /etc/exim.conf.local
        echo "" >> /etc/exim.conf.local
        sed -i '/@CONFIG@/ a message_size_limit = 40M' /etc/exim.conf.local
fi

/usr/local/cpanel/libexec/tailwatchd --disable=Cpanel::TailWatch::RecentAuthedMailIpTracker

/scripts/buildeximconf

echo "Instalando paquetes PHP EasyApache 4..."
if grep -i "Almalinux" /etc/redhat-release > /dev/null; then
        # https://support.cpanel.net/hc/en-us/articles/14191689268375-How-to-Install-the-Sodium-Cryptographic-Library-libsodium-and-PHP-Extension-on-AlmaLinux-8-and-CloudLinux-8
        dnf install libsodium libsodium-devel -y
else # CENTOS 7
        # https://support.cpanel.net/hc/en-us/articles/360056786594-How-to-Install-the-Sodium-Cryptographic-Library-libsodium-and-PHP-Extension-on-CentOS-7-and-CloudLinux-7
        yum install epel-release -y
        yum install libsodium libsodium-devel -y
fi

yum install -y \
ea-apache24-mod_proxy_fcgi \
libcurl-devel \
openssl-devel \
unixODBC \
ea-apache24-mod_version \
ea-apache24-mod_env \
ea-php73 \
ea-php73-pear \
ea-php73-php-cli \
ea-php73-php-common \
ea-php73-php-curl \
ea-php73-php-devel \
ea-php73-php-exif \
ea-php73-php-fileinfo \
ea-php73-php-ftp \
ea-php73-php-gd \
ea-php73-php-iconv \
ea-php73-php-intl \
ea-php73-php-litespeed \
ea-php73-php-mbstring \
ea-php73-php-mysqlnd \
ea-php73-php-opcache \
ea-php73-php-pdo \
ea-php73-php-posix \
ea-php73-php-soap \
ea-php73-php-zip \
ea-php73-runtime \
ea-php73-php-bcmath \
ea-php73-php-ioncube10 \
ea-php73-php-xmlrpc \
ea-php73-php-gettext \
ea-php73-php-gmp \
ea-php73-php-xml \
ea-php73-php-imap \
ea-php73-php-calendar \
ea-php74 \
ea-php74-pear \
ea-php74-php-cli \
ea-php74-php-common \
ea-php74-php-curl \
ea-php74-php-devel \
ea-php74-php-exif \
ea-php74-php-fileinfo \
ea-php74-php-ftp \
ea-php74-php-gd \
ea-php74-php-iconv \
ea-php74-php-intl \
ea-php74-php-litespeed \
ea-php74-php-mbstring \
ea-php74-php-mysqlnd \
ea-php74-php-opcache \
ea-php74-php-pdo \
ea-php74-php-posix \
ea-php74-php-soap \
ea-php74-php-zip \
ea-php74-runtime \
ea-php74-php-bcmath \
ea-php74-php-ioncube10 \
ea-php74-php-xmlrpc \
ea-php74-php-gettext \
ea-php74-php-gmp \
ea-php74-php-xml \
ea-php74-php-imap \
ea-php74-php-sodium \
ea-php74-php-calendar \
ea-php80 \
ea-php80-pear \
ea-php80-php-cli \
ea-php80-php-common \
ea-php80-php-curl \
ea-php80-php-devel \
ea-php80-php-exif \
ea-php80-php-fileinfo \
ea-php80-php-ftp \
ea-php80-php-gd \
ea-php80-php-iconv \
ea-php80-php-intl \
ea-php80-php-litespeed \
ea-php80-php-mbstring \
ea-php80-php-mysqlnd \
ea-php80-php-opcache \
ea-php80-php-pdo \
ea-php80-php-posix \
ea-php80-php-soap \
ea-php80-php-zip \
ea-php80-runtime \
ea-php80-php-bcmath \
ea-php80-php-gettext \
ea-php80-php-gmp \
ea-php80-php-xml \
ea-php80-php-imap \
ea-php80-php-sodium \
ea-php80-php-calendar \
ea-php81 \
ea-php81-pear \
ea-php81-php-cli \
ea-php81-php-common \
ea-php81-php-curl \
ea-php81-php-devel \
ea-php81-php-exif \
ea-php81-php-fileinfo \
ea-php81-php-ftp \
ea-php81-php-gd \
ea-php81-php-iconv \
ea-php81-php-intl \
ea-php81-php-litespeed \
ea-php81-php-mbstring \
ea-php81-php-mysqlnd \
ea-php81-php-opcache \
ea-php81-php-pdo \
ea-php81-php-posix \
ea-php81-php-soap \
ea-php81-php-zip \
ea-php81-runtime \
ea-php81-php-bcmath \
ea-php81-php-gettext \
ea-php81-php-gmp \
ea-php81-php-xml \
ea-php81-php-imap \
ea-php81-php-sodium \
ea-php81-php-ioncube12 \
ea-php81-php-calendar \
ea-php82 \
ea-php82-pear \
ea-php82-php-cli \
ea-php82-php-common \
ea-php82-php-curl \
ea-php82-php-devel \
ea-php82-php-exif \
ea-php82-php-fileinfo \
ea-php82-php-ftp \
ea-php82-php-gd \
ea-php82-php-iconv \
ea-php82-php-intl \
ea-php82-php-litespeed \
ea-php82-php-mbstring \
ea-php82-php-mysqlnd \
ea-php82-php-opcache \
ea-php82-php-pdo \
ea-php82-php-posix \
ea-php82-php-soap \
ea-php82-php-zip \
ea-php82-runtime \
ea-php82-php-bcmath \
ea-php82-php-gettext \
ea-php82-php-gmp \
ea-php82-php-xml \
ea-php82-php-imap \
ea-php82-php-sodium \
ea-php82-php-ioncube13 \
ea-php82-php-calendar \
ea-php83 \
ea-php83-pear \
ea-php83-php-cli \
ea-php83-php-common \
ea-php83-php-curl \
ea-php83-php-devel \
ea-php83-php-exif \
ea-php83-php-fileinfo \
ea-php83-php-ftp \
ea-php83-php-gd \
ea-php83-php-iconv \
ea-php83-php-intl \
ea-php83-php-litespeed \
ea-php83-php-mbstring \
ea-php83-php-mysqlnd \
ea-php83-php-opcache \
ea-php83-php-pdo \
ea-php83-php-posix \
ea-php83-php-soap \
ea-php83-php-zip \
ea-php83-runtime \
ea-php83-php-bcmath \
ea-php83-php-gettext \
ea-php83-php-gmp \
ea-php83-php-xml \
ea-php83-php-imap \
ea-php83-php-sodium \
ea-php83-php-ioncube14 \
ea-php83-php-calendar \
--skip-broken

echo "Configurando PHP EasyApache 4..."
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^memory_limit.*/memory_limit = 1024M/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^enable_dl.*/enable_dl = Off/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^expose_php.*/expose_php = Off/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^disable_functions.*/disable_functions = apache_get_modules,apache_get_version,apache_getenv,apache_note,apache_setenv,disk_free_space,diskfreespace,dl,exec,highlight_file,ini_alter,ini_restore,openlog,passthru,phpinfo,popen,posix_getpwuid,proc_close,proc_get_status,proc_nice,proc_open,proc_terminate,shell_exec,show_source,symlink,system,eval,debug_zval_dump/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^upload_max_filesize.*/upload_max_filesize = 16M/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^post_max_size.*/post_max_size = 16M/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^date.timezone.*/date.timezone = "America\/Argentina\/Buenos_Aires"/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^allow_url_fopen.*/allow_url_fopen = On/g'

find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^max_execution_time.*/max_execution_time = 120/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^max_input_time.*/max_input_time = 120/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^max_input_vars.*/max_input_vars = 2000/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^;default_charset = "UTF-8"/default_charset = "UTF-8"/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^default_charset.*/default_charset = "UTF-8"/g'

find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^display_errors.*/display_errors = On/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^error_reporting.*/error_reporting = E_ALL \& \~E_DEPRECATED \& \~E_STRICT/g'

echo "Configurando valores default PHP-FPM..." # https://documentation.cpanel.net/display/74Docs/Configuration+Values+of+PHP-FPM
mkdir -p /var/cpanel/ApachePHPFPM
cat > /var/cpanel/ApachePHPFPM/system_pool_defaults.yaml << EOF
---
pm_max_children: 20
pm_max_requests: 40
php_admin_value_disable_functions : { present_ifdefault: 0 }
EOF
/usr/local/cpanel/scripts/php_fpm_config --rebuild
/scripts/restartsrv_apache_php_fpm

echo "Configurando Handlers..."
whmapi1 php_set_handler version=ea-php73 handler=cgi
whmapi1 php_set_handler version=ea-php74 handler=cgi
whmapi1 php_set_handler version=ea-php80 handler=cgi
whmapi1 php_set_handler version=ea-php81 handler=cgi
whmapi1 php_set_handler version=ea-php82 handler=cgi
whmapi1 php_set_handler version=ea-php83 handler=cgi
whmapi1 php_set_system_default_version version=ea-php82

echo "Configurando PHP-FPM..."
whmapi1 php_set_default_accounts_to_fpm default_accounts_to_fpm=0

if [ $ISVPS = "NO" ]; then
	echo "Configurando ModSecurity..."
	URL="https%3A%2F%2Fwaf.comodo.com%2Fdoc%2Fmeta_comodo_apache.yaml"
	whmapi1 modsec_add_vendor url=$URL
                
	MODSEC_DISABLE_CONF=("00_Init_Initialization.conf" "10_Bruteforce_Bruteforce.conf" "12_HTTP_HTTPDoS.conf")
	for CONF in "${MODSEC_DISABLE_CONF[@]}"
	do
		echo "Deshabilitando conf $CONF..."
		whmapi1 modsec_make_config_inactive config=modsec_vendor_configs%2Fcomodo_apache%2F$CONF
	done
	whmapi1 modsec_enable_vendor vendor_id=comodo_apache

	function disable_rule {
	        whmapi1 modsec_disable_rule config=$2 id=$1
	        whmapi1 modsec_deploy_rule_changes config=$2
	}

	echo "Deshabilitando reglas conflictivas..."
	disable_rule 211050 modsec_vendor_configs/comodo_apache/09_Global_Other.conf
	disable_rule 214420 modsec_vendor_configs/comodo_apache/17_Outgoing_FilterPHP.conf
	disable_rule 214940 modsec_vendor_configs/comodo_apache/22_Outgoing_FiltersEnd.conf
	disable_rule 222390 modsec_vendor_configs/comodo_apache/26_Apps_Joomla.conf
	disable_rule 211540 modsec_vendor_configs/comodo_apache/24_SQL_SQLi.conf
	disable_rule 210730 modsec_vendor_configs/comodo_apache/11_HTTP_HTTP.conf
	disable_rule 221570 modsec_vendor_configs/comodo_apache/32_Apps_OtherApps.conf
	disable_rule 212900 modsec_vendor_configs/comodo_apache/08_XSS_XSS.conf
	disable_rule 212000 modsec_vendor_configs/comodo_apache/08_XSS_XSS.conf
	disable_rule 212620 modsec_vendor_configs/comodo_apache/08_XSS_XSS.conf
	disable_rule 212700 modsec_vendor_configs/comodo_apache/08_XSS_XSS.conf
	disable_rule 212740 modsec_vendor_configs/comodo_apache/08_XSS_XSS.conf
	disable_rule 212870 modsec_vendor_configs/comodo_apache/08_XSS_XSS.conf
	disable_rule 212890 modsec_vendor_configs/comodo_apache/08_XSS_XSS.conf
	disable_rule 212640 modsec_vendor_configs/comodo_apache/08_XSS_XSS.conf
	disable_rule 212650 modsec_vendor_configs/comodo_apache/08_XSS_XSS.conf
	disable_rule 221560 modsec_vendor_configs/comodo_apache/32_Apps_OtherApps.conf
	disable_rule 210831 modsec_vendor_configs/comodo_apache/03_Global_Agents.conf
fi

echo "Configurando MySQL..."
# I leave cpanel to decide
whmapi1 set_tweaksetting key=mycnf_auto_adjust_maxallowedpacket value=1
whmapi1 set_tweaksetting key=mycnf_auto_adjust_openfiles_limit value=1
whmapi1 set_tweaksetting key=mycnf_auto_adjust_innodb_buffer_pool_size value=1

sed -i '/^local-infile.*/d' /etc/my.cnf
sed -i '/^sql_mode.*/d' /etc/my.cnf
sed -i '/^# WNPower pre-configured values.*/d' /etc/my.cnf

sed  -i '/\[mysqld\]/a\ ' /etc/my.cnf
sed  -i '/\[mysqld\]/a sql_mode = ALLOW_INVALID_DATES,NO_ENGINE_SUBSTITUTION' /etc/my.cnf
sed  -i '/\[mysqld\]/a local-infile=0' /etc/my.cnf
sed  -i '/\[mysqld\]/a # WNPower pre-configured values' /etc/my.cnf

/scripts/restartsrv_mysql

echo "Configurando feature disabled..."
whmapi1 update_featurelist featurelist=disabled api_shell=0 agora=0 analog=0 boxtrapper=0 traceaddy=0 modules-php-pear=0 modules-perl=0 modules-ruby=0 pgp=0 phppgadmin=0 postgres=0 ror=0 serverstatus=0 webalizer=0 clamavconnector_scan=0 lists=0 emailtrace=1

echo "Configurando feature default..."
whmapi1 update_featurelist featurelist=default modsecurity=1 zoneedit=1 emailtrace=1

echo "Creando paquete default..."
# SE CALCULA 80% DEL DISCO PARA LA CUENTA DEFAULT
QUOTA=$(df -h /home/ | tail -1 | awk '{ print $2 }' | sed 's/G//' | awk '{ print ($1 * 1000) * 0.8 }')

whmapi1 addpkg name=default featurelist=default quota=$QUOTA cgi=0 frontpage=0 language=es maxftp=20 maxsql=20 maxpop=unlimited maxlists=0 maxsub=30 maxpark=30 maxaddon=0 hasshell=1 bwlimit=unlimited MAX_EMAIL_PER_HOUR=300 MAX_DEFER_FAIL_PERCENTAGE=30

echo "Configurando hora del servidor..."

if grep -i "Almalinux" /etc/redhat-release > /dev/null; then
        echo "Instalando Chrony..."
        yum install chrony -y
        systemctl enable chronyd
else # CentOS 7
        yum install ntpdate -y
        echo "Sincronizando fecha con pool.ntp.org..."
        ntpdate 0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org 0.south-america.pool.ntp.org
fi

echo "Seteando Timezone..."
timedatectl set-timezone "America/Argentina/Buenos_Aires"

echo "Seteando fecha del BIOS..."
hwclock -r

echo "Deshabilitando cron de mlocate..."
chmod -x /etc/cron.daily/mlocate* 2>&1 > /dev/null

if [ -f /proc/user_beancounters ]; then
	echo "OpenVZ detectado, implementando parche hostname..."
	echo "/usr/bin/hostnamectl set-hostname $HOSTNAME" >> /etc/rc.d/rc.local
	echo "/bin/systemctl restart exim.service" >> /etc/rc.d/rc.local
	chmod +x /etc/rc.d/rc.local
fi

echo "Configurando AutoSSL..."
whmapi1 set_autossl_metadata_key key=clobber_externally_signed value=1
whmapi1 set_autossl_metadata_key key=notify_autossl_expiry value=0
whmapi1 set_autossl_metadata_key key=notify_autossl_expiry_coverage value=0
whmapi1 set_autossl_metadata_key key=notify_autossl_renewal value=0
whmapi1 set_autossl_metadata_key key=notify_autossl_renewal_coverage value=0
whmapi1 set_autossl_metadata_key key=notify_autossl_renewal_coverage_reduced value=0
whmapi1 set_autossl_metadata_key key=notify_autossl_renewal_uncovered_domains value=0

echo "Desactivando cPHulk..."
whmapi1 disable_cphulk

echo "Activando Header Authorization en CGI..."
sed -i '/# INICIO ACTIVAR HEADER AUTHORIZATION CGI/,/# FIN ACTIVAR HEADER AUTHORIZATION CGI/d' /etc/apache2/conf.d/includes/pre_main_global.conf

cat >> /etc/apache2/conf.d/includes/pre_main_global.conf << 'EOF'
# INICIO ACTIVAR HEADER AUTHORIZATION CGI
SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1
# FIN ACTIVAR HEADER AUTHORIZATION CGI

EOF

/scripts/restartsrv_apache

echo "Activando 2FA..."
/usr/local/cpanel/bin/whmapi1 twofactorauth_enable_policy

echo "desactivando mod_userdir (preview viejo con ~usuario)..."
sed -i 's/:.*/:/g' /var/cpanel/moddirdomains

find /var/cpanel/userdata/ -type f -exec grep -H "userdirprotect: -1" {} \; | while read LINE
do
        FILE=$(echo "$LINE" | cut -d':' -f1)
        sed -i "s/userdirprotect: -1/userdirprotect: ''/" "$FILE"
done

/scripts/rebuildhttpdconf
/scripts/restartsrv_httpd

echo "Configurando JailShell..."
echo "/etc/pki/java" >> /var/cpanel/jailshell-additional-mounts

echo "Miscelaneas..."
# NO TIENE PERMISOS DE EJECUCION PARA TODOS POR DEFAULT
chmod 755 /usr/bin/wget
chmod 755 /usr/bin/curl 

echo "Instalando PHP ImageMagick..."
yum -y install ImageMagick-devel ImageMagick-c++-devel ImageMagick-perl

for phpver in $(ls -1 /opt/cpanel/ |grep ea-php | sed 's/ea-php//g') ; do

	# Desactivo disable_functions
	sed -i 's/^disable_functions/;disable_functions/' /opt/cpanel/ea-php$phpver/root/etc/php.ini

        printf "\autodetect" | exec /opt/cpanel/ea-php$phpver/root/usr/bin/php -C \
        -d include_path=/usr/share/pear \
        -d date.timezone=UTC \
        -d output_buffering=1 \
        -d variables_order=EGPCS \
        -d safe_mode=0 \
        -d register_argc_argv="On" \
        -d disable_functions="" \
        /opt/cpanel/ea-php$phpver/root/usr/share/pear/peclcmd.php install imagick

	# REACTIVO disable_functions
        sed -i 's/^;disable_functions/disable_functions/' /opt/cpanel/ea-php$phpver/root/etc/php.ini
done

/scripts/restartsrv_httpd
/scripts/restartsrv_apache_php_fpm

echo "Desactivando Greylisting..."
whmapi1 disable_cpgreylist

echo "Desactivando Welcome Panel..."
# https://support.cpanel.net/hc/en-us/articles/1500003456602-How-to-Disable-the-Welcome-Panel-Server-Wide-for-Newly-Created-Accounts
mkdir -pv /root/cpanel3-skel/.cpanel/nvdata; echo "1" > /root/cpanel3-skel/.cpanel/nvdata/xmainwelcomedismissed

echo "Desactivando nuevo theme Glass para nuevas cuentas..."
# https://support.cpanel.net/hc/en-us/articles/1500011608461
# https://support.cpanel.net/hc/en-us/articles/4402125595415-How-to-disable-the-Glass-theme-feedback-banner-for-newly-created-accounts
mkdir -pv /root/cpanel3-skel/.cpanel/nvdata/; echo -n "1" > /root/cpanel3-skel/.cpanel/nvdata/xmainNewStyleBannerDismissed
mkdir -pv /root/cpanel3-skel/.cpanel/nvdata/; echo -n "1" > /root/cpanel3-skel/.cpanel/nvdata/xmainSwitchToPreviousBannerDismissed
whmapi1 set_default type='default' name='basic'

echo "Desactivando cPanel Analytics..."
whmapi1 participate_in_analytics enabled=0

echo "Corrigiendo RPMs de cPanel..." # A veces queda alguno corrupto
/usr/local/cpanel/scripts/check_cpanel_pkgs --fix

echo "Seteando versión default de PHP global..."
whmapi1 php_set_system_default_version version=ea-php81

# Fix bug systemd --user https://support.cpanel.net/hc/en-us/community/posts/19164685550615-Cron-Jobs-and-usr-lib-systemd-systemd-user-in-Almalinux
systemctl mask user@.service
ps axo user:30,pid,comm:100 | grep systemd | grep -v "root\|grep" | awk '{ print $2 }' | xargs kill

echo "Reescribiendo /etc/resolv.conf..."

echo "options timeout:5 attempts:2" > /etc/resolv.conf
echo "nameserver 127.0.0.1" >> /etc/resolv.conf # local
echo "nameserver 208.67.222.222" >> /etc/resolv.conf # OpenDNS
echo "nameserver 8.20.247.20" >> /etc/resolv.conf # Comodo
echo "nameserver 8.8.8.8" >> /etc/resolv.conf # Google
echo "nameserver 199.85.126.10" >> /etc/resolv.conf # Norton
echo "nameserver 8.26.56.26" >> /etc/resolv.conf # Comodo
echo "nameserver 209.244.0.3" >> /etc/resolv.conf # Level3
echo "nameserver 8.8.4.4" >> /etc/resolv.conf # Google

# Configurando network-scripts (si tiene)
#RED=$(route -n | awk '$1 == "0.0.0.0" {print $8}')
#ETHCFG="/etc/sysconfig/network-scripts/ifcfg-$RED"
#
#if [ -f $ETHCFG ]; then
#	sed -i '/^NM_CONTROLLED=.*/d' $ETHCFG; echo "NM_CONTROLLED=no" >> $ETHCFG
#	sed -i '/^ONBOOT=.*/d' $ETHCFG; echo "ONBOOT=yes" >> $ETHCFG
#fi

echo "Instalando librerías para jq..."
yum install oniguruma -y
yum install libsodium -y

echo "Instalando locales..."
dnf install glibc-all-langpacks -y

echo "Limpiando...."

rm -f /var/cpanel/nocloudlinux > /dev/null

history -c
echo "" > /root/.bash_history

echo "#### ¡Terminado!. Si vas a reiniciar hacelo en 10 minutos porque puede estar actualizando MySQL ####"
