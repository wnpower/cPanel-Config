<h1>Script para configuraci&oacute;n de cPanel</h1>
<br />Este script instala y configura cPanel seg&uacute;n las buenas pr&aacute;cticas recomendadas por WNPower<br /><br />Modo de uso: wget https://raw.githubusercontent.com/wnpower/cPanel-config/master/install_cpanel.sh&nbsp;&amp;&amp; bash install_cpanel.sh<br /><br /><strong>NOTA: Instalar s&oacute;lo en CentOS 7 Minimal<br /><br /></strong>Tareas que realiza:<br />
<ul>
<li>Optimizaci&oacute;n de configuraci&oacute;n de red</li>
<li>Configura los DNS</li>
<li>Instala el paquete "Base" y otros m&aacute;s recomendados</li>
<li>Optimizaci&oacute;n de configuraci&oacute;n de SSH</li>
<li>Instala cPanel si no lo detecta</li>
<li><strong>Configura Tweak Settings con los valores recomendados</strong></li>
<li>Configura AWStats como sistema de estad&iacute;sticas</li>
<li>Deshabilita compiladores</li>
<li>Configura complejidad m&iacute;nima de passwords</li>
<li>Habilita php open_basedir protection</li>
<li>Deshabilita Shell Fork Bomb Protection (genera problemas con los l&iacute;mites en servidores con alto consumo)</li>
<li>Deshabilita SMTP Restrictions (en pos de utilizar SMTP_BLOCK de CSF)</li>
<li><strong>Configura Apache con los valores recomendados</strong></li>
<li><strong>Configura Exim con los valores recomendados</strong></li>
<li>Configura Pro-FTPd con los valores recomendados</li>
<li>Configura los features "disabled" y "default" con los valores recomendados</li>
<li><strong>Instala y configura CSF Firewall con los valores recomendados</strong></li>
<li><strong>Configura valores recomendados de MySQL</strong></li>
<li><strong>Configura todos los php.ini con los valores recomendados</strong></li>
<li>Crea el paquete "default" con los valores recomendados</li>
<li>Sincroniza la hora del servidor con un servidor NTP</li>
</ul>
