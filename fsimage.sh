#! /bin/bash
#Author: Pratap Raj
#Purpose: Backup HDFS metadata to Amazon S3 for disaster recovery purpose.

############     User configuratble variables - Edit as per your environment    #############
#############################################################################################
#_localbackupdir is temporary storage directory for metadata, until it is pushed to S3
_localbackupdir=/backups/fsimage

#_s3bucketname is the name of the S3 bucket, obtained from AWS portal
_s3bucketname=""

#Destination folder prefix in S3 where you need to copy HDFS folders to. Avoid preceding or trailing '/'. Example: hdfs
_s3prefix="fsimage"

#_s3sse is the key details for S3 encryption
_s3sse='aws:kms'

#_s3region is the region name obtained from AWS portal
_s3region=''

#_namenodedir is the directory where fs image is stored. Obtained from HDFS configuration - dfs.namenode.name.dir
_namenodedir="/dfs/nn/current"

# _hdfskeytab should point to keytab file for hdfs user in a Kerberised cluster. If there is no kerberos leave this blank.
_hdfskeytab=""

#Log file to use for this script. Setting up this variable is important, as it is used by the email reporting script. Example: /var/log/hdfsbackup.log
_logfile="/var/log/hdfsbdr.log"
############### User configurable variables end. DO NOT edit anything below ################

# Script specific variables
_backuptype=$1
_date=$(date +%D)
_currentuser=$(whoami)
_namenodehostname=$(hdfs getconf -namenodes | awk '{print $2}' | xargs dig +short)

# Make sure that a valid argument is passed to script
if [ "$_backuptype" == "daily" -o "$_backuptype" == "weekly" ]; then
 echo "$(date +%D\ %R) INFO: Starting fsimage backup" >>$_logfile

 # Get hdfs keytab
 if [ -f "$_hdfskeytab" ];then
   echo "$(date +%D\ %R) INFO: Trying to acquire kerberos keytab for hdfs user" >> $_logfile
   kinit -kt "$_hdfskeytab" hdfs 2>>$_logfile
   if [ "$?" == "0" ]; then
    echo  "$(date +%D\ %R) INFO: Successfully acquired keytab for hdfs user" >> $_logfile
    else
    echo "$(date +%D\ %R) ERROR: Error while trying to acquire keytab for hdfs user" >> $_logfile
    exit 1
   fi
 fi

 # Backup version file
 ansible "$_namenodehostname" -u"$_currentuser" --become -m fetch -a "src=/dfs/nn/current/VERSION dest="$_localbackupdir"/ flat=yes" 2>> _$logfile

 # Backup fsimage
 hdfs dfsadmin -fetchImage "$_localbackupdir" 2>>$_logfile
 if [ "$?" != "0" ]; then
 echo "$(date +%D\ %R) ERROR: Could not dump fsimage" >> $_logfile
 exit 1;
 fi

 #Upload fsimage dump to AWS S3
 aws s3 sync --sse "$_s3sse" --region "$_s3region" "$_localbackupdir" s3://"$_s3bucketname"/"$_s3prefix"/"$_backuptype" --delete >> $_logfile
 if [ "$?" == "0" ]; then
  echo "$(date +%D\ %R) INFO: Uploaded fsimage to AWS S3 bucket" >> $_logfile
  aws s3 ls --summarize --human-readable --recursive s3://"$_s3bucketname"/"$_s3prefix"/"$_backuptype" |grep "$(date +%F)"|awk '{print "INFO: Size of "$NF, "in S3 bucket is", $(NF-2), $(NF-1)}' >> $_logfile
  find "$_localbackupdir" -type f -iname 'fsimage_*' -mtime +1 -delete
  else
  echo "$(date +%D\ %R) ERROR: Could not upload fsimage to AWS S3" >> $_logfile
 fi
 ######################################

else
 echo "$(date +%D\ %R) ERROR: Invalid argument passed to script, should have been either daily or weekly" >> $_logfile
 exit 1;
fi
