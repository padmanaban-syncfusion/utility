#!/bin/bash
#!/bin/bash
# command to run this file
# bash install-option-lib.sh install-optional-libs {podname} 
command=$1
podname=$2
root_path=$3
installoptionlibs="install-optional-libs"

# check pod name validation
if [ -z "$podname" ]
then
echo "Pod Name is empty. Please enter the valid command"
echo "api or web or jobs or reportservice"

# begin progress to copy optional libraries
else

if [ -z "$root_path" ]
then
root_path="/application"
fi

entrypath=$root_path/app_data/optional-libs
clientlibrary=$entrypath/boldreports
assemblypath=$clientlibrary/clientlibraries
arguments=$(<$entrypath/optional-libs.txt)

# check empty command 
if [ -z "$command" ]
then
echo "Command is empty. Please enter the valid command"
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
assembly=("mysql" "oracle" "postgresql" "snowflake")
mysqlassemblies=""
postgresqlassemblies=""
oracleassemblies=""
snowflakeassemblies=""
podpath=$root_path/reporting/$podname
if [ $podname == "reportservice" ]
then
jsonfilepath="${podpath}/appsettings.json;"
else
jsonfilepath="${podpath}/appsettings.Production.json;"
fi
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
pluginpath=$root_path/reporting/$podname
for element in "${assmeblyarguments[@]}"
do
case $element in
"mysql")
mysqlassemblies="${element}=BoldReports.Data.MySQL;MemSQL;MariaDB;"
yes | cp -rpf $assemblypath/BoldReports.Data.MySQL.dll $pluginpath
yes | cp -rpf $assemblypath/MySqlConnector.dll $pluginpath
echo "mysql libraries are installed"
;;
"oracle")
oracleassemblies="${element}=BoldReports.Data.Oracle;"
yes | cp -rpf $assemblypath/BoldReports.Data.Oracle.dll $pluginpath
yes | cp -rpf $assemblypath/Oracle.ManagedDataAccess.dll $pluginpath
echo "oracle libraries are installed"
;;
"postgresql")
postgresqlassemblies="${element}=BoldReports.Data.PostgreSQL;"
yes | cp -rpf $assemblypath/BoldReports.Data.PostgreSQL.dll $pluginpath
yes | cp -rpf $assemblypath/Npgsql.dll $pluginpath
echo "postgresql libraries are installed"
;;
"snowflake")
snowflakeassemblies="${element}=BoldReports.Data.Snowflake;Snowflake.Data;"
yes | cp -rpf $assemblypath/BoldReports.Data.Snowflake.dll $pluginpath
yes | cp -rpf $assemblypath/Snowflake.Data.dll $pluginpath
yes | cp -rpf $assemblypath/Mono.Unix.dll $pluginpath
echo "snowflake libraries are installed"
;;
esac
done

# add client libraries in json files
clientLibraries="$mysqlassemblies$oracleassemblies$postgresqlassemblies$snowflakeassemblies"
dotnet $clientlibrary/clientlibraryutility/ClientLibraryUtil.dll $clientLibraries $jsonfilepath
echo "client libraries are updated"

fi
fi
fi
fi