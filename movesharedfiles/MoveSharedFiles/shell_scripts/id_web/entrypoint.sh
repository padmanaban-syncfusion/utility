#!/bin/bash

app_data_location="/application/app_data"
puppeteer_location="$app_data_location/reporting/exporthelpers/puppeteer"

dotnet appdatafiles/MoveSharedFiles/MoveSharedFiles.dll

if [ ! -d "$puppeteer_location/Linux-901912" ]; then
	[ ! -d "$app_data_location/reporting" ] && mkdir -p "$app_data_location/reporting"
	[ ! -d "$app_data_location/reporting/exporthelpers" ] && mkdir -p "$app_data_location/reporting/exporthelpers"
	[ ! -d "$puppeteer_location" ] && mkdir -p "$puppeteer_location"

	dotnet "/application/utilities/adminutils/Syncfusion.Server.Commands.Utility.dll" "installpuppeteer" -path "$puppeteer_location"
fi

if [ -d "$puppeteer_location/Linux-901912" ]; then
	## Removing PhantomJS
	[ -f "$app_data_location/reporting/exporthelpers/phantomjs" ] && rm -rf "$app_data_location/reporting/exporthelpers/phantomjs"
fi

dotnet Syncfusion.Server.IdentityProvider.Core.dll