# Sending notifications for Healthcheck failures in Oracle Cloud

This sample script (healthcheck-notify.sh) has been developed to leverage on Oracle Cloud Notification API for sending automated alerts when an Healthcheck probe (either PING or HTTP) fails.

# API used
* Notification API: [PublishMessage](https://docs.cloud.oracle.com/iaas/api/#/en/notification/20181201/NotificationTopic/PublishMessage) has been used to publish a message to subscribers of a pre-existing topic
* Healthcheck API: [ListHttpProbeResults](https://docs.cloud.oracle.com/iaas/api/#/en/healthchecks/20180501/HttpProbeResultSummary/ListHttpProbeResults) and [ListPingProbeResults](https://docs.cloud.oracle.com/iaas/api/#/en/healthchecks/20180501/PingProbeResultSummary/ListPingProbeResults) have been used to retrieve the latest status of PING (the former) and HTTP (the latter) pre-existing probes

# Prerequisites
* An Healthcheck probe (either PING or HTTP) - see https://docs.cloud.oracle.com/iaas/Content/HealthChecks/Tasks/managinghealthchecks.htm#console for creating a new probe using Oracle Cloud Console. This is the probe used to monitor a resource, which can be either on Oracle Cloud or on-premise
* A Notification topic - see https://docs.cloud.oracle.com/iaas/Content/Notification/Tasks/managingtopicsandsubscriptions.htm#createTopic for creating a new topic using Oracle Cloud Console. This is the topic used to send notifications to its subscribers
* An Oracle Linux 7 machine - this is the machine used to run the healthcheck-notify.sh script

# Usage
* Clone this repo
* Edit the variables in the "TODO" section
* Make healthcheck-notify.sh executable: chmod u+x healthcheck-notify.sh
* Run healthcheck-notify.sh in the background: nohup ./healthcheck-notify.sh &

