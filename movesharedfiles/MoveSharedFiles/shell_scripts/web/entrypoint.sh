#!/bin/bash

commonPath=/application/app_data/optional-libs
clientLibraryPath=$commonPath/boldreports
if [ -d "$clientLibraryPath" ]; then
    bash $clientLibraryPath/install-optional.libs.sh install-optional-libs web
    echo "Clientlibrary installed from boldreports folder"
else
    bash $commonPath/reporting/install-optional.libs.sh install-optional-libs web
    echo  "Clientlibrary installed from reporting folder"
fi

dotnet Syncfusion.Server.Reports.dll