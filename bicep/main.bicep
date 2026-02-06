param location string = resourceGroup().location

@description('Whether to fully provision the environment. If set to false, some longer steps will be assumed to already be provisioned and will be skipped to speed up the process.')
param fullProvision bool = true

// Virtual Network
param virtualNetworkName string
param virtualNetworkAddressSpace string = '10.0.0.0/16'
// If set to a value other than the Resource Group used for the rest of the resources, the VNet will be assumed to already exist in that Resource Group
param virtualNetworkResourceGroupName string = resourceGroup().name
param virtualNetworkContainerAppsSubnetName string = 'container-apps'
param virtualNetworkContainerAppsSubnetAddressSpace string = '10.0.0.0/23'
param virtualNetworkPrivateEndpointsSubnetName string = 'private-endpoints'
param virtualNetworkPrivateEndpointsSubnetAddressSpace string = '10.0.2.0/28'
module virtualNetwork 'virtual-network/virtual-network.bicep' = if (fullProvision && virtualNetworkResourceGroupName == resourceGroup().name) {
  name: 'virtual-network'
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    virtualNetworkAddressSpace: virtualNetworkAddressSpace
    containerAppsSubnetName: virtualNetworkContainerAppsSubnetName
    containerAppsSubnetAddressSpace:  virtualNetworkContainerAppsSubnetAddressSpace
    containerAppsEnvironmentUseWorkloadProfiles: containerAppsEnvironmentUseWorkloadProfiles
    privateEndpointsSubnetName: virtualNetworkPrivateEndpointsSubnetName
    privateEndpointsSubnetAddressSpace: virtualNetworkPrivateEndpointsSubnetAddressSpace
    // Optional services VM provisioning (see configuration below)
    provisionServicesVM: provisionServicesVM
    servicesVmSubnetName: servicesVmSubnetName
    servicesVmSubnetAddressSpace: servicesVmSubnetAddressSpace
  }
}

// Key Vault
param keyVaultName string
// If set to a value other than the Resource Group used for the rest of the resources, the Key Vault will be assumed to already exist in that Resource Group
param keyVaultResourceGroupName string = resourceGroup().name
param keyVaultEnablePurgeProtection bool = true
module keyVaultModule './key-vault/key-vault.bicep' = if (fullProvision && keyVaultResourceGroupName == resourceGroup().name) {
  name: 'key-vault'
  dependsOn: [virtualNetwork]
  params: {
    location: location
    name: keyVaultName
    virtualNetworkResourceGroupName: virtualNetworkResourceGroupName
    virtualNetworkName: virtualNetworkName
    virtualNetworkContainerAppsSubnetName: virtualNetworkContainerAppsSubnetName
    enablePurgeProtection: keyVaultEnablePurgeProtection
  }
}
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultResourceGroupName)
}

param privateDnsZonesResourceGroupName string = resourceGroup().name
param privateDnsZoneForDatabaseName string = 'privatelink.mysql.database.azure.com'
param privateDnsZoneForStorageAccountsName string = 'privatelink.blob.${environment().suffixes.storage}'
module privateDnsZones './private-dns-zones/private-dns-zones.bicep' = if (fullProvision) {
  name: 'private-dns-zones'
  dependsOn: [virtualNetwork]
  params:{
    privateDnsZonesResourceGroupName: privateDnsZonesResourceGroupName
    virtualNetworkName: virtualNetworkName
    virtualNetworkResourceGroupName: virtualNetworkResourceGroupName
    provisionZoneForContainerRegistry: containerRegistrySku == 'Premium' // Private VNet integration is currently only possible on Premium tier Container Registries
  }
}

// Container Registry
param containerRegistryName string
param containerRegistrySku string = ''
param containerRegistryFirewallIps array = []
param containerRegistryPrivateEndpointName string = '${containerRegistryName}-private-endpoint'
param containerRegistryPrivateEndpointNicName string = ''
module containerRegistry './container-registry/container-registry.bicep' = if (fullProvision) {
  name: 'container-registry'
  dependsOn: [virtualNetwork]
  params: {
    location: location
    containerRegistryName: containerRegistryName
    sku: containerRegistrySku
    firewallIps: containerRegistryFirewallIps
    privateDnsZoneId:privateDnsZones.outputs.zoneIdForContainerRegistry
    privateEndpointName: containerRegistryPrivateEndpointName
    privateEndpointNicName: containerRegistryPrivateEndpointNicName
    virtualNetworkName: virtualNetworkName
    virtualNetworkResourceGroupName: virtualNetworkResourceGroupName
    virtualNetworkSubnetName: virtualNetworkPrivateEndpointsSubnetName
  }
}

// Backup Vault
param backupVaultName string = '${resourceGroupName}-backup-vault'
module backupVault 'backup-vault/backup-vault.bicep' = if (fullProvision && storageAccountLongTermBackups) {
  name: 'backup-vault'
  params: {
    name: backupVaultName
  }
}

// Storage Account
param storageAccountName string
param storageAccountSku string = 'Standard_LRS'
param storageAccountKind string = 'StorageV2'
param storageAccountAccessTier string = 'Hot'
param storageAccountContainerName string = 'symfony'
param storageAccountAdditionalFileShares array = []
param storageAccountFirewallIps array = []
param storageAccountBackupRetentionDays int = 7
param storageAccountPrivateEndpointName string = '${storageAccountName}-private-endpoint'
param storageAccountPrivateEndpointNicName string = ''
param storageAccountLongTermBackups bool = true
param storageAccountLongTermBackupRetentionPeriod string = 'P365D'
module storageAccount 'storage-account/storage-account.bicep' = {
  name: 'storage-account'
  dependsOn: [virtualNetwork, backupVault]
  params: {
    location: location
    fullProvision: fullProvision
    storageAccountName: storageAccountName
    containerName: storageAccountContainerName
    accessTier: storageAccountAccessTier
    kind: storageAccountKind
    sku: storageAccountSku
    firewallIps: storageAccountFirewallIps
    virtualNetworkName: virtualNetworkName
    virtualNetworkContainerAppsSubnetName: virtualNetworkContainerAppsSubnetName
    virtualNetworkPrivateEndpointSubnetName: virtualNetworkPrivateEndpointsSubnetName
    virtualNetworkResourceGroupName: virtualNetworkResourceGroupName
    shortTermBackupRetentionDays: storageAccountBackupRetentionDays
    privateDnsZoneId: privateDnsZones.outputs.zoneIdForStorageAccounts
    privateEndpointName: storageAccountPrivateEndpointName
    privateEndpointNicName: storageAccountPrivateEndpointNicName
    longTermBackups: storageAccountLongTermBackups
    backupVaultName: backupVaultName
    longTermBackupRetentionPeriod: storageAccountLongTermBackupRetentionPeriod
    additionalFileShares: storageAccountAdditionalFileShares
  }
}

// Optional Azure Files-based Storage Account for use as volume mounts in Container Apps (leveraging NFS)
param fileStorageAccountName string = ''
param fileStorageAccountSku string = 'Premium_LRS'
param fileStorageAccountFileShares array = []
module fileStorage './file-storage/file-storage.bicep' = if (fullProvision && !empty(fileStorageAccountName)) {
  name: 'file-storage-account'
  dependsOn: [virtualNetwork]
  params: {
    location: location
    storageAccountName: fileStorageAccountName
    storageAccountSku: fileStorageAccountSku
    fileShares: map(fileStorageAccountFileShares, (fileShare => {
      name: fileShare.name
      maxSizeGB: fileShare.maxSizeGB
    }))
    virtualNetworkName: virtualNetworkName
    virtualNetworkResourceGroupName: virtualNetworkResourceGroupName
    virtualNetworkSubnetName: virtualNetworkContainerAppsSubnetName
  }
}

// Metric alerts
param provisionMetricAlerts bool = false
param generalMetricAlertsActionGroupName string = '${resourceGroupName}-general-metric-alerts-group'
@maxLength(12)
param generalMetricAlertsActionGroupShortName string = 'gen-metrics'
param generalMetricAlertsEmailReceivers array = []
module generalMetricAlertsActionGroup 'insights/metric-alerts/metrics-action-group.bicep' = if (provisionMetricAlerts) {
  name: 'general-metric-alerts-action-group'
  params: {
    name: generalMetricAlertsActionGroupName
    shortName: generalMetricAlertsActionGroupShortName
    emailReceivers: generalMetricAlertsEmailReceivers
  }
}
param criticalMetricAlertsActionGroupName string = '${resourceGroupName}-critical-metric-alerts-group'
@maxLength(12)
param criticalMetricAlertsActionGroupShortName string = 'crit-metrics'
param criticalMetricAlertsEmailReceivers array = []
module criticalMetricAlertsActionGroup 'insights/metric-alerts/metrics-action-group.bicep' = if (provisionMetricAlerts) {
  name: 'critical-metric-alerts-action-group'
  params: {
    name: criticalMetricAlertsActionGroupName
    shortName: criticalMetricAlertsActionGroupShortName
    emailReceivers: criticalMetricAlertsEmailReceivers
  }
}

// Database
param skipDatabase bool = false
param databaseServerName string
param databaseServerVersion string = '8.4'
param databaseAdminUsername string = 'adminuser'
param databasePasswordSecretName string = 'databasePassword'
param databaseSkuName string = 'Standard_B2s'
param databaseSkuTier string = 'Burstable'
param databaseStorageSizeGB int = 20
param databaseName string = 'app'
param databaseShortTermBackupRetentionDays int = 7
param databaseGeoRedundantBackup bool = false
param databaseLongTermBackups bool = false
// param databaseLongTermBackupRetentionPeriod string = 'P365D'
param databaseBackupsStorageAccountName string = ''
param databaseBackupsStorageAccountSku string = 'Standard_LRS'
param databaseBackupsStorageAccountKind string = 'StorageV2'
param databaseBackupsStorageAccountContainerName string = 'database'
param databasePrivateEndpointName string = '${databaseServerName}-private-endpoint'
module database 'database/database.bicep' = if (!skipDatabase) {
  name: 'database'
  dependsOn: [virtualNetwork, backupVault, generalMetricAlertsActionGroup, criticalMetricAlertsActionGroup]
  params: {
    location: location
    fullProvision: fullProvision
    administratorLogin: databaseAdminUsername
    administratorPassword: keyVault.getSecret(databasePasswordSecretName)
    databaseName: databaseName
    serverName: databaseServerName
    serverVersion: databaseServerVersion
    skuName: databaseSkuName
    skuTier: databaseSkuTier
    storageSizeGB: databaseStorageSizeGB
    virtualNetworkName: virtualNetworkName
    virtualNetworkResourceGroupName: virtualNetworkResourceGroupName
    virtualNetworkPrivateEndpointsSubnetName: virtualNetworkPrivateEndpointsSubnetName
    shortTermBackupRetentionDays: databaseShortTermBackupRetentionDays
    geoRedundantBackup: databaseGeoRedundantBackup
    privateDnsZoneForDatabaseId: privateDnsZones.outputs.zoneIdForDatabase
    privateEndpointName: databasePrivateEndpointName

    // Optional long-term backups
    longTermBackups: databaseLongTermBackups
    databaseBackupsStorageAccountName: databaseBackupsStorageAccountName
    databaseBackupsStorageAccountContainerName: databaseBackupsStorageAccountContainerName
    databaseBackupsStorageAccountKind: databaseBackupsStorageAccountKind
    databaseBackupsStorageAccountSku: databaseBackupsStorageAccountSku

    // Optional metrics alerts
    provisionMetricAlerts: provisionMetricAlerts
    generalMetricAlertsActionGroupName: generalMetricAlertsActionGroupName
    criticalMetricAlertsActionGroupName: criticalMetricAlertsActionGroupName
  }
}

param logAnalyticsWorkspaceName string = '${resourceGroupName}-log-analytics'
module logAnalyticsWorkspace 'log-analytics-workspace/log-analytics-workspace.bicep' = {
  name: 'log-analytics-workspace'
  params: {
    location: location
    name: logAnalyticsWorkspaceName
  }
}

// Container Apps
param containerAppsEnvironmentName string
param containerAppsEnvironmentUseWorkloadProfiles bool = false
param containerAppsManagedIdentityName string = '${resourceGroup().name}-container-app-managed-id'
// Init Container App Job
param initContainerAppJobName string = ''
param initContainerAppJobImageName string = 'init'
param initContainerAppJobCpuCores string = '1.5'
param initContainerAppJobMemory string = '3Gi'
param initContainerAppJobReplicaTimeoutSeconds int = 600
// PHP ("web") Container App 
param phpContainerAppExternal bool = true
param phpContainerAppName string
param phpContainerAppImageName string = 'php'
param phpContainerAppUseProbes bool = false
param phpContainerAppCustomDomains array = []
param phpContainerAppCpuCores string = '1.5'
param phpContainerAppMemory string = '3Gi'
param phpContainerAppMinReplicas int = 1
param phpContainerAppMaxReplicas int = 1
param phpContainerAppIpSecurityRestrictions array = []
// Optional scaling rules
param phpContainerAppProvisionHttpScaleRule bool = true
param phpContainerAppHttpScaleRuleConcurrentRequestsThreshold int = 20
param phpContainerAppProvisionCronScaleRule bool = false
param phpContainerAppCronScaleRuleDesiredReplicas int = 1
param phpContainerAppCronScaleRuleStartSchedule string = ''
param phpContainerAppCronScaleRuleEndSchedule string = ''
param phpContainerAppCronScaleRuleTimezone string = ''
// Supervisord Container App
param provisionSupervisordContainerApp bool = false
param supervisordContainerAppName string = ''
param supervisordContainerAppImageName string = 'supervisord'
param supervisordContainerAppCpuCores string = '1'
param supervisordContainerAppMemory string = '2Gi'
// Symfony runtime variables
@allowed(['0', '1'])
param appDebug string
param appEnv string
// Environment variables and secrets
param additionalEnvVars array = []
param additionalSecrets array = []
// Volume mounts
param additionalVolumesAndMounts array = []
module containerApps 'container-apps/container-apps.bicep' = {
  name: 'container-apps'
  dependsOn: [virtualNetwork, containerRegistry, logAnalyticsWorkspace, storageAccount, fileStorage, generalMetricAlertsActionGroup, criticalMetricAlertsActionGroup]
  params: {
    location: location
    fullProvision: fullProvision
    additionalEnvVars: additionalEnvVars
    additionalSecrets: additionalSecrets
    additionalVolumesAndMounts: additionalVolumesAndMounts
    appDebug: appDebug
    appEnv: appEnv
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerAppsEnvironmentUseWorkloadProfiles: containerAppsEnvironmentUseWorkloadProfiles
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    containerRegistryName: containerRegistryName
    keyVaultName: keyVaultName
    managedIdentityName: containerAppsManagedIdentityName
    databaseName: databaseName
    databasePasswordSecretNameInKeyVault: databasePasswordSecretName
    databaseServerName: databaseServerName
    databaseServerVersion: databaseServerVersion
    databaseUser: databaseAdminUsername
    initContainerAppJobName: initContainerAppJobName
    initContainerAppJobImageName: initContainerAppJobImageName
    initContainerAppJobCpuCores: initContainerAppJobCpuCores
    initContainerAppJobMemory: initContainerAppJobMemory
    initContainerAppJobReplicaTimeoutSeconds: initContainerAppJobReplicaTimeoutSeconds
    phpContainerAppName: phpContainerAppName
    phpContainerAppCustomDomains: phpContainerAppCustomDomains
    phpContainerAppImageName: phpContainerAppImageName
    phpContainerAppCpuCores: phpContainerAppCpuCores
    phpContainerAppMemory: phpContainerAppMemory
    phpContainerAppExternal: phpContainerAppExternal
    phpContainerAppUseProbes: phpContainerAppUseProbes
    phpContainerAppMinReplicas: phpContainerAppMinReplicas
    phpContainerAppMaxReplicas: phpContainerAppMaxReplicas
    phpContainerAppIpSecurityRestrictions: phpContainerAppIpSecurityRestrictions
    storageAccountContainerName: storageAccountContainerName
    storageAccountName: storageAccountName
    provisionSupervisordContainerApp: provisionSupervisordContainerApp
    supervisordContainerAppName: supervisordContainerAppName
    supervisordContainerAppImageName: supervisordContainerAppImageName
    supervisordContainerAppCpuCores: supervisordContainerAppCpuCores
    supervisordContainerAppMemory: supervisordContainerAppMemory
    virtualNetworkName: virtualNetworkName
    virtualNetworkSubnetName: virtualNetworkContainerAppsSubnetName
    virtualNetworkResourceGroup: virtualNetworkResourceGroupName

    // Optional alerts provisioning
    provisionMetricAlerts: provisionMetricAlerts
    generalMetricAlertsActionGroupName: generalMetricAlertsActionGroupName
    criticalMetricAlertsActionGroupName: criticalMetricAlertsActionGroupName

    // Optional scaling rules
    phpContainerAppProvisionHttpScaleRule: phpContainerAppProvisionHttpScaleRule
    phpContainerAppHttpScaleRuleConcurrentRequestsThreshold: phpContainerAppHttpScaleRuleConcurrentRequestsThreshold
    phpContainerAppProvisionCronScaleRule: phpContainerAppProvisionCronScaleRule
    phpContainerAppCronScaleRuleDesiredReplicas: phpContainerAppCronScaleRuleDesiredReplicas
    phpContainerAppCronScaleRuleStartSchedule: phpContainerAppCronScaleRuleStartSchedule
    phpContainerAppCronScaleRuleEndSchedule: phpContainerAppCronScaleRuleEndSchedule
    phpContainerAppCronScaleRuleTimezone: phpContainerAppCronScaleRuleTimezone
  }
}

// Optional Virtual Machine for running side services
param provisionServicesVM bool = false
param servicesVmName string = ''
param servicesVmSubnetName string = 'services-vm'
param servicesVmSubnetAddressSpace string = '10.0.3.0/29'
param servicesVmAdminUsername string = 'azureuser'
param servicesVmPublicKeyKeyVaultSecretName string = 'services-vm-public-key'
param servicesVmSize string = 'Standard_B2s'
param servicesVmUbuntuOSVersion string = 'Ubuntu-2204'
param servicesVmFirewallIpsForSsh array = []
module servicesVm './services-virtual-machine/services-virtual-machine.bicep' = if (fullProvision && provisionServicesVM) {
  name: 'services-virtual-machine'
  dependsOn: [virtualNetwork]
  params: {
    location: location
    name: servicesVmName
    adminPublicSshKey: keyVault.getSecret(servicesVmPublicKeyKeyVaultSecretName)
    adminUsername: servicesVmAdminUsername
    size: servicesVmSize
    ubuntuOSVersion: servicesVmUbuntuOSVersion
    virtualNetworkResourceGroupName: virtualNetworkResourceGroupName
    virtualNetworkName: virtualNetworkName
    virtualNetworkSubnetName: servicesVmSubnetName
    firewallIpsForSsh: servicesVmFirewallIpsForSsh
  }
}

// We use a single parameters.json file for multiple Bicep files and scripts, but Bicep
// will complain if we use it on a file that doesn't actually use all of the parameters.
// Therefore, we declare the extra params here.  If https://github.com/Azure/bicep/issues/5771 
// is ever fixed, these can be removed.
param subscriptionId string = ''
param resourceGroupName string = ''
param tenantId string = ''
param servicePrincipalName string = ''
param keyVaultGenerateRandomSecrets bool = false
param provisionServicePrincipal bool = true
