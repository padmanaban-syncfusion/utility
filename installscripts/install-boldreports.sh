#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.
#

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Use in the the functions: eval $invocation
invocation='say_verbose "Calling: ${yellow:-}${FUNCNAME[0]} ${green:-}$*${normal:-}"'

# standard output may be used as a return value in the functions
# we need a way to write text on the screen in the functions so that
# it won't interfere with the return value.
# Exposing stream 3 as a pipe to standard output of the script itself
exec 3>&1

verbose=true
args=("$@")
install_dir="/var/www/bold-services"
backup_folder="/var/www"
dotnet_dir="$install_dir/dotnet"
services_dir="$install_dir/services"
system_dir="/etc/systemd/system"
boldreports_product_json_location="$install_dir/application/app_data/configuration/product.json"
nginx_config_file_location="/etc/nginx/sites-available/boldreports-nginx-config"
user=""
host_url=""
can_configure_nginx=false
declare -A separated_services=( ["viewer"]="reporting\/viewer" ["etl"]="etlservice" )
services_array=("bold-id-web" "bold-id-api" "bold-ums-web" "bold-reports-web" "bold-reports-api" "bold-reports-jobs" "bold-reports-service" "bold-reports-viewer" "bold-etl")
installation_type=""
app_data_location="$install_dir/application/app_data"
puppeteer_location="$app_data_location/reporting/exporthelpers/puppeteer"

while [ $# -ne 0 ]
do
    name="$1"
    case "$name" in
        -d|--install-dir|-[Ii]nstall[Dd]ir)
            shift
            install_dir="$1"
            ;;
			
		-i|--install|-[Ii]nstall)
            shift
            installation_type="$1"
            ;;
			
		-u|--user|-User)
            shift
            user="$1"
            ;;
			
		-h|--host|-[Hh]ost)
            shift
            host_url="$1"
            ;;
        
		-n|--nginx|-[Nn]ginx)
            shift
            can_configure_nginx="$1"
            ;;
		
        -?|--?|--help|-[Hh]elp)
            script_name="$(basename "$0")"
            echo "Bold Reports Installer"
            echo "Usage: $script_name [-u|--user <USER>]"
            echo "       $script_name |-?|--help"
            echo ""
            exit 0
            ;;
        *)
            say_err "Unknown argument \`$name\`"
            exit 1
            ;;
    esac

    shift
done

# Setup some colors to use. These need to work in fairly limited shells, like the Ubuntu Docker container where there are only 8 colors.
# See if stdout is a terminal
if [ -t 1 ] && command -v tput > /dev/null; then
    # see if it supports colors
    ncolors=$(tput colors)
    if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
        bold="$(tput bold       || echo)"
        normal="$(tput sgr0     || echo)"
        black="$(tput setaf 0   || echo)"
        red="$(tput setaf 1     || echo)"
        green="$(tput setaf 2   || echo)"
        yellow="$(tput setaf 3  || echo)"
        blue="$(tput setaf 4    || echo)"
        magenta="$(tput setaf 5 || echo)"
        cyan="$(tput setaf 6    || echo)"
        white="$(tput setaf 7   || echo)"
    fi
fi

say_warning() {
    printf "%b\n" "${yellow:-}boldreports_install: Warning: $1${normal:-}" >&3
}

say_err() {
    printf "%b\n" "${red:-}boldreports_install: Error: $1${normal:-}" >&2
}

say() {
    # using stream 3 (defined in the beginning) to not interfere with stdout of functions
    # which may be used as return value
    printf "%b\n" "${cyan:-}boldreports-install:${normal:-} $1" >&3
}

say_verbose() {
    if [ "$verbose" = true ]; then
        say "$1"
    fi
}

machine_has() {
    eval $invocation

    hash "$1" > /dev/null 2>&1
    return $?
}

check_min_reqs() {
    # local hasMinimum=false
    # if machine_has "curl"; then
        # hasMinimum=true
    # elif machine_has "wget"; then
        # hasMinimum=true
    # fi

    # if [ "$hasMinimum" = "false" ]; then
        # say_err "curl or wget are required to download Bold BI. Install missing prerequisite to proceed."
        # return 1
    # fi
	
	local hasZip=false
	if machine_has "zip"; then
        hasZip=true
    fi
	
	if [ "$hasZip" = "false" ]; then
        say_err "Zip is required to extract the Bold Reports Linux package. Install missing prerequisite to proceed."
        return 1
    fi
	
	if ! machine_has "python3"; then
	    say_err "python3 is required for installing Bold Reports. Install the missing prerequisite to proceed."
	    return 1
	fi
 
	if ! machine_has "pip" && ! machine_has "pip3"; then
	    say_err "python3-pip is required for installing Bold Reports. Install the missing prerequisite to proceed."
	    return 1
	fi
	
	local hasNginx=false
	if machine_has "nginx"; then
        hasNginx=true
    fi
	
	if [ "$hasNginx" = "false" ]; then
        say_err "Nginx is required to host the Bold Reports application. Install missing prerequisite to proceed."
        return 1
    fi
	
    return 0
}

# args:
# input - $1
to_lowercase() {
    #eval $invocation

    echo "$1" | tr '[:upper:]' '[:lower:]'
    return 0
}

# args:
# input - $1
remove_trailing_slash() {
    #eval $invocation

    local input="${1:-}"
    echo "${input%/}"
    return 0
}

# args:
# input - $1
remove_beginning_slash() {
    #eval $invocation

    local input="${1:-}"
    echo "${input#/}"
    return 0
}


enable_boldreports_services() {
	eval $invocation
	for t in ${services_array[@]}; do
		if is_service_already_exists "$t"; then
			say "Enabling service - $t"
			systemctl enable $t
		else
			say_err "Unable to enable service - $t"
		fi
	done
}

copy_files_to_installation_folder() {
	eval $invocation
	
	cp -a application/. $install_dir/application/
	cp -a clientlibrary/. $install_dir/clientlibrary/
	cp -a dotnet/. $install_dir/dotnet/
	cp -a services/. $install_dir/services/
	cp -a Infrastructure/. $install_dir/Infrastructure/
}

start_boldreports_services() {
	eval $invocation
	for t in ${services_array[@]}; do
		if is_service_already_exists "$t"; then
			say "Starting service - $t"
			systemctl start $t
			
			if [ $t = "bold-id-web" ]; then
			    say "Initializing $t"
			    sleep 5
			fi
		else
			say_err "Unable to start service - $t"
		fi
	done
}

status_boldreports_services() {
	eval $invocation
	systemctl --type=service | grep bold-*
}

stop_boldreports_services() {
	eval $invocation
	for t in ${services_array[@]}; do
		if is_service_already_exists "$t"; then
			say "Stopping service - $t"
			systemctl stop $t
		fi
	done
}

restart_boldreports_services() {
	eval $invocation
	for t in ${services_array[@]}; do
		if is_service_already_exists "$t"; then
			say "Restarting service - $t"
			systemctl restart $t
			
			if [ $t = "bold-id-web" ]; then
			    say "Initializing $t"
			    sleep 5
			fi
		else
			say_err "Unable to restart service - $t"
		fi
	done
}

chrome_package_installation() {
	eval $invocation

	[ ! -d "$app_data_location/reporting" ] && mkdir -p "$app_data_location/reporting"
	[ ! -d "$app_data_location/reporting/exporthelpers" ] && mkdir -p "$app_data_location/reporting/exporthelpers"
	[ ! -d "$puppeteer_location" ] && mkdir -p "$puppeteer_location"

	"$dotnet_dir/dotnet" "$install_dir/application/utilities/adminutils/Syncfusion.Server.Commands.Utility.dll" "installpuppeteer" -path "$puppeteer_location"
	install-chromium-dependencies
	
	if [ -d "$puppeteer_location/Linux-901912" ]; then
		say "Chrome package installed successfully"
	fi
}

install-chromium-dependencies() {
    eval $invocation
	
    apt-get update && apt-get -y install xvfb gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgbm1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget && rm -rf /var/lib/apt/lists/*
}

update_url_in_product_json() {
	eval $invocation
	old_url="http:\/\/localhost\/"
	new_url="$(remove_trailing_slash "$host_url")"

	idp_url="$new_url"
	say "IDP URL - $idp_url"
	
	reports_url="$new_url/reporting"
	say "Reports URL - $reports_url"
	
	reports_service_url="$new_url/reporting/reportservice"
	say "Reports Service URL - $reports_service_url"
	
	sed -i $boldreports_product_json_location -e "s|\"Idp\":.*\",|\"Idp\":\"$idp_url\",|g" -e "s|\"Reports\":.*\",|\"Reports\":\"$reports_url\",|g" -e "s|\"ReportsService\":.*\"|\"ReportsService\":\"$reports_service_url\"|g"
	
	say "Product.json file URLs updated."
}
	
copy_service_files () {
	eval $invocation
	
	cp -a "$1" "$2"
}
	
configure_nginx () {
	eval $invocation
	nginx_sites_available_dir="/etc/nginx/sites-available" 
	nginx_sites_enabled_dir="/etc/nginx/sites-enabled" 
	
	[ ! -d "$nginx_sites_available_dir" ] && mkdir -p "$nginx_sites_available_dir"
	[ ! -d "$nginx_sites_enabled_dir" ] && mkdir -p "$nginx_sites_enabled_dir"
	
	say "Copying Bold Reports Nginx config file"
	cp boldreports-nginx-config $nginx_sites_available_dir/boldreports-nginx-config
	
	nginx_default_file=$nginx_sites_available_dir/default
	if [ -f "$nginx_default_file" ]; then
		say "Taking backup of default nginx file"
		mv $nginx_default_file $nginx_sites_available_dir/default_backup
		say "Removing the default Nginx file"
		rm $nginx_sites_enabled_dir/default
	fi
	
	say "Creating symbolic links from these files to the sites-enabled directory"
	ln -s $nginx_sites_available_dir/boldreports-nginx-config $nginx_sites_enabled_dir/
	say "Validating the Nginx configuration"
	nginx -t
	say "Restarting the Nginx to apply the changes"
	nginx -s reload
}

configure_nginx_for_upgrade(){
	eval $invocation
	is_service_updated_in_config_file=false 

	IFS=$'\n'
	for t in ${!separated_services[@]}; do
    		if ! grep -q "${separated_services[$t]}" "$nginx_config_file_location"; then
  			while true; do
				read -p "Breaking changes: Added a ${t} service that needs to be configured in the Nginx configuration file. If you had installed the application using automatic Nginx configuration during initial installation, choose yes. If not, please complete current installation and manually configure the ${t} service in the Nginx file by referring to the help documentation: https://help.boldreports.com/enterprise-reporting/administrator-guide/installation/deploy-in-linux/upgrade-linux-server/#upgrade-breaking-changes  [yes / no]:  " yn
				case $yn in
					[Yy]* ) configure_service "${separated_services[$t]}" 
						is_service_updated_in_config_file=true; 
						break;;
					[Nn]* ) break;;
					* ) echo "Please answer yes or no.";;
				esac
			done
		fi
	done

	if [ "$is_service_updated_in_config_file" = true ]; then
		validate_nginx_config
	fi
}

validate_nginx_config(){
	eval $invocation
	say "Validating the Nginx configuration"
	nginx -t
	say "Restarting the Nginx to apply the changes"
	systemctl restart nginx
}

configure_service(){
	extracted_location=$(sed -n "/$1/, /}/ p" boldreports-nginx-config)
    	location='\'
	isFirstLine=true

    	for line in $extracted_location;do
    		if [[ "$isFirstLine" == true ]]; then
    			location+="$line"
			isFirstLine=false
    		else
        		location+="\n$line"
		fi
    	done
	
	sed -i "/^\(}\)/ i $location" "$nginx_config_file_location"
}

install_client_libraries () {
	eval $invocation
	mkdir -p $install_dir/clientlibrary/temp
	bash $install_dir/clientlibrary/install-optional.libs.sh install-optional-libs postgresql,mysql,oracle
}

install_phanthomjs () {
	eval $invocation
	mkdir -p $install_dir/application/app_data/reporting/exporthelpers
	mkdir -p $install_dir/clientlibrary/temp
	bash $install_dir/clientlibrary/install-optional.libs.sh install-optional-libs phantomjs
}

is_boldreports_already_installed() {
	systemctl list-unit-files | grep "bold-*" > /dev/null 2>&1
	return $?
}

is_service_already_exists() {
	systemctl list-unit-files | grep "$1" > /dev/null 2>&1
	return $?
}

taking_backup(){
	eval $invocation
	say "Started creating backup . . ."
	timestamp="$(date +"%T")"
	backup_file_location=$backup_folder/boldreports_backup_$timestamp.zip
	zip -qr $backup_file_location $install_dir
	say "Backup file name:$backup_file_location"
	say "Backup process completed . . ."
	return $?
}

removing_old_files(){
	eval $invocation
	rm -r $install_dir/application/reporting
	rm -r $install_dir/application/idp
	rm -r $install_dir/application/utilities
	rm -r $install_dir/clientlibrary
	rm -r $install_dir/dotnet
	if [ -d "$install_dir/dotnet-runtime-5.0" ]; then
	rm -r $install_dir/dotnet-runtime-5.0
	fi
	rm -r $install_dir/services
	rm -r $install_dir/Infrastructure
}
	
validate_user() {
	eval $invocation
	if [[ $# -eq 0 ]]; then
		say_err "Please specify the user that manages the service."
		return 1
	fi	
	
	# if grep -q "^$1:" /etc/passwd ;then
		# return 0
	# else
		# say_err "User $1 is not valid"
		# return 1
	# fi
	
	return 0
}

validate_host_url() {
	eval $invocation
	if [[ $# -eq 0 ]]; then
		say_err "Please specify the host URL."
		return 1
	fi	
	
	url_regex='(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
	if [[ $1 =~ $url_regex ]]; then 
		return 0
	else
		say_err "Please specify the valid host URL."
		return 1
	fi
}
	
validate_installation_type() {
	eval $invocation
	if  [[ $# -eq 0 ]]; then
		say_err "Please specify the installation type (new or upgrade)."
		return 1
	fi	

	if  [ "$(to_lowercase $1)" != "new" ] && [ "$(to_lowercase $1)" != "upgrade" ]; then
		say_err "Please specify the valid installation type."
		return 1
	fi

	return 0	
}
	
	
install_boldreports() {
	eval $invocation
    local download_failed=false
    local asset_name=''
    local asset_relative_path=''
	check_min_reqs

	if [[ "$?" != "0" ]]; then
		return 1
	fi
	
	validate_user $user
	if [[ "$?" != "0" ]]; then
		return 1
	fi 
	
	validate_installation_type $installation_type
	if [[ "$?" != "0" ]]; then
		return 1
	fi
	validate_host_url $host_url
	if [[ "$?" != "0" ]]; then
		return 1
	fi
			
	if is_boldreports_already_installed; then
		####### Bold Reports Upgrade Install######
		
		if [ "$(to_lowercase $installation_type)" = "new" ]; then
			say_err "Bold Reports already present in this machine. Terminating the installation process..."
			return 1
		fi
	
        say "Bold Reports already present in this machine."
		stop_boldreports_services
		sleep 5
		if taking_backup; then		
			removing_old_files
			
			copy_files_to_installation_folder
			
			update_url_in_product_json
			
			find "$services_dir" -type f -name "*.service" -print0 | xargs -0 sed -i "s|www-data|$user|g"
			copy_service_files "$services_dir/." "$system_dir"
			
			chmod +x "$dotnet_dir/dotnet"
			
			[ ! -d "$puppeteer_location/Linux-901912" ] && chrome_package_installation
			
			chown -R "$user" "$install_dir"
			
			enable_boldreports_services
			start_boldreports_services

			if [ -f "$nginx_config_file_location" ]; then
				configure_nginx_for_upgrade
			else
				say "Breaking changes: Added new services that need to be manually configured in the Nginx configuration file. Please refer to the help documentation for more information: https://help.boldreports.com/enterprise-reporting/administrator-guide/installation/deploy-in-linux/upgrade-linux-server/#upgrade-breaking-changes"
			fi
			
			sleep 5
			
			status_boldreports_services
			say "Bold Reports upgraded successfully!!!"
			
			return 0
		else
			return 1
		fi
    else
		####### Bold Reports Fresh Install######
	
		if [ "$installation_type" = "upgrade" ]; then
			say_err "Bold Reports is not present in this machine. Terminating the installation process..."
			say_err "Please do a fresh install."
			return 1
		fi
	
		mkdir -p "$install_dir"    
		copy_files_to_installation_folder
		update_url_in_product_json
		find "$services_dir" -type f -name "*.service" -print0 | xargs -0 sed -i "s|www-data|$user|g"
		copy_service_files "$services_dir/." "$system_dir"
		#install_client_libraries
		#install_phanthomjs
		
		chmod +x "$dotnet_dir/dotnet"
		
		chrome_package_installation
		
		chown -R "$user" "$install_dir"
		
		sleep 5
		
		enable_boldreports_services
		start_boldreports_services
		
		sleep 5
	
		status_boldreports_services
		
		if [ "$can_configure_nginx" = true ]; then
			configure_nginx
		fi
		say "Bold Reports installation completed!!!"
		return 0
    fi
	
	#zip_path="$(mktemp "$temporary_file_template")"
    #say_verbose "Zip path: $zip_path"
	
	# Failures are normal in the non-legacy case for ultimately legacy downloads.
    # Do not output to stderr, since output to stderr is considered an error.
    #say "Downloading primary link $download_link"
	
	# The download function will set variables $http_code and $download_error_msg in case of failure.
    #http_code=""; download_error_msg=""
    #download "$download_link" "$zip_path" 2>&1 || download_failed=true
    #primary_path_http_code="$http_code"; primary_path_download_error_msg="$download_error_msg"
	
	#say "Extracting zip from $download_link"
	
	#extract_boldbi_package "$zip_path" "$install_dir" || return 1
}

install_boldreports
