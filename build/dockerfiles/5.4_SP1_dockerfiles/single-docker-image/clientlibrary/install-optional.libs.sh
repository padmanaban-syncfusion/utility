#!/bin/bash
#!/bin/bash
# command to run this file
# bash install-option-lib.sh install-optional-libs {podname} 
command=$1
podname=$2
root_path=$3
installoptionlibs="install-optional-libs"
root_path="/application"
entrypath=$root_path/app_data/optional-libs
clientlibrary=$entrypath/boldreports
assemblypath=$clientlibrary/clientlibraries

 # check empty assembly names
        if [ -z "$podname" ]
        then
        echo "No Optional Libraries were chosen."
        else 

        # split assembly name into array

        IFS=', ' read -r -a assmeblyarguments <<< "$podname"
        assembly=("mysql" "oracle" "postgresql")
        directories=("api" "jobs" "web" "viewer" "reportservice")
        mysqlassemblies=""
        postgresqlassemblies=""
        oracleassemblies=""
        serverpath=$root_path/reporting
        apijson="${serverpath}/api/appsettings.Production.json;"
        jobsjson="${serverpath}/jobs/appsettings.Production.json;"
        webjson="${serverpath}/web/appsettings.Production.json;"
        viewerjson="${serverpath}/viewer/appsettings.Production.json;"
        servicejson="${serverpath}/reportservice/appsettings.json"
        jsonfiles="$apijson$jobsjson$webjson$viewerjson$servicejson"
        nonexistassembly=()          




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
for element in "${assmeblyarguments[@]}"
do
case $element in
"mysql")
mysqlassemblies="${element}=BoldReports.Data.MySQL;MemSQL;MariaDB;"
for dirname in "${directories[@]}"
do
pluginpath=$root_path/reporting/$dirname
yes | cp -rpf $assemblypath/BoldReports.Data.MySQL.dll $pluginpath
yes | cp -rpf $assemblypath/MySqlConnector.dll $pluginpath
done
echo "mysql libraries are installed"
;;
"oracle")
oracleassemblies="${element}=BoldReports.Data.Oracle;"
for dirname in "${directories[@]}"
do
pluginpath=$root_path/reporting/$dirname
yes | cp -rpf $assemblypath/BoldReports.Data.Oracle.dll $pluginpath
yes | cp -rpf $assemblypath/Oracle.ManagedDataAccess.dll $pluginpath
done
echo "oracle libraries are installed"
;;
"postgresql")
postgresqlassemblies="${element}=BoldReports.Data.PostgreSQL;"
for dirname in "${directories[@]}"
do
pluginpath=$root_path/reporting/$dirname
yes | cp -rpf $assemblypath/BoldReports.Data.PostgreSQL.dll $pluginpath
yes | cp -rpf $assemblypath/Npgsql.dll $pluginpath
done
echo "postgresql libraries are installed"
;;
esac
done

# add client libraries in json files
clientLibraries="$mysqlassemblies$oracleassemblies$postgresqlassemblies"
dotnet $clientlibrary/clientlibraryutility/ClientLibraryUtil.dll $clientLibraries $jsonfiles
echo "client libraries are updated"

fi
fi