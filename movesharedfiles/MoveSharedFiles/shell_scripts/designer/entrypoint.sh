#!/bin/bash

commonPath=/application/app_data/optional-libs
clientLibraryPath=$commonPath/boldreports
if [ -d "$clientLibraryPath" ]; then
    bash $clientLibraryPath/install-optional.libs.sh install-optional-libs reportservice
    echo "Clientlibrary installed from boldreports folder"
else
    bash $commonPath/reporting/install-optional.libs.sh install-optional-libs reportservice
    echo  "Clientlibrary installed from reporting folder"
fi

dotnet BoldReports.Server.Services.dll