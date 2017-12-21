#!/bin/bash
# Author: Pratap Raj
# Purpose: Perform incremental backups of Hive hdfs files to AWS S3 storage

############ User configuratble variables start - Edit as per your environment  #############
#############################################################################################
#NumDays is the number of days worth incremental data to process
NumDays=2

#HiveJDBCString is the JDBC connection string for beeline
HiveJDBCString=''

#HiveKeytabFile is the keytab file for hive user
HiveKeytabFile=''

#Log file to use for this script. Setting up this variable is important, as it is used by the email reporting script. Example: /var/log/hdfsbdrv2.log
LogFile='/var/log/hdfsbdrv2.log'

#_s3accesskey is the S3 bucket access key, obtained from AWS portal
_s3accesskey=''

#_s3secretkey is the S3 secret key, obtained from AWS portal
_s3secretkey=''

#Destination folder prefix in S3 where you need to copy HDFS folders to. Avoid preceding or trailing '/'. Example: hadoop-dr/hive
S3Prefix=''
#############################################################################################
############### User configurable variables end. DO NOT edit anything below ################

pushd $(dirname $0)

DBName=$1
BackupType=$2
MySQLReferenceTable=$3

function usagehelp {
echo "Script usage example:"
echo "$0 hivedbname full MySQLReferenceDB.ReferenceTable"
exit 1;
}

function CheckStatus {
if [ "$1" == "0" ]; then
 echo "$(date +%F\ %R) INFO: Operation $2 on $3 is successful" >> $LogFile
else
 echo "$(date +%F\ %R) ERROR: Operation $2 on $3 failed" >> $LogFile
fi
}

#Perform various validation. If any of these fail then the script will exit
kdestroy
if ! kinit -kt $HiveKeytabFile hive >> /dev/null;
then
 echo "$(date +%F\ %R) ERROR: Unable to get Kerberos credentials for hive user. Script will exit now" >> $LogFile
 exit 1;
fi

if [ "$#" != "3" ]; then
 echo "$(date +%F\ %R) ERROR: Number of supplied arguments $# is not equal to required number 2. Script will exit now" >> $LogFile
 usagehelp
fi

if [ ! -s "$DBName"".""$BackupType" ]; then
 echo "$(date +%F\ %R) ERROR: This script expects list of tables in file "$DBName"".""$BackupType" but could not find it. Exiting now" >> $LogFile
 usagehelp
fi

if ! mysql -e "desc $MySQLReferenceTable" >> /dev/null;
 then
 echo "$(date +%F\ %R) ERROR: Supplied reference table doesnt exist in MySQL. Script will exit now" >> $LogFile
 usagehelp
fi

#Start actual backup
case "$BackupType" in
"full" )
echo "$(date +%F\ %R) INFO: Starting a $BackupType backup" >> $LogFile
for TableName in `cat $DBName'.'{full,incremental}`
do
        HdfsPath=$(beeline -u "$HiveJDBCString" -e "describe formatted $DBName.$TableName"|grep 'Location:'|awk '{print $4}')
        CheckStatus "$?" "GetHdfsPathfromHiveMetadata" "$HdfsPath"
        HdfsRelativePath=${HdfsPath#*nameservice1}
        aws s3 rm --recursive "s3://$S3Prefix/latest/$DBName$HdfsRelativePath"
        CheckStatus "$?" "DeletePartitionFromS3" "s3://$S3Prefix/latest/$DBName$HdfsRelativePath"
        hadoop distcp -Dfs.s3a.server-side-encryption-algorithm=AES256 -Dfs.s3a.awsAccessKeyId="$_s3accesskey" -Dfs.s3a.awsSecretAccessKey="$_s3secretkey" -i -m5 "$HdfsPath" "s3a://$S3Prefix/latest/$DBName/$HdfsRelativePath"
        CheckStatus "$?" "HdfsDistcp" "$HdfsPath"
done
;;

"incremental" )
echo "$(date +%F\ %R) INFO: Starting an $BackupType backup" >> $LogFile
#Find Processed folders within date range
_date=$(date -d "$NumDays days ago" +%b\ %d)
_year=$(date +%Y)
StartId=$(mysql -N -s -e "select ID from $MySQLReferenceTable where PROCESS_DATE_TIME like '%$_date%$_year%' and STATUS='PROCESSED' limit 1;")
EndId=$(mysql -N -s -e "select max(ID) from $MySQLReferenceTable where STATUS='PROCESSED';")
ProcessDate=$(mysql -N -s -e "select FILE_DATE from $MySQLReferenceTable where STATUS='PROCESSED' and ID between $StartId and $EndId;"|sort -n|uniq|tr '\n' ' ')

for TableName in `cat $DBName'.'$BackupType`
do
 for j in `echo "$ProcessDate"|xargs`
 do
        HdfsPath=$(beeline -u "$HiveJDBCString" -e "describe formatted "$DBName".$TableName"|grep 'Location:'|awk '{print $4}')
        CheckStatus "$?" "GetHdfsPathfromHiveMetadata" "$HdfsPath"
        HdfsRelativePath=${HdfsPath#*nameservice1}
        if hadoop fs -ls "$HdfsPath/processeddate=$j" >> /dev/null;
        then
           hadoop fs -mkdir "s3a://$S3Prefix/latest/$DBName$HdfsRelativePath/processeddate=$j"
           hadoop distcp -Dfs.s3a.server-side-encryption-algorithm=AES256 -Dfs.s3a.awsAccessKeyId="$_s3accesskey" -Dfs.s3a.awsSecretAccessKey="$_s3secretkey" -overwrite -i -m5 "$HdfsPath/processeddate=$j" "s3a://$S3Prefix/latest/$DBName$HdfsRelativePath/processeddate=$j"
           CheckStatus "$?" "HdfsDistcp" "$HdfsPath/processeddate=$j"
        else
         echo "$(date +%F\ %R) WARN: "$HdfsPath/processeddate=$j" doesnt exist at source, hence skipping copy" >> $LogFile
        fi
 done
done
;;

* )
echo "Invalid option "$BackupType". Valid ones are full and incremental"
usagehelp
;;
esac
