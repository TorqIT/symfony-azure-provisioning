param containerAppName string
param generalMetricAlertsActionGroupName string

module replicaRestartAlerts './container-app-restarts-alerts.bicep' = {
  name: '${containerAppName}-restarts-alerts'
  params: {
    containerAppName: containerAppName
    generalMetricAlertsActionGroupName: generalMetricAlertsActionGroupName
  }
}
