# hadoop
Hadoop cluster administration scripts

##Introduction
This script lets you backup important HDFS folders to Amazon S3 storage. The highlights are:
 - Considerable savings on cost as you dont need to build a new hadoop cluster for backup.
 - S3 storage can be in a different geographic region, thereby facilitating disaster recovery backups.
 - Email alerts with 'pretty' summary so you dont have to read entire log file to find out if a backup was successful

##Pre-requisites
 - You must purchase an S3 bucket via Amazon
 - Hadoop cluster with an edge node running on any Hadoop compatible Linux Operating system
 - Install the following packages in your edge node(or wherever the script is running):
   * mailx
   * aws cli  (http://docs.aws.amazon.com/cli/latest/userguide/installing.html)  
      
##List of Scripts
 - hdfsbdr.sh
 - backupreport.sh

##Usage
 - Open script file 'hdfsbdr.sh' and edit values under the section 'User configurable variables'
 - Create a logfile and backupfilelist as per the variables you set in step #1
 - Open script file 'backupreport.sh' and edit values under the section 'User configurable variables'
 - Execute the script:
```sh
./hdfsbdr.sh daily
./hdfsbdr.sh weekly
```

##Automation
Once manual testing of script is successful, you can automate Disaster recovery backups via cronjobs:
```sh 
00 01 * * 1,2,3,4,5,6 bash /var/lib/hadoop-hdfs/scripts/hdfsbdr.sh daily
00 01 * * 7 bash /var/lib/hadoop-hdfs/scripts/hdfsbdr.sh weekly
```
