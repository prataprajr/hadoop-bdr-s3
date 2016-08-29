#!/bin/bash
# Author: Pratap Raj
# Purpose: Backup MySQL and PostgresSQL database dumps to Amazon S3 for Disaster recovery
# Retention period: 1 daily, 2 weekly

############     User configuratble variables - Edit as per your environment    #############
#############################################################################################
#Email preference. Enter the absolute path to email reporting script(default is backupreport.sh) if you want to email backup reports
_backupreport=backupreport.sh

#_mysqllocal is temporary storage directory for MySQL dumps, until it is pushed to S3
_mysqllocal=/backups/mysql

#_postgresqllocal is temporary storage directory for PostgreSQL dumps, until it is pushed to S3
_postgresqllocal=/backups/postgresql

#Log file to use for this script. Setting up this variable is important, as it is used by the email reporting script. Example: /var/log/hdfsbackup.log
_logfile=/var/log/sqlbdr.log

#_mysqldblist is list of MySQL databases to be backed up, separated by space. eg: db1 db2 db3
_mysqldblist="hive mysql oozie sentry"

#_postgresqldblist is list of PostgreSQL databases to be backed up, separated by space. eg: db1 db2 db3
_postgresqldblist="amon nav navms scm"

#_s3bucketname is the name of the S3 bucket, obtained from AWS portal
_s3bucketname=""

#_s3sse is the key details for S3 encryption
_s3sse='"$_s3sse"'

#_s3region is the region name obtained from AWS portal
_s3region=''
############### User configurable variables end. DO NOT edit anything below ################

umask=117
_date=$(date +%D)
_backuptype=$1


# Make sure that a valid argument is passed to script
if [ "$_backuptype" == "daily" -o "$_backuptype" == "weekly" ]; then

echo "$(date +%D\ %R) INFO: Starting SQL backups" >>$_logfile

# Start MySQL dump
# Pre-requisite: Well formatted ~/.my.cnf file
echo  "$(date +%D\ %R) INFO: Starting MySQL backups" >> $_logfile
for i in `echo "$_mysqldblist"`
do
mysqldump --add-drop-database $i > $_mysqllocal/$i.`date +%F`.sql 2>> $_logfile
if [ "$?" == "0" ];then
 echo "$(date +%D\ %R) INFO: Backup of database $i is successful" >> $_logfile
 else
 echo "$(date +%D\ %R) ERROR: Backup of database $i failed" >> $_logfile
fi
done


# Start PostgreSQL dump
# pre-requisite: Well formatted ~/.pgpass file
echo "$(date +%D\ %R) INFO: Starting PostgreSQL backups" >> $_logfile
for i in `echo "$_postgresqldblist"`
do
pg_dump -p7432 -hlocalhost -Ucloudera-scm $i > $_postgresqllocal/$i.`date +%F`.sql 2>> $_logfile
if [ "$?" == "0" ];then
 echo "$(date +%D\ %R) INFO: Backup of database $i is successful" >> $_logfile
 else
 echo "$(date +%D\ %R) ERROR: Backup of database $i failed" >> $_logfile
fi
done

# If type is weekly, then split into odd and even weeks
if [ "$_backuptype" == "weekly" ]; then
        _weeknum=$((($(date +%-d)-1)/7+1))
        if ((_weeknum % 2)); then
                _backuptype=oddweek
        else
                _backuptype=evenweek
        fi
fi

# Upload to S3
echo "$(date +%D\ %R) INFO: Uploading MySQL dumps to S3" >> $_logfile
aws s3 sync --sse "$_s3sse" --region "$_s3region" $_mysqllocal s3://"$_s3bucketname"/mysql/$_backuptype --delete >>$_logfile
if [ $? -eq 0 ]; then
                echo  "$(date +%D\ %R) INFO: Upload of MySQL database dumps to S3 is successful" >> $_logfile
                aws s3 ls --summarize --human-readable s3://"$_s3bucketname"/mysql/$_backuptype --recursive |grep "$(date +%F)"|awk -v _datetime="$(date +%D\ %R)" '{print _datetime,"INFO: Size of "$NF, "in S3 bucket is",  $(NF-2), $(NF -1)}' >> $_logfile
                else
                echo "$(date +%D\ %R) ERROR: Error in backup" >> $_logfile
        fi
echo "$(date +%D\ %R) INFO: Deleting local MySQL dumps" >> $_logfile
find $_mysqllocal -type f -iname '*.sql' -mtime +2 -delete

echo "$(date +%D\ %R) INFO: Uploading PostgreSQL dumps to S3" >> $_logfile
aws s3 sync --sse "$_s3sse" --region "$_s3region" $_postgresqllocal s3://"$_s3bucketname"/postgresql/$_backuptype --delete >>$_logfile
if [ $? -eq 0 ]; then
                echo  "$(date +%D\ %R) INFO: Upload of PostgreSQL database dumps to S3 is successful" >> $_logfile
                aws s3 ls --summarize --human-readable s3://"$_s3bucketname"/postgresql/$_backuptype --recursive |grep "$(date +%F)"|awk -v _datetime="$(date +%D\ %R)" '{print _datetime,"INFO: Size of "$NF, "in S3 bucket is",  $(NF-2), $(NF -1)}' >> $_logfile
                else
                echo "$(date +%D\ %R) ERROR: Error in backup" >> $_logfile
        fi
echo "$(date +%D\ %R) INFO: Deleting local PostgreSQL dumps" >> $_logfile
find $_postgresqllocal -type f -iname '*.sql' -mtime +2 -delete


#Send backup report as email if a mail script is specified
 if [ -f $_backupreportscript ];then
   bash $_backupreport "$_date" "$_logfile" "SQLBDR"
 fi


else
echo "$(date +%D\ %R) ERROR: Invalid argument passed to script, should have been either daily or weekly" >> $_logfile
exit 1;
fi
