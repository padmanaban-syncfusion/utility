#!/bin/bash
# command to run this file
# bash install-option-lib.sh install-optional-libs {user} oracle,postgresql,mysql,snowflake
command=$1
user=$2
arguments=$3
root_path=$4
installoptionlibs="install-optional-libs"
installphantomjs="installphantomjs"
if [ -z "$root_path" ]
then
root_path="/var/www/bold-services"
fi
clientlibrary=$root_path/clientlibrary/boldreports
clientlibraryzip=$clientlibrary/clientlibraries.zip
clientlibraryextractpath=$clientlibrary/temp
# check empty command 
if [ -z "$command" ]
then
echo "Please enter the valid command"
echo "install-optional-libs"

# check valid command
elif [ $command != "$installoptionlibs" ];
then
echo "Please enter the valid command"
echo "install-optional-libs"

# copy optionlib block
else

# check empty assembly names
if [ -z "$arguments" ]
then
echo "Please pass optional library names as arguments."
else

# split assembly name into array
IFS=', ' read -r -a assmeblyarguments <<< "$arguments"
assembly=("phantomjs" "mysql" "oracle" "postgresql" "snowflake")
directories=("api" "jobs" "web" "viewer" "reportservice")
mysqlassemblies=""
postgresqlassemblies=""
oracleassemblies=""
snowflakeassemblies=""
serverpath=$root_path/application/reporting/
apijson="${serverpath}/api/appsettings.Production.json;"
jobsjson="${serverpath}/jobs/appsettings.Production.json;"
webjson="${serverpath}/web/appsettings.Production.json;"
viewerjson="${serverpath}/viewer/appsettings.Production.json;"
servicejson="${serverpath}/reportservice/appsettings.json"
jsonfiles="$apijson$jobsjson$webjson$viewerjson$servicejson"
nonexistassembly=()

# change the directory owner
changeowner() {
    if [ ! -z "$user" ]
    then
    chown -R "$user":"$user" $1
    fi
}

# create invalid assembly array
for element in "${assmeblyarguments[@]}"
do
    if [[ ! " ${assembly[@]} " =~ " ${element} " ]]; then
    nonexistassembly+=("$element")
fi
done

# check non exist assembly count
if [ ${#nonexistassembly[@]} -ne 0 ]; then
echo "The below optional library names do not exist. Please enter valid library names."

for element in "${nonexistassembly[@]}"
do
echo "$element"
done

else
if [ $arguments != "phantomjs" ]
then
echo "$clientlibraryextractpath"
rm -r $clientlibraryextractpath
mkdir -p $clientlibraryextractpath
unzip $clientlibraryzip -d $clientlibraryextractpath
changeowner $clientlibraryextractpath
fi

for element in "${assmeblyarguments[@]}"
do
case $element in
"snowflake")
snowflakeassemblies="${element}=BoldReports.Data.Snowflake;"
for dirname in "${directories[@]}"
do
pluginpath=$root_path/application/reporting/$dirname
yes | cp -rpf $clientlibraryextractpath/BoldReports.Data.Snowflake.dll $pluginpath
yes | cp -rpf $clientlibraryextractpath/Snowflake.Data.dll $pluginpath
yes | cp -rpf $clientlibraryextractpath/Mono.Unix.dll $pluginpath
done
echo "snowflake libraries are installed"
;;
"mysql")
mysqlassemblies="${element}=BoldReports.Data.MySQL;MemSQL;MariaDB;"
for dirname in "${directories[@]}"
do
pluginpath=$root_path/application/reporting/$dirname
yes | cp -rpf $clientlibraryextractpath/BoldReports.Data.MySQL.dll $pluginpath
yes | cp -rpf $clientlibraryextractpath/MySqlConnector.dll $pluginpath
done
echo "mysql libraries are installed"
;;
"oracle")
oracleassemblies="${element}=BoldReports.Data.Oracle;"
for dirname in "${directories[@]}"
do
pluginpath=$root_path/application/reporting/$dirname
yes | cp -rpf $clientlibraryextractpath/BoldReports.Data.Oracle.dll $pluginpath
yes | cp -rpf $clientlibraryextractpath/Oracle.ManagedDataAccess.dll $pluginpath
done
echo "oracle libraries are installed"
;;
"postgresql")
postgresqlassemblies="${element}=BoldReports.Data.PostgreSQL;"
for dirname in "${directories[@]}"
do
pluginpath=$root_path/application/reporting/$dirname
yes | cp -rpf $clientlibraryextractpath/BoldReports.Data.PostgreSQL.dll $pluginpath
yes | cp -rpf $clientlibraryextractpath/Npgsql.dll $pluginpath
done
echo "postgresql libraries are installed"
;;
"phantomjs")
export PHANTOM_JS="phantomjs-2.1.1-linux-x86_64"
rm -r $clientlibrary/$PHANTOM_JS
wget -P $clientlibrary https://bitbucket.org/ariya/phantomjs/downloads/$PHANTOM_JS.tar.bz2
tar xvjf $clientlibrary/$PHANTOM_JS.tar.bz2 -C $clientlibrary
dataservicepath=$root_path/application/app_data/reporting/exporthelpers

if [ ! -d "$dataservicepath" ]
then
mkdir -p $dataservicepath
fi

changeowner $clientlibrary/$PHANTOM_JS
phantomjspath=$clientlibrary/$PHANTOM_JS/bin/phantomjs
yes | cp -rpf $phantomjspath $dataservicepath
changeowner $dataservicepath
echo "phantomjs libraries are installed"
rm -r $clientlibrary/$PHANTOM_JS.tar.bz2
rm -r $clientlibrary/$PHANTOM_JS
;;
esac
done

if [ $arguments != "phantomjs" ]
then
# add client libraries in json files
clientLibraries="$mysqlassemblies$oracleassemblies$postgresqlassemblies$snowflakeassemblies"
$root_path/dotnet/dotnet $clientlibrary/clientlibraryutility/ClientLibraryUtil.dll $clientLibraries $jsonfiles
echo "client libraries are updated"
rm -r $clientlibraryextractpath
fi

fi
fi
fi