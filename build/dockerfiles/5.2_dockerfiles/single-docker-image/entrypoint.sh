#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.
#

# Stop script on NZEC
set -e

# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Use in the the functions: eval $invocation
invocation='say_verbose "Calling: ${yellow:-}${FUNCNAME[0]} ${green:-}$*${white:-}"'

# standard output may be used as a return value in the functions
# we need a way to write text on the screen in the functions so that
# it won't interfere with the return value.
# Exposing stream 3 as a pipe to standard output of the script itself
exec 3>&1

verbose=true
args=("$@")
root_path="/application"
app_data_path="$root_path/app_data"
configuration_path="$app_data_path/configuration"
product_json_path="$configuration_path/product.json"
config_xml_path="$configuration_path/config.xml"
id_path="$root_path/idp"
reports_path="$root_path/reporting"
counter=0
is_success=false

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
    printf "%b\n" "${yellow:-}configure_boldreports: Warning: $1${white:-}" >&3
}

say_err() {
    printf "%b\n" "${red:-}configure_boldreports: Error: $1${white:-}" >&2
}

say_success() {
    printf "%b\n" "${cyan:-}configure_boldreports: ${green:-}$1${white:-}" >&2
}

say_bold() {
    printf "%b\n" "${cyan:-}configure_boldreports: ${bold:-}$1${white:-}" >&2
}

say() {
    # using stream 3 (defined in the beginning) to not interfere with stdout of functions
    # which may be used as return value
        printf "%b\n" "${cyan:-}configure_boldreports: ${white:-}$1" >&3
}

say_verbose() {
    if [ "$verbose" = true ]; then
        say "$1"
    fi
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

start_boldreports_services() {
        eval $invocation

        cd "$id_path/web/"
        nohup dotnet Syncfusion.Server.IdentityProvider.Core.dll --urls=http://localhost:6500 &>/dev/null &     
        say "Starting IDP Web application [Identity Provider Web for Bold Enterprise Products.]"

        check_config_file_generated

        cd "$id_path/api/"
        nohup dotnet Syncfusion.Server.IdentityProvider.API.Core.dll --urls=http://localhost:6501 &>/dev/null & 
       say "Starting IDP API application [Identity Provider REST API for Bold Enterprise Products.]"

        cd "$id_path/ums/"
        nohup dotnet Syncfusion.TenantManagement.Core.dll --urls=http://localhost:6502 &>/dev/null &
        say "Starting UMS application [Tenant and User Management for Bold Enterprise Products.]"

        install_client_libraries

        cd "$reports_path/web/"
        nohup dotnet Syncfusion.Server.Reports.dll --urls=http://localhost:6504 &>/dev/null &
        say "Starting Reports Web application [Reports Server for Bold Reports.]"

        cd "$reports_path/api/"
        nohup dotnet Syncfusion.Server.API.dll --urls=http://localhost:6505 &>/dev/null &
        say "Starting Reports API application [Reports API Service for Bold Reports.]"

        cd "$reports_path/jobs/"
        nohup dotnet Syncfusion.Server.Jobs.dll --urls=http://localhost:6506 &>/dev/null &
        say "Starting Reports Jobs application [Reports Jobs Service for Bold Reports.]"
        
        cd "$reports_path/viewer/"
        nohup dotnet Syncfusion.Server.Viewer.dll --urls=http://localhost:6507 &>/dev/null &
        say "Starting Reports Viewer application [Reports Viewer Service for Bold Reports.]"

        cd "$reports_path/reportservice/"
        nohup dotnet BoldReports.Server.Services.dll --urls=http://localhost:6508 &>/dev/null &   
        say "Starting Reports Designer application [Reports Designer Service for Bold Reports.]"
}

check_config_file_generated() {
        eval $invocation

        ## code to check whether the config.xml file is generated or not
        say "Initializing configuration files..."

        while :
        do
                if [ -f "$config_xml_path" ]; then
                        break
                fi
        done

        say_success "Config files generated successfully."
        ##
}

update_url_in_product_json() {
        eval $invocation

        say "Checking whether product.json exists in app_data folder."
        if [ ! -f $product_json_path ]; then

                if [ -z $APP_URL ]; then
                        mkdir -p $configuration_path && cp -rf product.json $product_json_path
                else
                        export IDPURL=$APP_URL
                        jq --arg IDPURL "$IDPURL" '.InternalAppUrl.Idp=$IDPURL' product.json > out1.json        

                        export REPORTURL=$APP_URL"/reporting"
                        jq --arg REPORTURL "$REPORTURL" '.InternalAppUrl.Reports=$REPORTURL' out1.json > out2.json

                        export REPORTDESIGNERURL=$APP_URL"/reporting/reportservice"
                        jq --arg REPORTDESIGNERURL "$REPORTDESIGNERURL" '.InternalAppUrl.ReportsService=$REPORTDESIGNERURL' out2.json > out3.json

                        mkdir -p $configuration_path && cp -rf out3.json $product_json_path
                        rm out1.json out2.json out3.json
                fi
                say_success "Updated product.json with APP_URL and moved to app_data folder."
        else
                dotnet "$root_path/clientlibrary/MoveSharedFiles/MoveSharedFiles.dll" upgrade_version docker
        fi
}

configure_nginx () {
        eval $invocation

        say "Configuring Nginx web server."
        cd $root_path

        if [ "$OS_ENV" != "alpine" ]; then
                nginx_sites_available_dir="/etc/nginx/sites-available"
                nginx_sites_enabled_dir="/etc/nginx/sites-enabled"

                if [ ! -f $nginx_sites_available_dir/boldreports-nginx-config ]; then
                        [ ! -d "$nginx_sites_available_dir" ] && mkdir -p "$nginx_sites_available_dir"
                        [ ! -d "$nginx_sites_enabled_dir" ] && mkdir -p "$nginx_sites_enabled_dir"

                        cp boldreports-nginx-config $nginx_sites_available_dir/boldreports-nginx-config
                fi

                [ ! -f "$nginx_sites_enabled_dir/boldreports-nginx-config" ] && ln -sf $nginx_sites_available_dir/boldreports-nginx-config $nginx_sites_enabled_dir/default
        else
                echo "include /etc/nginx/sites-available/boldreports-nginx-config;" > /etc/nginx/http.d/default.conf 

                nginx_sites_available_dir="/etc/nginx/sites-available"

                if [ ! -f $nginx_sites_available_dir/boldreports-nginx-config ]; then
                        [ ! -d "$nginx_sites_available_dir" ] && mkdir -p "$nginx_sites_available_dir"
                        cp boldreports-nginx-config $nginx_sites_available_dir/boldreports-nginx-config
                fi
        fi

        nginx -c /etc/nginx/nginx.conf
        say "Starting Nginx web server."
}


install_client_libraries() {
        eval $invocation

        dotnet "$root_path/clientlibrary/MoveSharedFiles/MoveSharedFiles.dll"

    bash $root_path/clientlibrary/install-optional.libs.sh install-optional-libs $OPTIONAL_LIBS
}

final_configuration() {
        eval $invocation

        ## code to check whether all services were running or not
        APP_URL=($(cat $product_json_path | jq '.InternalAppUrl.Idp'))
        APP_URL=$(eval echo $APP_URL)
        domain="$(remove_trailing_slash "$APP_URL")"
        #domain=$(basename "$APP_URL")

        health_check_endpoint="$domain/api/status"
        keyword1='"is_running":true'
        keyword2='"is_running":false'

        say "Completing final configuration. Please wait..."

        while sleep 5; do
                counter=$((counter+1))

                if curl -s "$health_check_endpoint" | grep -q "$keyword1"
                then
                        say "This may take some time..."
                        while :
                        do
                                if ! curl -s "$health_check_endpoint" | grep -q "$keyword2"
                                then
                                        is_success=true
                                        break
                                fi
                        done
                        break
                elif [[ "$counter" -eq 18 ]]; then
                    say "This is taking more time than usual. Please wait..."
                elif [[ "$counter" -gt 36 ]]; then
                        say "Please check whether your domain in APP_URL is correct. Unable to configure boldreports with $domain"
                        break
                fi
        done

    if $is_success; then
            say_success "Bold Reports configuration completed successfully."
            say_success "Bold Reports is ready to use now."
        fi
}

final_notes() {
        eval $invocation

        say "Configure the Bold Reports On-Premise application startup to use the application."
        say "Please refer the following link for more details"
        say "https://help.boldreports.com/enterprise-reporting/administrator-guide/application-startup"
        say "Please refer here for Bold Reports Enterprise documentation => https://help.boldreports.com/enterprise-reporting/"      
}

scan_services() {
        while sleep 60; do
          ps aux |grep Syncfusion.Server.IdentityProvider.Core.dll |grep -q -v grep
          PROCESS_1_STATUS=$?

          ps aux |grep Syncfusion.Server.IdentityProvider.API.Core.dll |grep -q -v grep
          PROCESS_2_STATUS=$?

          ps aux |grep Syncfusion.TenantManagement.Core.dll |grep -q -v grep
          PROCESS_3_STATUS=$?

          ps aux |grep Syncfusion.Server.Reports.dll |grep -q -v grep
          PROCESS_4_STATUS=$?

          ps aux |grep Syncfusion.Server.API.dll |grep -q -v grep
          PROCESS_5_STATUS=$?

          ps aux |grep Syncfusion.Server.Jobs.dll |grep -q -v grep
          PROCESS_6_STATUS=$?

          ps aux |grep Syncfusion.Server.Viewer.dll |grep -q -v grep
          PROCESS_7_STATUS=$?

          ps aux |grep BoldReports.Server.Services.dll |grep -q -v grep
          PROCESS_8_STATUS=$?

          if [ $PROCESS_1_STATUS -ne 0 -o $PROCESS_2_STATUS -ne 0 -o $PROCESS_3_STATUS -ne 0 -o $PROCESS_4_STATUS -ne 0        -o $PROCESS_5_STATUS -ne 0 -o $PROCESS_6_STATUS -ne 0 -o $PROCESS_7_STATUS -ne 0 $PROCESS_8_STATUS -ne 0]; then
                say_err "One of the application has exited."
                exit 1
          fi
        done
}

configure_boldreports() {
        eval $invocation

        update_url_in_product_json
        start_boldreports_services
        configure_nginx
        final_configuration
        if $is_success; then final_notes; fi
        scan_services
}

configure_boldreports
