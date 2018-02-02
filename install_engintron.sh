#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "██╗    ██╗███╗   ██╗██████╗  ██████╗ ██╗    ██╗███████╗██████╗     ██████╗ ██████╗ ███╗   ███╗"
echo "██║    ██║████╗  ██║██╔══██╗██╔═══██╗██║    ██║██╔════╝██╔══██╗   ██╔════╝██╔═══██╗████╗ ████║"
echo "██║ █╗ ██║██╔██╗ ██║██████╔╝██║   ██║██║ █╗ ██║█████╗  ██████╔╝   ██║     ██║   ██║██╔████╔██║"
echo "██║███╗██║██║╚██╗██║██╔═══╝ ██║   ██║██║███╗██║██╔══╝  ██╔══██╗   ██║     ██║   ██║██║╚██╔╝██║"
echo "╚███╔███╔╝██║ ╚████║██║     ╚██████╔╝╚███╔███╔╝███████╗██║  ██║██╗╚██████╗╚██████╔╝██║ ╚═╝ ██║"
echo "╚══╝╚══╝ ╚═╝  ╚═══╝╚═╝      ╚═════╝  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═════╝ ╚═╝     ╚═╝"

echo ""
echo "               ####################### Nginx Installer #######################              "
echo ""
echo ""

if [ ! -d /usr/local/cpanel ]; then
        echo "No se detectó cPanel, abortando."
        exit 0
fi

configure_cloudflare()
{ # CLOUDFLARE PATCH
        echo "Configurando Engintron..."

        echo "Agregando IP para CloudFlare..."
        IP_COUNT=$(whmapi1 listips | grep "public_ip:" | cut -d':' -f2 | sed 's/ //' | grep -v "^169.*" | grep -v "^10.*" | grep -v "^192.168.*" | wc -l)
        if [ "$IP_COUNT" -eq 1 ]; then
                IP=$(whmapi1 listips | grep "public_ip:" | cut -d':' -f2 | sed 's/ //' | grep -v "^169.*" | grep -v "^10.*" | grep -v "^192.168.*")
                sed -i '/^set \$PROXY_DOMAIN_OR_IP/d' /etc/nginx/custom_rules
                printf "\nset \$PROXY_DOMAIN_OR_IP \"$IP\";" >> /etc/nginx/custom_rules
        fi
}

configure_dynamic()
{
        echo "Configurando caché dinámico..."
        sed -i "s/^proxy_cache_valid.*/proxy_cache_valid\t200 30s;/" /etc/nginx/proxy_params_dynamic
}


if [ -f /usr/local/src/publicnginx/nginxinstaller ]; then
	echo "NginxCP detectado, eliminando antes..."
	/usr/local/src/publicnginx/nginxinstaller uninstall
	/script/rebuildhttpdconf
	rm -rf /usr/local/src/publicnginx*
fi

cd /; rm -f engintron.sh; wget --no-check-certificate https://raw.githubusercontent.com/engintron/engintron/master/engintron.sh; bash engintron.sh install

echo "Configurando..."
configure_cloudflare
configure_dynamic

echo "Reiniciando servicios..."
service httpd restart
service nginx restart

echo "Listo!"
