#!/bin/bash
#
# curl -sSL https://www.dropbox.com/s/vfns0bkml6w2u8r/new_server.sh?dl=0 | sudo bash
#

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Did you leave out sudo?"
	exit
fi

log_info() {
  declare desc="columnar log info2 formatter"
  echo ''
  echo '======================================================================='
  echo "   $*"
  echo '======================================================================='
}
clear;

log_info 'Installing Dependencies'

mkdir /var/www >/dev/null 2>&1
chown -R www-data:www-data /var/www

#sudo dpkg --configure -a >/dev/null 2>&1

if [ $(which nginx) ]; then
    echo "Nginx already installed";
    nginx -v
	if [ -d  "/etc/nginx/sites-enabled" ]; then
		echo "This server is running: "$(ls /etc/nginx/sites-enabled -I default) > /etc/motd
	fi
else
	log_info "Install Nginx"
	sudo apt-get install nginx -y -qq
fi


if [[ $(ufw status) == *"Status: inactive"* ]]; then
	log_info "Configure Firewall"
	ufw default deny incoming
	ufw default allow outgoing
	ufw allow 'Nginx Full'
	ufw allow ssh
	ufw --force enable
else
	echo 'Firewall already configured'
	ufw status
fi


if [ $(which php) ]; then
    echo "PHP already installed";
    PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -f1-2 -d".")
else
	#clear;
	log_info "Install PHP"
	TMP_PHP_VERSION='7.4'
	read -p "Which PHP Version [$TMP_PHP_VERSION]: " PHP_VERSION </dev/tty
	PHP_VERSION=${PHP_VERSION:-$TMP_PHP_VERSION}

	if [ "$PHP_VERSION" != "7.2" ]; then

		sudo apt-get install software-properties-common -y -qq
		sudo add-apt-repository ppa:ondrej/php -y
		sudo apt-get update -y -qq
	fi

	sudo apt-get install php${PHP_VERSION}-fpm -y -qq

	sudo apt-get install php${PHP_VERSION}-cli -y -qq
	sudo apt-get install php${PHP_VERSION}-mysql -y -qq
	sudo apt-get install php${PHP_VERSION}-gd -y -qq
	sudo apt-get install php${PHP_VERSION}-imagick -y -qq
	sudo apt-get install php${PHP_VERSION}-intl -y -qq
	sudo apt-get install php${PHP_VERSION}-tidy -y -qq
	sudo apt-get install php${PHP_VERSION}-xmlrpc -y -qq
	sudo apt-get install php${PHP_VERSION}-xml -y -qq
	sudo apt-get install php${PHP_VERSION}-bcmath -y -qq
	sudo apt-get install php${PHP_VERSION}-curl -y -qq
	sudo apt-get install php${PHP_VERSION}-zip -y -qq
	sudo apt-get install php${PHP_VERSION}-mbstring -y -qq
	sudo apt-get install php${PHP_VERSION}-imap -y -qq

	if grep -Fxq "[my-custom-config]" /etc/php/$PHP_VERSION/fpm/php.ini
	then
	    echo "skip PHP $PHP_VERSION entries for FPM";
	else
		cat <<-EOF >> /etc/php/$PHP_VERSION/fpm/php.ini
		[my-custom-config]

		upload_max_filesize = 256M
		post_max_size = 256M
		memory_limit = 256M
		max_execution_time = 600
		max_input_vars = 3000
		max_input_time = 1000
		EOF
	fi

	if grep -Fxq "[my-custom-config]" /etc/php/$PHP_VERSION/cli/php.ini
	then
	    echo "skip PHP $PHP_VERSION entries for CLI";
	else
		cat <<-EOF >> /etc/php/$PHP_VERSION/cli/php.ini
		[my-custom-config]

		upload_max_filesize = 256M
		post_max_size = 256M
		memory_limit = 256M
		max_execution_time = 600
		max_input_vars = 3000
		max_input_time = 1000
		EOF
	fi

fi

if [ $(which fail2ban-client) ]; then
    echo "Fail2Ban already installed";
    fail2ban-client ping
else
	log_info "Install Fail2Ban"
	sudo apt-get install -qq fail2ban -y
fi

if [ $(which certbot) ]; then
    echo "Certbot already installed";
    certbot --version
else
	log_info "Install Certbot"
	sudo apt-get install certbot python3-certbot-nginx -y -qq
	#sudo apt-get install certbot python-certbot-nginx -y -qq
	sudo snap install --classic certbot
fi

log_info "Install Database"


if [ $(which mariadb) ] || [ $(which mysql-server) ] || [ $(which mysql) ]; then

	 echo "Database already installed!";
else

	TMP_DB_SELECT="1"
	read -p "[1] MariaDB or [2] MySQL? [$TMP_DB_SELECT]:  " DB_SELECT </dev/tty
	DB_SELECT=${DB_SELECT:-$TMP_DB_SELECT}

	if [ "$DB_SELECT" = "1" ] ; then
		log_info "Install MariaDB"
		sudo apt-get install mariadb-server -y -qq
	    #mariadb --version
	else
		log_info "Install MySQL Database"

		wget -c wget https://dev.mysql.com/get/mysql-apt-config_0.8.15-1_all.deb
		sudo dpkg -i mysql-apt-config_*
		sudo apt-get -qq update
		sudo apt-get -qq -y upgrade
		rm mysql-apt-config_*

		sudo apt-get install -qq -y mysql-server

		echo "Configure MySQL Database"
		sudo apt-get install -qq aptitude -y

		sudo aptitude -y install expect

		SECURE_MYSQL=$(expect -c "
			set timeout 10
			spawn mysql_secure_installation
			expect \"Press y|Y for Yes, any other key for No:\"
			send \"y\r\"
			expect \"Please enter 0 = LOW, 1 = MEDIUM and 2 = STRONG:\"
			send \"1\r\"
			expect \"Remove anonymous users?\"
			send \"y\r\"
			expect \"Disallow root login remotely?\"
			send \"y\r\"
			expect \"Remove test database and access to it?\"
			send \"y\r\"
			expect \"Reload privilege tables now?\"
			send \"y\r\"
			expect eof
		")

		echo "$SECURE_MYSQL"

		aptitude -y purge expect

		sudo service mysql restart
		sudo service mysql status
	fi


fi

clear;

TMP_DOMAIN=$(cat /etc/hosts | grep '127.0.1.1' | cut -d " " -f 2)

read -p "Please enter Domain [$TMP_DOMAIN]:  " DOMAIN </dev/tty
DOMAIN=${DOMAIN:-$TMP_DOMAIN}

read -p "Please enter SubDomain [NONE]:  " SUBDOMAIN </dev/tty

if [ -z "$SUBDOMAIN" ]; then
	HOST=${DOMAIN}
else
	HOST=${SUBDOMAIN}.${DOMAIN}
fi

SITEDIR=/var/www/${HOST}
SLUG="${HOST//./_}"
HEADER=$(curl -sSLI http://$HOST)

TMP_WORDPRESS=Yes
read -p "Install WordPress [$TMP_WORDPRESS]:  " WORDPRESS </dev/tty
WORDPRESS=${WORDPRESS:-$TMP_WORDPRESS}

TMP_DB_PWD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)"#@"
TMP_DB_NAME=$SLUG
TMP_DB_USER=$SLUG

mkdir ${SITEDIR} >/dev/null 2>&1
chown -R www-data:www-data /var/www

if [ "$WORDPRESS" = "Yes" ] ; then

	if [ ! $(which wp) ]; then
		sudo apt-get -qq update
		log_info "Install WP CLI"
		curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar >/dev/null 2>&1
		chmod +x wp-cli.phar
		sudo mv wp-cli.phar /usr/local/bin/wp
	    #wp --version --allow-root
	fi

	if $(wp core is-installed --allow-root --path=${SITEDIR} >/dev/null 2>&1); then
		TMP_DB_PWD=$(wp config get DB_PASSWORD --allow-root --path=${SITEDIR})
		TMP_DB_NAME=$(wp config get DB_NAME --allow-root --path=${SITEDIR})
		TMP_DB_USER=$(wp config get DB_USER --allow-root --path=${SITEDIR})
	fi

fi

read -p "Please enter Database Name [$TMP_DB_NAME]:  " DB_NAME </dev/tty
DB_NAME=${DB_NAME:-$TMP_DB_NAME}
DB_NAME="${DB_NAME//./_}"

read -p "Please enter Database User [$TMP_DB_USER]:  " DB_USER </dev/tty
DB_USER=${DB_USER:-$TMP_DB_USER}

read -p "Please enter Database Password [$TMP_DB_PWD]:  " DB_PWD </dev/tty
DB_PWD=${DB_PWD:-$TMP_DB_PWD}


if [ -d /var/lib/mysql/$DB_NAME ]; then
    echo "Database '${DB_NAME}' already exists!";
else
	log_info "Create DB '${DB_NAME}'"
	sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

	sudo service mysql restart
fi

if [[ $(sudo mysql -u root -e "SELECT User FROM mysql.user WHERE User = '$DB_USER' AND Host = 'localhost';") ]]; then
	TMP_DEL_USER='Yes'
	read -p "User '${DB_USER}' exists! Create new one? [$TMP_DEL_USER]:  " DEL_USER </dev/tty
	DEL_USER=${DEL_USER:-$TMP_DEL_USER}
	if [ "$DEL_USER" = "Yes" ] ; then
	    echo "Drop User";
		sudo mysql -u root -e "REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${DB_USER}'@'localhost';"
		sudo mysql -u root -e "DROP USER '${DB_USER}'@'localhost';"
	fi

fi

if [[ $(sudo mysql -u root -e "SELECT User FROM mysql.user WHERE User = '$DB_USER' AND Host = 'localhost';") ]]; then
	echo ''
else
	log_info "Create User '${DB_USER}'"

	sudo mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PWD}';";
	sudo mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';";
	if [[ $(mysql -V) == *"MariaDB"* ]]; then
		#MariaDB
		sudo mysql -u root -e "UPDATE mysql.user SET authentication_string=PASSWORD('${DB_PWD}') WHERE USER='${DB_USER}' AND Host='localhost';";
	else
		# MySQL
		sudo mysql -u root -e "ALTER user '${DB_NAME}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_PWD}';"
		sudo mysql -u root -e "SET GLOBAL binlog_expire_logs_seconds = 3600;"
	fi

	sudo mysql -u root -e "PURGE BINARY LOGS BEFORE date_sub(now(), interval 1 day);";
	sudo mysql -u root -e "FLUSH PRIVILEGES;";
	sudo service mysql restart
fi

if [ "$WORDPRESS" = "Yes" ] ; then

log_info "Installing WordPress in $SITEDIR"
mkdir /var/www >/dev/null 2>&1
mkdir ${SITEDIR} >/dev/null 2>&1

wp core download --allow-root --path=${SITEDIR} >/dev/null 2>&1

if ! $(wp core is-installed --allow-root --path=${SITEDIR} >/dev/null 2>&1); then

	TMP_WP_EMAIL='xaver@everpress.co'
	read -p "Admin Email: [$TMP_WP_EMAIL]: " WP_EMAIL </dev/tty
	WP_EMAIL=${WP_EMAIL:-$TMP_WP_EMAIL}

	TMP_WP_USER='Xaver'
	read -p "Admin Username: [$TMP_WP_USER]: " WP_USER </dev/tty
	WP_USER=${WP_USER:-$TMP_WP_USER}

	TMP_WP_PWD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
	read -p "Please enter WordPress Password [$TMP_WP_PWD]:  " WP_PWD </dev/tty
	WP_PWD=${WP_PWD:-$TMP_WP_PWD}

	TMP_WP_TITLE=${HOST}
	read -p "Please enter WordPress Title [$TMP_WP_TITLE]:  " WP_TITLE </dev/tty
	WP_TITLE=${WP_TITLE:-$TMP_WP_TITLE}

	TMP_WP_CRON='Yes'
	read -p "Use Crontab for WP Crons (DISABLE_WP_CRON)? [$TMP_WP_CRON]:  " WP_CRON </dev/tty
	WP_CRON=${WP_CRON:-$TMP_WP_CRON}


	if [ "$WP_CRON" = "Yes" ] ; then
		TMP_WP_CRON_INTERVAL='1'
		read -p "Cron Interval in Minutes [$TMP_WP_CRON_INTERVAL]:  " WP_CRON_INTERVAL </dev/tty
		WP_CRON_INTERVAL=${WP_CRON_INTERVAL:-$TMP_WP_CRON_INTERVAL}
	fi

	wp config create --allow-root --dbname=${DB_NAME} --dbuser=${DB_USER} --dbpass=${DB_PWD} --force --path=${SITEDIR}
	wp core install --url=http://${HOST} --title=${HOST} --admin_user=${WP_USER} --admin_password=${WP_PWD} --admin_email=${WP_EMAIL} --skip-email --allow-root --path=${SITEDIR}
	wp theme delete twentyseventeen --allow-root --path=${SITEDIR}
	wp theme delete twentynineteen --allow-root --path=${SITEDIR}
	wp plugin delete $(wp plugin list --status=inactive --field=name --allow-root --path=${SITEDIR}) --allow-root --path=${SITEDIR}
	wp rewrite structure '/%postname%/' --allow-root --path=${SITEDIR}
	wp rewrite flush --allow-root --path=${SITEDIR}
	cd ${SITEDIR}
	rm -rf license.txt readme.html wp-config-sample.php

	if [ "$WP_CRON" = "Yes" ] ; then

		#TODO write crontab in /etc/crontab to be user specific
		wp config set DISABLE_WP_CRON true --raw --allow-root --path=${SITEDIR}
		echo -e "" >> /etc/crontab
		echo -e "# WordPress Cron" >> /etc/crontab
		echo -e "*/${WP_CRON_INTERVAL} * * * * www-data /usr/bin/php ${SITEDIR}/wp-cron.php doing_wp_cron >/dev/null 2>&1" >> /etc/crontab
	fi

else
	DB_PWD=$(wp config get DB_PASSWORD --allow-root --path=${SITEDIR})
	WP_EMAIL=$(wp user get 1 --field=email --allow-root --path=${SITEDIR})
	WP_USER=$(wp user get 1 --field=login --allow-root --path=${SITEDIR})
	WP_TITLE=$(wp option get blogname --allow-root --path=${SITEDIR})
	#sudo mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('${DB_PWD}') WHERE USER='${DB_USER}' AND Host='localhost';FLUSH PRIVILEGES;";
	#wp package browse --allow-root --path=${SITEDIR}
fi

fi


chown -R www-data:www-data /var/www

NGINXFILE=/etc/nginx/sites-available/${HOST}

if [ -f "$NGINXFILE" ]; then
    log_info "$NGINXFILE exist"
else
    log_info "$NGINXFILE does not exist"
    touch $NGINXFILE
	cat <<-EOF >> $NGINXFILE
server {
    listen 80;
    listen [::]:80;

    root ${SITEDIR};
    index index.php index.html index.htm;

    server_name ${HOST};

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt { access_log off; log_not_found off; }
    location = /apple-touch-icon.png { access_log off; log_not_found off; }
    location = /apple-touch-icon-precomposed.png { access_log off; log_not_found off; }
    location ~ /\. { deny  all; access_log off; log_not_found off; }

    location ~* ^.+\.(js|css|swf|xml|txt|ogg|ogv|svg|svgz|eot|otf|woff|woff2|mp4|ttf|rss|atom|jpg|jpeg|gif|png|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)$ {
        access_log off; log_not_found off; expires 30d;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # Add a slash at the end of request */wp-admin
    rewrite /wp-admin$ \$scheme://\$host\$uri/ permanent;

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_buffers 16 32k;
        fastcgi_buffer_size 64k;
        fastcgi_busy_buffers_size 64k;
    }

    #access_log ${SITEDIR}.access.log;
    access_log off;
    error_log ${SITEDIR}.error.log;

    #error_page 404 /404.html;
    error_page 404 /index.php?error=404;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }

    client_max_body_size 20M;

}
EOF

fi

#sudo ufw allow 'Nginx HTTP'
#sudo ufw enable
#nginx -t
#systemctl status nginx.service
if [ ! -f /etc/nginx/sites-enabled/${HOST} ]; then
	ln -s /etc/nginx/sites-available/${HOST} /etc/nginx/sites-enabled/${HOST}
fi

if [ -d  "/etc/nginx/sites-enabled" ]; then
	echo "This server is running: "$(ls /etc/nginx/sites-enabled -I default) > /etc/motd
fi

if [ $(which apache2) ]; then
    log_info "Uninstall Apache Server";
	sudo service apache2 stop
	#sudo update-rc.d apache2 disable
	sudo apt-get purge apache2 apache2-utils apache2.2-bin apache2-common -y
	sudo apt-get purge apache2 apache2-utils apache2-bin apache2.2-common -y
	sudo apt-get autoremove -y
fi

log_info "Restart NGINX service"
service nginx restart

if [ $(which postfix) ]; then
    echo "Postfix already installed";
else
	log_info "Install Postfix"
	debconf-set-selections <<< "postfix postfix/mailname string ${DOMAIN}"
	debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
	sudo apt-get install -qq postfix -y
fi


log_info "Install Lets Encrypt certificates"
if certbot certificates -d=$HOST | grep "Domains: $HOST"; then
 	echo 'Certificate already installed.'
 	sudo systemctl status certbot.timer
else
	TMP_CERTIFY=yes
	read -p "Certify $HOST? [Enter for proceed, c for cancel]:  " CERTIFY </dev/tty
	CERTIFY=${CERTIFY:-$TMP_CERTIFY}
	if [ "$CERTIFY" = "yes" ]; then
		certbot --register-unsafely-without-email --redirect --agree-tos --nginx -d=${HOST} -n
		if [ ! $(which wp) ]; then
			wp search-replace "http://${HOST}" "https://${HOST}" --allow-root --path=${SITEDIR} --precise --report-changed-only
		fi
	else
		echo 'canceled! try with:'
		echo "certbot --register-unsafely-without-email --redirect --agree-tos --nginx -d=${HOST} -n"
		echo "certbot renew --dry-run"
	fi

fi


# install client
if [ ! -f /etc/apt/sources.list.d/digitalocean-agent.list ]; then
	log_info "Installing DigitalOcean Client..."
	curl -sSL https://repos.insights.digitalocean.com/install.sh | sudo bash >/dev/null 2>&1
fi

sudo dpkg --configure -a
log_info "Update"
sudo apt-get -qq -y update
sudo apt-get -qq -y upgrade
sudo apt-get -qq -y dist-upgrade
sudo apt-get -qq -y autoremove
rm -rf /var/log/journal/*
find /var/log -type f -name "*.gz" -exec rm -f "{}" +;

#delete this message of the day:
unlink /etc/nginx/sites-enabled/digitalocean >/dev/null 2>&1
rm /etc/nginx/sites-available/digitalocean >/dev/null 2>&1

echo "sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get -y dist-upgrade && sudo apt-get -y autoremove && sudo rm -rf /var/log/journal/* && sudo rm -rf /var/cache/*"

echo ''
echo '======================================'
echo "Create site: $HOST"
echo "Database:    $DB_NAME"
echo "User:        $DB_USER"
echo "Password:    $DB_PWD"
echo "Site dir:    $SITEDIR"
echo ''
if [ "$WORDPRESS" = "Yes" ] ; then
echo "URL:         $(wp option get home --allow-root --path=${SITEDIR})"
echo "Title:       $WP_TITLE"
echo "Email:       $WP_EMAIL"
echo "User:        $WP_USER"
echo "Password:    $WP_PWD"
fi
echo '======================================'
echo ''

exit

