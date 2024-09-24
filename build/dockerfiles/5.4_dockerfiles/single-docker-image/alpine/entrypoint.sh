#!/bin/bash
root_path="/application"

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

  if [ $PROCESS_1_STATUS -ne 0 -o $PROCESS_2_STATUS -ne 0 -o $PROCESS_3_STATUS -ne 0 -o $PROCESS_4_STATUS -ne 0 -o $PROCESS_5_STATUS -ne 0 -o $PROCESS_6_STATUS -ne 0 -o $PROCESS_7_STATUS -ne 0 -o $PROCESS_8_STATUS -ne 0 ]; then
    echo "One of the application has exited."
    exit 1
  fi
done
