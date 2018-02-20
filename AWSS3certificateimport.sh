#!/bin/bash
# Author: Pratap Raj
# Purpose: Check AWS S3 server side ertificate for changes. If new certificate is found, import it into Java keystore of all Hadoop nodes. This will prevent disctp and HBase BDR jobs from failing

################### User configuratble variables start ################

#_ansibleclustername is the hosts entry for the entire cluster, as per /etc/ansible/hosts
_ansibleclustername=cluster

#_mailrecipients is the comma seperated list of email addressres to ´send alerts to
_mailrecipients=''

#_s3bucketname is the name of the destination S3 bucket for your Hadoop backups
_s3bucketname=

#_keytoolbinary is the full path to the keytool binary. It will depend on the JAVA_HOME used by the Hadoop cluster.
_keytoolbinary="/usr/java/jdk1.7.0_67-cloudera/bin/keytool"

#_keystorefile is the Java keystore file that your hadoop cluster uses.
_keystorefile="/usr/java/jdk1.7.0_67-cloudera/jre/lib/security/jssecacerts"

#_keystorepassword is the password of your Java keystore file. default: changeit
_keystorepassword=changeit

################### User configuratble variables end  ################
################### Do NOT edit anything below   #####################
_oldmodulusfile=$(dirname $0)/s3.modulus
_outputfile=/tmp/awss3_`date +%F`

echo "" | openssl s_client -host $_s3bucketname".s3.amazonaws.com" -port 443 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > $_outputfile
_currentmodulus=$(openssl x509 -in $_outputfile -noout -modulus | openssl md5 | cut -d' ' -f2)
if [ "$_currentmodulus" != "$(cat $_oldmodulusfile)" ]; then
        ansible $_ansibleclustername -uclouderaadmin --become -m copy -a "src=$_outputfile dest=$_outputfile"
        ansible $_ansibleclustername -uclouderaadmin --become -m shell -a "$_keytoolbinary -importcert -trustcacerts -file $_outputfile -alias awss3_"$(date +%F)" -keystore $_keystorefile -storepass $_keystorepassword  -noprompt"
        if [ "$?" == "0" ]; then
                _messagebody="AWS S3 certificate has changed. New certificate has been successfully imported to Java Keystore. No further action required"
                echo "$_messagebody" | mailx -s "Alert: AWS S3 SSL certificate has changed" "$_mailrecipients"
        else
                _messagebody="AWS S3 certificate has changed but new certificate could not be imported to Java Keystore. Import the certificates manually ASAP to prevent the S3 backups from failing"
                echo "$_messagebody" | mailx -s "Critical: AWS S3 SSL certificate has changed" "$_mailrecipients"
        fi
else
        echo nochange
fi
echo $_currentmodulus > $_oldmodulusfile