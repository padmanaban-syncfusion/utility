#!/bin/bash
root_path="/application"
etl_path="$root_path/etl/etlservice"

update_nginx_configuration() {

nginx_conf="/etc/nginx/sites-available/boldreports-nginx-config"

viewer_location_block=$(cat <<EOL
        location /etlservice/ {
        root               /application/reporting/viewer;
        proxy_pass         http://localhost:6507/;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "keep-alive";
        proxy_set_header   Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
EOL
)

etl_location_block=$(cat <<EOL
        location /etlservice/ {
        root               /application/etl/etlservice/wwwroot;
        proxy_pass         http://localhost:6509/;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
        location /etlservice/_framework/blazor.server.js {
        root               /application/etl/etlservice/wwwroot;
        proxy_pass         http://localhost:6509/_framework/blazor.server.js;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
   }
}
EOL
)

if ! grep -Eq "location .*/viewer.*" "$nginx_conf"; then
    # Append the new location block to the end of the file
    sed -i '${/}/d;}' $nginx_conf
    echo "$viewer_location_block" >> "$nginx_conf"
    echo "Viewer location block added in Nginx file"
fi

if ! grep -Eq "location .*/etlservice/.*" "$nginx_conf"; then
    # Append the new location block to the end of the file
    sed -i '${/}/d;}' $nginx_conf
    echo "$etl_location_block" >> "$nginx_conf"
    echo "ETL location block added in Nginx file"
fi
}

echo "Checking whether product.json exists in app_data folder."   
if [ ! -f /application/app_data/configuration/product.json ]; then

        if [ -z $APP_URL ]; then
                mkdir -p /application/app_data/configuration && cp -rf product.json /application/app_data/configuration/product.json
        else
                export IDPURL=$APP_URL
                jq --arg IDPURL "$IDPURL" '.InternalAppUrl.Idp=$IDPURL' product.json > out1.json

                export REPORTURL=$APP_URL"/reporting"
                jq --arg REPORTURL "$REPORTURL" '.InternalAppUrl.Reports=$REPORTURL' out1.json > out2.json

                export REPORTDESIGNERURL=$APP_URL"/reporting/reportservice"
                jq --arg REPORTDESIGNERURL "$REPORTDESIGNERURL" '.InternalAppUrl.ReportsService=$REPORTDESIGNERURL' out2.json > out3.json

                mkdir -p /application/app_data/configuration/ && cp -rf out3.json /application/app_data/configuration/product.json
                rm out1.json out2.json out3.json
    fi
        echo "Updated product.json with APP_URL and moved to app_data folder."

else
        dotnet "$root_path/clientlibrary/MoveSharedFiles/MoveSharedFiles.dll" upgrade_version docker
fi

cd /application/idp/web/
nohup dotnet Syncfusion.Server.IdentityProvider.Core.dll --urls=http://localhost:6500 &>/dev/null &
echo "Started IDP web application."

sleep 15s

cd /application/idp/api/
nohup dotnet Syncfusion.Server.IdentityProvider.API.Core.dll --urls=http://localhost:6501 &>/dev/null &
echo "Started IDP API application."

cd /application/idp/ums/
nohup dotnet Syncfusion.TenantManagement.Core.dll --urls=http://localhost:6502 &>/dev/null &
echo "Started UMS application."

cd /application/reporting/web/
nohup dotnet Syncfusion.Server.Reports.dll --urls=http://localhost:6504 &>/dev/null &
echo "Started Reports web application."

cd /application/reporting/api/
nohup dotnet Syncfusion.Server.API.dll --urls=http://localhost:6505 &>/dev/null &
echo "Started Reports API application."

cd /application/reporting/jobs/
nohup dotnet Syncfusion.Server.Jobs.dll --urls=http://localhost:6506 &>/dev/null &
echo "Started Reports jobs application."

cd /application/reporting/viewer/
nohup dotnet Syncfusion.Server.Viewer.dll --urls=http://localhost:6507 &>/dev/null &
echo "Started Reports viewer application."

cd /application/reporting/reportservice/
nohup dotnet BoldReports.Server.Services.dll --urls=http://localhost:6508 &>/dev/null &
echo "Started Reports designer application."

cd "$etl_path"
nohup dotnet BOLDELT.dll --urls=http://localhost:6509 &> "$syslogs/etl.txt" &
echo "Started ETL application [ETL Service for Bold Enterprise Products.]"

echo "Configuring nginx web server."
cd /application

if [ "$OS_ENV" != "alpine" ]; then
        nginx_sites_available_dir="/etc/nginx/sites-available"
        nginx_sites_enabled_dir="/etc/nginx/sites-enabled"

        if [ ! -f $nginx_sites_available_dir/boldreports-nginx-config ]; then

        [ ! -d "$nginx_sites_available_dir" ] && mkdir -p "$nginx_sites_available_dir"
        [ ! -d "$nginx_sites_enabled_dir" ] && mkdir -p "$nginx_sites_enabled_dir"

        cp boldreports-nginx-config $nginx_sites_available_dir/boldreports-nginx-config

        fi
		
		update_nginx_configuration
        ln -s $nginx_sites_available_dir/boldreports-nginx-config $nginx_sites_enabled_dir/
    rm $nginx_sites_enabled_dir/default
else
        echo "include /etc/nginx/sites-available/boldreports-nginx-config;" > /etc/nginx/http.d/default.conf
        nginx_sites_available_dir="/etc/nginx/sites-available"

        if [ ! -f $nginx_sites_available_dir/boldreports-nginx-config ]; then

        [ ! -d "$nginx_sites_available_dir" ] && mkdir -p "$nginx_sites_available_dir"

        cp boldreports-nginx-config $nginx_sites_available_dir/boldreports-nginx-config

        fi
fi

nginx -c /etc/nginx/nginx.conf
echo "Started nginx web server."

dotnet "$root_path/clientlibrary/MoveSharedFiles/MoveSharedFiles.dll"

bash $root_path/clientlibrary/install-optional.libs.sh install-optional-libs $OPTIONAL_LIBS

app_data_location="$root_path/app_data"
puppeteer_location="$app_data_location/reporting/exporthelpers/puppeteer"
	
if [ ! -d "$puppeteer_location/chrome-linux" ]; then
	eval $invocation
					
	[ ! -d "$app_data_location/reporting" ] && mkdir -p "$app_data_location/reporting"
	[ ! -d "$app_data_location/reporting/exporthelpers" ] && mkdir -p "$app_data_location/reporting/exporthelpers"
	[ ! -d "$puppeteer_location" ] && mkdir -p "$puppeteer_location"
	dotnet "utilities/adminutils/Syncfusion.Server.Commands.Utility.dll" "installpuppeteer" -path "$puppeteer_location"
fi

if [ -d "$puppeteer_location/Linux-901912" ]; then
	echo "Chrome package installed successfully"
	[ -f "$app_data_location/reporting/exporthelpers/phantomjs" ] && rm -rf "$app_data_location/reporting/exporthelpers/phantomjs"
fi

echo "Configure the Bold Reports On-Premise application startup to use the application"
echo "Please refer the following link for more details"
echo "https://help.boldreports.com/enterprise-reporting/administrator-guide/application-startup"
echo "Please refer here for Bold Reports Enterprise documentation => https://help.boldreports.com/enterprise-reporting/"

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
  
  ps aux | grep BOLDELT.dll | grep -q -v grep
  PROCESS_9_STATUS=$?

  if [ $PROCESS_1_STATUS -ne 0 -o $PROCESS_2_STATUS -ne 0 -o $PROCESS_3_STATUS -ne 0 -o $PROCESS_4_STATUS -ne 0 -o $PROCESS_5_STATUS -ne 0 -o $PROCESS_6_STATUS -ne 0 -o $PROCESS_7_STATUS -ne 0 -o $PROCESS_8_STATUS -ne 0 -o $PROCESS_9_STATUS -ne 0 ]; then
    echo "One of the application has exited."
    exit 1
  fi
done