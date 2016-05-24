#!/bin/bash
# Author: Pratap Raj
# Purpose: Send backup reports as email

############     User configuratble variables #############
#_mailaddress is recipient email address.
_mailaddress=''
##########    User configuratble variables end  ###########

#Validate number of arguments
if [ $# -ne 3 ];then
echo "$(date +%F\ %R) ERROR: Not enough arguments"
echo "Usage example: $0 05/24/16 /var/log/hdfsbackup.log HdfsBackup"
exit 1
fi

#Validate date argument
if ! date -d "$1" &>/dev/null; then
echo "ERROR: Invalid date"
exit 1
fi

#Validate file argument
if [ ! -f $2 ];then
echo "Error: Invalid log file path"
exit 1
fi

_date=$1
_logfile=$2
_backuptype=$3

_rawmessagebody=$(grep -A400 "$_date .*INFO: Starting" $_logfile)

# Exit if there are no logs for specified date
if [ $? -ne 0 ]; then
echo "ERROR: No logs found for specified date."
exit 1;
fi

if echo $_rawmessagebody | grep -q ERROR; then
_subjectline="$_backuptype Backup report: Errors found"
_messagebody1="There were errors during backup. Summary is provided below. Check $_logfile for a detailed report"
_messagebody2=$(echo "$_rawmessagebody" | grep "$_date .*ERROR:")
else
_subjectline="$_backuptype Backup report: No errors found"
_messagebody1="Backup successful. Summary is provided below. Check $_logfile for a detailed report"
_messagebody2=$(echo "$_rawmessagebody" | grep "$_date .*INFO:")
fi
#echo $_rawmessagebody

#Send email
echo -e "$_messagebody1\n\n$_messagebody2" | mailx -s "$_subjectline" "$_mailaddress"