#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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

echo "Este script instala y pre-configura cPanel (CTRL + C para cancelar)"
sleep 10

echo "####### PRE-CONFIGURACION CPANEL ##########"
yum update -y
yum groupinstall "Base" -y
yum install screen -y
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/sysconfig/selinux
/usr/sbin/setenforce 0
iptables-save > /root/firewall.rules
systemctl stop firewalld.service
systemctl disable firewalld.service

echo "######### CONFIGURANDO DNS Y RED ########"
RED=$(route -n | awk '$1 == "0.0.0.0" {print $8}')
ETHCFG="/etc/sysconfig/network-scripts/ifcfg-$RED"

sed -i '/^PEERDNS=.*/d' $ETHCFG
sed -i '/^NM_CONTROLLED=.*/d' $ETHCFG
sed -i '/^DNS1=.*/d' $ETHCFG
sed -i '/^DNS2=.*/d' $ETHCFG
	
echo "Configurando red..."
echo "PEERDNS=no" >> $ETHCFG
echo "NM_CONTROLLED=no" >> $ETHCFG
echo "DNS1=127.0.0.1" >> $ETHCFG
echo "DNS2=8.8.8.8" >> $ETHCFG

systemctl stop NetworkManager.service
systemctl disable NetworkManager.service

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
echo "######### FIN CONFIGURANDO DNS Y RED ########"


echo "######### CONFIGURANDO SSH ########"
sed -i 's/^X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/#UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
echo "######### FIN CONFIGURANDO SSH ########"

echo "####### INSTALANDO CPANEL #######"
if [ -d /usr/local/cpanel ]; then
        echo "cPanel ya detectado, no se instala, sólo se configura (CTRL + C para cancelar)"
        sleep 10
else
        cd /home && curl -o latest -L https://securedownloads.cpanel.net/latest && sh latest
fi
echo "####### FIN INSTALANDO CPANEL #######"

echo "####### CONFIGURANDO CSF #######"
if [ ! -d /etc/csf ]; then
        echo "csf no detectado, descargando!"
	touch /etc/sysconfig/iptables
	touch /etc/sysconfig/iptables6
	systemctl start iptables
	systemctl start ip6tables
	systemctl enable iptables
	systemctl enable ip6tables
	cd /root && rm -f ./csf.tgz; wget https://download.configserver.com/csf.tgz && tar xvfz ./csf.tgz && cd ./csf && sh ./install.sh
fi

echo " Configurando CSF..."
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
sed -i 's/^PS_LIMIT = .*/PS_LIMIT = "20"/g' /etc/csf/csf.conf

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

echo "Habilitando listas negras..."
sed -i '/^#SPAMDROP/s/^#//' /etc/csf/csf.blocklists
sed -i '/^#SPAMEDROP/s/^#//' /etc/csf/csf.blocklists
sed -i '/^#DSHIELD/s/^#//' /etc/csf/csf.blocklists
sed -i '/^#HONEYPOT/s/^#//' /etc/csf/csf.blocklists
sed -i '/^#MAXMIND/s/^#//' /etc/csf/csf.blocklists
sed -i '/^#BDE|/s/^#//' /etc/csf/csf.blocklists

sed -i '/^SPAMDROP/s/|0|/|300|/' /etc/csf/csf.blocklists
sed -i '/^SPAMEDROP/s/|0|/|300|/' /etc/csf/csf.blocklists
sed -i '/^DSHIELD/s/|0|/|300|/' /etc/csf/csf.blocklists
sed -i '/^HONEYPOT/s/|0|/|300|/' /etc/csf/csf.blocklists
sed -i '/^MAXMIND/s/|0|/|300|/' /etc/csf/csf.blocklists
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

csf -r
service lfd restart

echo "####### FIN CONFIGURANDO CSF #######"
echo "####### CONFIGURANDO CPANEL #######"

if [ ! -d /usr/local/cpanel ]; then
	echo "cPanel no detectado. Abortando."
	exit 0
fi

HOSTNAME_LONG=$(hostname -d)

echo "Bajando TTL de DNS a 1 Hora..."
sed -i 's/TTL 14400/TTL 3600/' /etc/wwwacct.conf

echo "Cambiando mail de contacto..."
sed -i '/^CONTACTEMAIL\ .*/d' /etc/wwwacct.conf
echo "CONTACTEMAIL hostmaster@$HOSTNAME_LONG" >> /etc/wwwacct.conf

echo "Cambiando default DNSs..."
sed -i '/^NS\ .*/d' /etc/wwwacct.conf
sed -i '/^NS2\ .*/d' /etc/wwwacct.conf
sed -i '/^NS3\ .*/d' /etc/wwwacct.conf
echo "NS ns1.$HOSTNAME_LONG" >> /etc/wwwacct.conf
echo "NS2 ns2.$HOSTNAME_LONG" >> /etc/wwwacct.conf

echo "Subiendo conexiones FTP por IP..."
sed -i 's/MaxClientsPerIP: 8/MaxClientsPerIP: 30/' /var/cpanel/conf/pureftpd/main
sed -i "s/RootPassLogins:.*/RootPassLogins: 'no'/" /var/cpanel/conf/pureftpd/main
sed -i 's/MaxClientsPerIP 8/MaxClientsPerIP 30/' /etc/pure-ftpd.conf
service pure-ftpd restart

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
curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/scripts2/saveglobalapachesetup" --cookie $CWD/wpwhmcookie.txt --data 'module=Apache&find=&___original_sslciphersuite=ECDHE-ECDSA-AES256-GCM-SHA384%3AECDHE-RSA-AES256-GCM-SHA384%3AECDHE-ECDSA-CHACHA20-POLY1305%3AECDHE-RSA-CHACHA20-POLY1305%3AECDHE-ECDSA-AES128-GCM-SHA256%3AECDHE-RSA-AES128-GCM-SHA256%3AECDHE-ECDSA-AES256-SHA384%3AECDHE-RSA-AES256-SHA384%3AECDHE-ECDSA-AES128-SHA256%3AECDHE-RSA-AES128-SHA256&sslciphersuite_control=default&___original_sslprotocol=TLSv1.2&sslprotocol_control=default&___original_loglevel=warn&loglevel=warn&___original_traceenable=Off&traceenable=Off&___original_serversignature=Off&serversignature=Off&___original_servertokens=ProductOnly&servertokens=ProductOnly&___original_fileetag=None&fileetag=None&___original_root_options=&root_options=FollowSymLinks&root_options=IncludesNOEXEC&root_options=SymLinksIfOwnerMatch&___original_startservers=5&startservers_control=default&___original_minspareservers=5&minspareservers_control=default&___original_maxspareservers=10&maxspareservers_control=default&___original_optimize_htaccess=search_homedir_below&optimize_htaccess=search_homedir_below&___original_serverlimit=256&serverlimit_control=default&___original_maxclients=150&maxclients_control=other&maxclients_other=100&___original_maxrequestsperchild=10000&maxrequestsperchild_control=default&___original_keepalive=On&keepalive=1&___original_keepalivetimeout=5&keepalivetimeout_control=default&___original_maxkeepaliverequests=100&maxkeepaliverequests_control=default&___original_timeout=300&timeout_control=default&___original_symlink_protect=Off&symlink_protect=0&its_for_real=1' > /dev/null

/scripts/rebuildhttpdconf

curl -sk "https://127.0.0.1:2087/$SESS_TOKEN/scripts2/save_apache_mem_limits" --cookie $CWD/wpwhmcookie.txt --data 'newRLimitMem=enabled&newRLimitMemValue=1024&restart_apache=on&btnSave=1' > /dev/null

service httpd restart

# REMOVE COOKIE
rm -f $CWD/wpwhmcookie.txt

echo "Configurando exim..."
sed -i 's/^acl_spamhaus_rbl=.*/acl_spamhaus_rbl=1/' /etc/exim.conf.localopts
sed -i 's/^acl_spamcop_rbl=.*/acl_spamcop_rbl=1/' /etc/exim.conf.localopts
sed -i 's/^require_secure_auth=.*/require_secure_auth=0/' /etc/exim.conf.localopts
sed -i 's/^acl_spamcop_rbl=.*/acl_spamcop_rbl=1/' /etc/exim.conf.localopts
sed -i 's/^allowweakciphers=.*/allowweakciphers=1/' /etc/exim.conf.localopts
sed -i 's/^per_domain_mailips=.*/per_domain_mailips=1/' /etc/exim.conf.localopts
/scripts/buildeximconf

echo "Deshabilitando Eximstats..."
/usr/local/cpanel/libexec/tailwatchd --disable=Cpanel::TailWatch::Eximstats

service exim restart

echo "Instalando paquetes PHP EasyApache 4..."
yum install -y ea-php55-php-curl ea-php55-php-fileinfo ea-php55-php-fpm ea-php55-php-gd ea-php55-php-iconv ea-php55-php-ioncube ea-php55-php-intl ea-php55-php-mbstring ea-php55-php-mcrypt ea-php55-php-pdo ea-php55-php-soap ea-php55-php-xmlrpc ea-php55-php-zip ea-php56-php-curl ea-php56-php-fileinfo ea-php56-php-fpm ea-php56-php-gd ea-php56-php-iconv ea-php56-php-ioncube ea-php56-php-intl ea-php56-php-mbstring ea-php56-php-mcrypt ea-php56-php-pdo ea-php56-php-soap ea-php56-php-xmlrpc ea-php56-php-zip ea-php56-php-opcache ea-php70-php-curl ea-php70-php-fileinfo ea-php70-php-fpm ea-php70-php-gd ea-php70-php-iconv ea-php70-php-intl ea-php70-php-mbstring ea-php70-php-mcrypt ea-php70-php-pdo ea-php70-php-soap ea-php70-php-xmlrpc ea-php70-php-zip ea-php70-php-ioncube6 ea-php70-php-opcache ea-php55-php-mysqlnd ea-php56-php-mysqlnd ea-php70-php-mysqlnd ea-apache24-mod_proxy_fcgi ea-php55-php-fpm ea-php56-php-fpm ea-php70-php-fpm libcurl-devel openssl-devel ea-php71 ea-php71-pear ea-php71-php-cli ea-php71-php-common ea-php71-php-curl ea-php71-php-devel ea-php71-php-exif ea-php71-php-fileinfo ea-php71-php-fpm ea-php71-php-ftp ea-php71-php-gd ea-php71-php-iconv ea-php71-php-intl ea-php71-php-litespeed ea-php71-php-mbstring ea-php71-php-mcrypt ea-php71-php-mysqlnd ea-php71-php-odbc ea-php71-php-opcache ea-php71-php-pdo ea-php71-php-posix ea-php71-php-soap ea-php71-php-xml ea-php71-php-zip ea-php71-runtime ea-php72 ea-php72-pear ea-php72-php-cli ea-php72-php-common ea-php72-php-curl ea-php72-php-devel ea-php72-php-exif ea-php72-php-fileinfo ea-php72-php-fpm ea-php72-php-ftp ea-php72-php-gd ea-php72-php-iconv ea-php72-php-intl ea-php72-php-litespeed ea-php72-php-mbstring ea-php72-php-mysqlnd ea-php72-php-opcache ea-php72-php-pdo ea-php72-php-posix ea-php72-php-soap ea-php72-php-xml ea-php72-php-zip ea-php72-runtime unixODBC --skip-broken

echo "Configurando PHP EasyApache 4..."
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^memory_limit.*/memory_limit = 1024M/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^enable_dl.*/enable_dl = off/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^expose_php.*/expose_php = off/g'
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

find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^display_errors.*/display_errors = "On"/g'
find /opt/ \( -name "php.ini" -o -name "local.ini" \) | xargs sed -i 's/^error_reporting.*/error_reporting = "E_ALL \& \~E_DEPRECATED \& \~E_STRICT"/g'


echo "Configurando valores default PHP-FPM..."
mkdir -p /var/cpanel/ApachePHPFPM
grep "pm_max_requests" /var/cpanel/ApachePHPFPM/system_pool_defaults.yaml > /dev/null 2>&1 || echo "pm_max_requests: 40" >> /var/cpanel/ApachePHPFPM/system_pool_defaults.yaml

echo "Configurando Handlers..."
whmapi1 php_set_handler version=ea-php55 handler=cgi
whmapi1 php_set_handler version=ea-php56 handler=cgi
whmapi1 php_set_handler version=ea-php70 handler=cgi
whmapi1 php_set_handler version=ea-php71 handler=cgi
whmapi1 php_set_handler version=ea-php72 handler=cgi
whmapi1 php_set_system_default_version version=ea-php70

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

echo "Configurando MySQL..."
sed -i '/^local-infile.*/d' /etc/my.cnf
sed -i '/^query_cache_type.*/d' /etc/my.cnf
sed -i '/^query_cache_size.*/d' /etc/my.cnf
sed -i '/^join_buffer_size.*/d' /etc/my.cnf
sed -i '/^tmp_table_size.*/d' /etc/my.cnf
sed -i '/^max_heap_table_size.*/d' /etc/my.cnf
sed -i '/^# WNPower pre-configured values.*/d' /etc/my.cnf

sed  -i '/\[mysqld\]/a\ ' /etc/my.cnf
sed  -i '/\[mysqld\]/a local-infile=0' /etc/my.cnf
sed  -i '/\[mysqld\]/a query_cache_type=1' /etc/my.cnf
sed  -i '/\[mysqld\]/a query_cache_size=12M' /etc/my.cnf
sed  -i '/\[mysqld\]/a join_buffer_size=12M' /etc/my.cnf
sed  -i '/\[mysqld\]/a tmp_table_size=192M' /etc/my.cnf
sed  -i '/\[mysqld\]/a max_heap_table_size=256M' /etc/my.cnf
sed  -i '/\[mysqld\]/a # WNPower pre-configured values' /etc/my.cnf

service mysql restart

echo "Configurando feature disabled..."
whmapi1 update_featurelist featurelist=disabled api_shell=0 agora=0 analog=0 boxtrapper=0 enduserlve=0 traceaddy=0 emailtrace=0 modules-php-pear=0 modules-perl=0 modules-ruby=0 pgp=0 phppgadmin=0 postgres=0 ror=0 ssh=0 serverstatus=0 webalizer=0 clamavconnector_scan=0
echo "Configurando feature default..."
whmapi1 update_featurelist featurelist=default modsecurity=1 zoneedit=1
echo "Creando paquete default..."
whmapi1 addpkg name=default featurelist=default quota=unlimited cgi=0 frontpage=0 language=es maxftp=20 maxsql=20 maxpop=unlimited maxlists=0 maxsub=30 maxpark=30 maxaddon=0 hasshell=0 bwlimit=unlimited MAX_EMAIL_PER_HOUR=300 MAX_DEFER_FAIL_PERCENTAGE=30

echo "Configurando hora del servidor..."
yum install ntpdate -y
echo "Sincronizando fecha con pool.ntp.org..."
ntpdate 0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org 0.south-america.pool.ntp.org
if [ -f /usr/share/zoneinfo/America/Buenos_Aires ]; then
        echo "Seteando timezone a America/Buenos_Aires..."
        mv /etc/localtime /etc/localtime.old
        ln -s /usr/share/zoneinfo/America/Buenos_Aires /etc/localtime
fi
echo "Seteando fecha del BIOS..."
hwclock -r

history -c
echo "" > /root/.bash_history

echo "Terminado!"
