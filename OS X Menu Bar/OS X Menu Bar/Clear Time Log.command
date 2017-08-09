#Created by Bruce Roberts on 

#!/bin/bash

read -p "Are you sure you want to clear the time log? Your progress will be reset to 00:00:00. [y]=yes " answer

if [ "$answer" == "y" ]
then

echo $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

rm "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/periods.txt
rm "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/data.js

fi
