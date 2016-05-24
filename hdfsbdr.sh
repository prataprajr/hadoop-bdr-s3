#! /bin/bash
#Author: Pratap Raj
#Purpose: Backup critical HDFS data to AWS S3 for disaster recovery purpose

############     User configuratble variables - Edit as per your environment    #############
#############################################################################################
#_backupfilelist is a text file that contains the list of HDFS directories to backup. Avoid trailing '/'. Example: /etc/hdfsbackup.list
_backupfilelist=""

#_nameservice should be set if you have HA enabled for your namenode. In a Cloudera environment default value is nameservice1
#Run this command to find out:  # hdfs getconf -confKey dfs.nameservices
_nameservice=""

# _hdfskeytab should point to keytab file for hdfs user in a Kerberised cluster. If there is no kerberos leave this blank.
_hdfskeytab=""

#_s3bucketname is the name of the S3 bucket, obtained from AWS portal
_s3bucketname=""

#_s3accesskey is the S3 bucket access key, obtained from AWS portal
_s3accesskey=''

#_s3secretkey is the S3 secret key, obtained from AWS portal
_s3secretkey=''

#Destination folder prefix in S3 where you need to copy HDFS folders to. Avoid preceding or trailing '/'. Example: hdfs
_s3prefix=""

#Log file to use for this script. Setting up this variable is important, as it is used by the email reporting script. Example: /var/log/hdfsbackup.log
_logfile=""

#Email preference. Enter the absolute path to email reporting script(default is backupreport.sh) if you want to email backup reports
_backupreportscript=""
############### User configurable variables end. DO NOT edit anything below ################

# Script specific variables
_backuptype=$1
_date=$(date +%D)
_lockfile=/tmp/HdfsBackuplock.txt

# Make sure that a valid argument is passed to script
if [ "$_backuptype" == "daily" -o "$_backuptype" == "weekly" ]; then
 echo "$(date +%D\ %R) INFO: Starting HDFS backup" >>$_logfile

 # Make sure only one instance of distcp is running
 if [ -e ${_lockfile} ] && kill -0 `cat ${_lockfile}`; then   #check pid of previous distcp
    echo "$(date +%D\ %R) ERROR: BDR is already running. Will exit now" >> $_logfile
    exit 1;
 fi

 # Make sure the lockfile is removed upon exit
 trap "rm -f ${_lockfile}; exit" INT TERM EXIT
 echo $$ > ${_lockfile}

 # Get hdfs keytab
 if [ -f "$_hdfskeytab" ];then
   echo "$(date +%D\ %R) INFO: Trying to acquire kerberos keytab for hdfs user"
   kinit -kt "$_hdfskeytab" hdfs 2>>$_logfile
   if [ "$?" == "0" ]; then
    echo  "$(date +%D\ %R) INFO: Successfully acquired keytab for hdfs user" >> $_logfile
    else
    echo "$(date +%D\ %R) ERROR: Error while trying to acquire keytab for hdfs user" >> $_logfile
    exit 1
   fi
 fi
 
 # If backup type is weekly, then split into odd and even weeks. This is to ensure that we have 2 weekly backups at any point of time
 if [ "$_backuptype" == "weekly" ]; then
        _weeknum=$((($(date +%-d)-1)/7+1))
        if ((_weeknum % 2)); then
                _backuptype=oddweek
        else
                _backuptype=evenweek
        fi
 fi

 for i in `cat "$_backupfilelist"`
        do
        hadoop distcp  -Dfs.s3a.awsAccessKeyId="$_s3accesskey" -Dfs.s3a.awsSecretAccessKey="$_s3secretkey" -update -delete hdfs://"$_nameservice""$i" s3a://"$_s3bucketname"/"$_s3prefix"/$_backuptype${i} 2>> $_logfile
        if [ "$?" == "0" ]; then
         echo  "$(date +%D\ %R) INFO: Backup of $i successful" >> $_logfile
         else
         echo "$(date +%D\ %R) ERROR: Error during backup of $i" >> $_logfile
        fi
 done
 rm -f ${_lockfile}
 ######################################

 #Send backup report as email if a mail script is specified
 if [ -f $_backupreportscript ];then
   bash $_backupreportscript "$_date" "$_logfile" "HdfsBackup"
 fi
else
 echo "$(date +%D\ %R) ERROR: Invalid argument passed to script, should have been either daily or weekly" >> $_logfile
 exit 1;
fi
