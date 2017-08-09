#Created by Bruce Roberts on 

#!/bin/bash

read -p "Are you sure you want to clear the time log? Your progress will be reset to 00:00:00. ( [y]=yes ) " answer

if [ "$answer" == "y" ]
then

dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$dir"

dte=`date "+(%H:%M:%S)%d-%m-%y"`
zip "Archive - "$dte.zip ./periods.txt ./data.js

rm ./periods.txt
rm ./data.js



fi
