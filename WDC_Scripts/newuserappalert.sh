#!/bin/sh
# AUTHOR : Shashank Rathore
# Organization: Teradata
# Desctiption: This script is used to report any user query based upon configured thresholds for number of mappers, runtime, memory.
# Version : 01.01.00 : optimized for performance.
# Version : 02.01.00 : script has been modified to report memory usage for non pipeline users.
# Version : 03.00.01 : Script has been modified to send automated emails to users.

USER=svc-awor-bdppmon
TIME=`date +%s`
LOG_DIR=/var/log/userappalert
bold=$(tput bold)
normal=$(tput sgr0)
## JOB_TIME  value are in seconds i.e. 3600 is one hour.
#
#
JOB_TIME=7200

## MEM_TH is the memory threshold in MB's. 1000=1GB, 10000=10GB, 100000=1TB.
#
MEM_TH=1999999

## CONTACT email address you want to send mail to.
#
#
#CCCONTACT=abhay.patil@wdc.com,SHIGEYUKI.NAKAGAWA@wdc.com,fayaz.syed@wdc.com,Javier.Quiroz@wdc.com
#CCCONTACT=shashank.rathore@teradata.com
## Yarn Host where resource manager is running.
#
#
YARN_HOST=abo-lp-mstr04.wdc.com
MAPLIMIT=3000

send_alert()
{
sort $LOG_DIR/nb_usr.out|uniq | while read line
do
JOBUSER=`echo $line |awk '{print $2}'`
JOBID=`echo $line |awk '{print $4}'`
JOBTIME=$((`echo $line |awk '{print $3}'`/60))
JOBLINK=`echo $line |awk '{print $5}'`
JOBMEM=$(($(echo $line |awk '{print $1}')/1024))
USERMAIL=`mysql -uroot -pT3@Hgst -e "select email from hue.auth_user where username='$JOBUSER';"|grep -v email`
NAME=`mysql -uroot -pT3@Hgst -e "select first_name from hue.auth_user where username='$JOBUSER';"|grep -v name`
MAPS=`echo $line|awk '{print $6}'`
APPID=`echo $JOBLINK|cut -d "/" -f 5`
PROG=`ssh $USER@$YARN_HOST yarn application -status $APPID |grep Progress|awk '{print $3}'`

if [ "$JOBTIME" -le "10" ]; then
echo "skipping alert for job runtime< 10 min"
continue
else
echo "job time criteria met continue with further checks..."
fi

if [ "$(echo $PROG|cut -d "%" -f1)" -ge "80" ];then
        if [ "$JOBTIME" -ge 90 ]; then
        echo "job completed more than 80% within 90 mins, skip alert..."
        continue
        else
        echo "job running at $JOBTIME th min. and $PROG. Sending alert..."
        fi
else
echo "Job progress is less than 80: Alert will be sent"
fi


if [ -s $LOG_DIR/$JOBUSER ] ; then
echo "$LOG_DIR/$JOBUSER exists"
else
mkdir $LOG_DIR/$JOBUSER
fi

if [ -f $LOG_DIR/$JOBUSER/$JOBID ] ; then
echo "$LOG_DIR/$JOBUSER/$JOBID already saved, email will only be sent to support team"
CCCONTACT=Hang.Cui@Teradata.com
USERMAIL=
else
#touch $LOG_DIR/$JOBUSER/$JOBID
ssh -n $USER@$YARN_HOST hdfs dfs -cat /user/$JOBUSER/.staging/$JOBID/job.xml|sed -n '/hive.query.string/,/<\/value/p' |sed 's/<property><name>hive.query.string<\/name><value>//;s/<\/value><source>programatically<\/source><\/property>//;s/\\//' > $LOG_DIR/$JOBUSER/$JOBID
CCCONTACT=SHIGEYUKI.NAKAGAWA@wdc.com,fayaz.syed@wdc.com,Javier.Quiroz@wdc.com,Hang.Cui@Teradata.com,Suresh.Kumarappa@wdc.com
sleep 1
fi

echo -e "Hello $NAME,

Following job running under your user ID '$JOBUSER' has been reported as in-efficient, this job must be re-written/optimized to get the results more efficiently and quickly.
We request you to please stop this job as it is utilizing cluster resources and impacting other jobs and users.

Below are some recommendations for better performance and quick output for queries:
1. Review partitions used.
2. Restrict using select * from in your queries.
3. Please query required dataset only.
4. Please review partition information of table being queried before running your query.
5. Please close hue page or refresh your hue page after your work is complete, as it will gracefully close your impala session.
6. Do Not click refresh button on table list on hue this will run refresh metadata on all tables at once.
7. Please do manual test run of your queries before scheduling them.
8. Please check the number of mappers displayed on Hue Hive editor. If that is beyond 1000, cancel it and relook the query.

Below are your Job Details:
\tUSER ID:\t\t\t$JOBUSER
\tApp ID:\t\t\t\t$APPID
\tRun Time(min):\t\t\t$JOBTIME
\tMemory(GB):\t\t\t$JOBMEM
\tMappers Running:\t\t$MAPS
\tProgress:\t\t\t$PROG
\tResource Manager:\t\t$JOBLINK
\tJOB SQL:\t\t\tAnnexed



Here are some confluence links which provide more details on using partitions and more. 
https://confluence.hgst.com/display/BDP3/Data+Partition+Use+for+Efficient+Queries,
https://confluence.hgst.com/pages/viewpage.action?pageId=68762981
In case you find this alert to as false or concerning please drop an email on BDP.support@wdc.com with your concern and we will support you with your concern.

This is an autogenerated email.

Regards,
BDP Platform Support Team
email: BDP.support@wdc.com

User SQL Query:
$(cat $LOG_DIR/$JOBUSER/$JOBID)

Note: cannot fetch sql if this application is running from Oozie.
"|mailx -S smtp="10.86.1.25:25" -r no-reply@wdc.com -c $CCCONTACT -s "Query Optimization Alert" $USERMAIL HM230067@Teradata.com
echo "email sent to $CCCONTACT $USERMAIL HM230067@Teradata.com"
sleep 2
done
}


#ssh $USER@$YARN_HOST kinit -kt /home/$USER/svc-AWOR-bdppmon.keytab svc-AWOR-bdppmon@HITACHIGST.GLOBAL
#ssh $USER@$YARN_HOST mapred job -list |grep -v "bdppapp\|usrnpc\|usrnpe\|usrnpx"|grep "RUNNING"|awk '{print $9,$4,$3,$1, $12}'|sed 's/M//'|sort -nr> $LOG_DIR/joblist
ssh $USER@$YARN_HOST mapred job -list |grep -v "bdppapp"|grep "RUNNING"|awk '{print $9,$4,$3,$1, $12}'|sed 's/M//'|sort -nr> $LOG_DIR/joblist

cat $LOG_DIR/joblist|while read line
        do
        id=`echo $line |awk '{print $4}'`
        maps=`ssh -n $USER@$YARN_HOST mapred job -status $id 2>/dev/null |grep "Launched map tasks"|cut -d "=" -f2`
#        echo "$line $maps"|tee -a $LOG_DIR/mappers.out
        echo "$line $maps" >> $LOG_DIR/mappers.out
        done

if [ -s $LOG_DIR/mappers.out ]; then
        TIME=`date +%s`
#Checking for jobs running against time threshold
        awk '$1, $3='$TIME' - substr($3,0,10) {print}' $LOG_DIR/mappers.out |awk '$3 > '$JOB_TIME' {print}'|tee -a $LOG_DIR/nb_usr.out
#Checking for jobs running with high memory.
        awk '$1 > '$MEM_TH', $3='$TIME' - substr($3,0,10) {print}' $LOG_DIR/mappers.out|tee -a $LOG_DIR/nb_usr.out
#Checking for jobs against mapper threshold. 
	awk '$6>'$MAPLIMIT', $3='$TIME' - substr($3,0,10) {print}' $LOG_DIR/mappers.out|	tee -a $LOG_DIR/nb_usr.out
#sort -n $LOG_DIR/nb_usr.out|uniq -u 
	if [ -s $LOG_DIR/nb_usr.out ]; then
        send_alert
	else
	echo "no jobs found above threshold"
	cat $LOG_DIR/nb_usr.out
	exit 0;
	fi
else
	echo "Dint find any user jobs running."
	cat $LOG_DIR/nb_usr.out
        exit 0;
fi

cat /dev/null > $LOG_DIR/mappers.out
cat /dev/null> $LOG_DIR/nb_usr.outfi