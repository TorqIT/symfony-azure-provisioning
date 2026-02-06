param location string = resourceGroup().location

param fullProvision bool

param containerAppsEnvironmentName string
param containerAppsEnvironmentUseWorkloadProfiles bool

param logAnalyticsWorkspaceName string

param virtualNetworkName string
param virtualNetworkResourceGroup string
param virtualNetworkSubnetName string

param keyVaultName string

param databaseServerName string
param databaseServerVersion string
param databasePasswordSecretNameInKeyVault string

param containerRegistryName string

param managedIdentityName string

param storageAccountName string
param storageAccountContainerName string

param initContainerAppJobName string
param initContainerAppJobImageName string
param initContainerAppJobCpuCores string
param initContainerAppJobMemory string
param initContainerAppJobReplicaTimeoutSeconds int

param phpContainerAppExternal bool
param phpContainerAppCustomDomains array
param phpContainerAppName string
param phpContainerAppImageName string
param phpContainerAppUseProbes bool
param phpContainerAppCpuCores string
param phpContainerAppMemory string
param phpContainerAppMinReplicas int
param phpContainerAppMaxReplicas int
param phpContainerAppIpSecurityRestrictions array
// Optional scale rules
param phpContainerAppProvisionHttpScaleRule bool
param phpContainerAppHttpScaleRuleConcurrentRequestsThreshold int
param phpContainerAppProvisionCronScaleRule bool
param phpContainerAppCronScaleRuleDesiredReplicas int
param phpContainerAppCronScaleRuleStartSchedule string
param phpContainerAppCronScaleRuleEndSchedule string
param phpContainerAppCronScaleRuleTimezone string

param provisionSupervisordContainerApp bool
param supervisordContainerAppName string
param supervisordContainerAppImageName string
param supervisordContainerAppCpuCores string
param supervisordContainerAppMemory string

param appDebug string
param appEnv string
param databaseName string
param databaseUser string
param additionalEnvVars array
param additionalSecrets array
param additionalVolumesAndMounts array

// Optional metric alerts provisioning
param provisionMetricAlerts bool
param generalMetricAlertsActionGroupName string
param criticalMetricAlertsActionGroupName string

// ENVIRONMENT
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}
module containerAppsEnvironment 'environment/container-apps-environment.bicep' = {
  name: 'container-apps-environment'
  params: {
    location: location
    name: containerAppsEnvironmentName
    useWorkloadProfiles: containerAppsEnvironmentUseWorkloadProfiles
    phpContainerAppExternal: phpContainerAppExternal
    virtualNetworkName: virtualNetworkName
    virtualNetworkResourceGroup: virtualNetworkResourceGroup
    virtualNetworkSubnetName: virtualNetworkSubnetName
    logAnalyticsCustomerId: logAnalyticsWorkspace.properties.customerId
    logAnalyticsSharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
    storageAccountName: storageAccountName
    additionalVolumesAndMounts: additionalVolumesAndMounts
  }
}

// SECRETS
// Managed Identity allowing the Container App resources access other resources directly (e.g. Key Vault, Container Registry)
module managedIdentityModule './identity/container-apps-managed-identitity.bicep' = if (fullProvision) {
  name: 'container-apps-managed-identity'
  params: {
    location: location
    name: managedIdentityName
    keyVaultName: keyVaultName
    containerRegistryName: containerRegistryName
  }
}
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: managedIdentityName
}
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}
// Set up common secrets for the init, PHP and supervisord Container Apps 
var databasePasswordSecretRefName = 'database-password'
var storageAccountKeySecretRefName = 'storage-account-key'
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: storageAccountName
}
var storageAccountKeySecret = {
  name: 'storage-account-key'
  value: storageAccount.listKeys().keys[0].value  
}
resource databasePasswordSecretInKeyVault 'Microsoft.KeyVault/vaults/secrets@2023-07-01' existing = {
  parent: keyVault
  name: databasePasswordSecretNameInKeyVault
}
var databasePasswordSecret = {
  name: databasePasswordSecretRefName
  keyVaultUrl: databasePasswordSecretInKeyVault.properties.secretUri
  identity: managedIdentity.id
}
// Optional additional secrets, assumed to exist in Key Vault
module additionalSecretsModule './secrets/container-apps-additional-secrets.bicep' = {
  name: 'container-apps-additional-secrets'
  params: {
    secrets: additionalSecrets
    keyVaultName: keyVaultName
    managedIdentityForKeyVaultId: managedIdentity.id
  }
}

// ENV VARS
// Set up common environment variables for the init, PHP and supervisord Container Apps
module environmentVariables 'container-apps-env-variables.bicep' = {
  name: 'environment-variables'
  params: {
    appDebug: appDebug
    appEnv: appEnv
    databaseServerName: databaseServerName
    databaseServerVersion: databaseServerVersion
    databaseName: databaseName
    databaseUser: databaseUser
    databasePasswordSecretRefName: databasePasswordSecretRefName
    storageAccountName: storageAccountName
    storageAccountContainerName: storageAccountContainerName
    storageAccountKeySecretRefName: storageAccountKeySecretRefName
    additionalEnvVars: concat(additionalEnvVars, additionalSecretsModule.outputs.envVars)
  }
}

module initContainerAppJob 'container-app-job-init.bicep' = {
  name: 'init-container-app-job'
  dependsOn: [containerAppsEnvironment]
  params: {
    location: location
    containerAppJobName: initContainerAppJobName
    imageName: initContainerAppJobImageName
    cpuCores: initContainerAppJobCpuCores
    memory: initContainerAppJobMemory
    replicaTimeoutSeconds: initContainerAppJobReplicaTimeoutSeconds
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerRegistryName: containerRegistryName
    storageAccountKeySecret: storageAccountKeySecret
    databasePasswordSecret: databasePasswordSecret
    defaultEnvVars: environmentVariables.outputs.envVars
    databaseServerName: databaseServerName
    databaseName: databaseName
    databaseUser: databaseUser
    managedIdentityId: managedIdentity.id
    keyVaultName: keyVaultName
    additionalSecrets: additionalSecretsModule.outputs.secrets
    additionalVolumesAndMounts: additionalVolumesAndMounts
  }
}

module phpContainerApp 'container-app-php.bicep' = {
  name: 'php-container-app'
  dependsOn: [containerAppsEnvironment]
  params: {
    location: location
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerAppName: phpContainerAppName
    imageName: phpContainerAppImageName
    environmentVariables: environmentVariables.outputs.envVars
    containerRegistryName: containerRegistryName
    cpuCores: phpContainerAppCpuCores
    memory: phpContainerAppMemory
    useProbes: phpContainerAppUseProbes
    minReplicas: phpContainerAppMinReplicas
    maxReplicas: phpContainerAppMaxReplicas
    customDomains: phpContainerAppCustomDomains
    isExternal: phpContainerAppExternal
    ipSecurityRestrictions: phpContainerAppIpSecurityRestrictions
    managedIdentityId: managedIdentity.id
    databasePasswordSecret: databasePasswordSecret
    storageAccountKeySecret: storageAccountKeySecret
    additionalSecrets: additionalSecretsModule.outputs.secrets
    additionalVolumesAndMounts: additionalVolumesAndMounts

    // Optional scaling rules
    provisionHttpScaleRule: phpContainerAppProvisionHttpScaleRule
    httpScaleRuleConcurrentRequestsThreshold: phpContainerAppHttpScaleRuleConcurrentRequestsThreshold
    provisionCronScaleRule: phpContainerAppProvisionCronScaleRule
    cronScaleRuleDesiredReplicas: phpContainerAppCronScaleRuleDesiredReplicas
    cronScaleRuleStartSchedule: phpContainerAppCronScaleRuleStartSchedule
    cronScaleRuleEndSchedule: phpContainerAppCronScaleRuleEndSchedule
    cronScaleRuleTimezone: phpContainerAppCronScaleRuleTimezone
  }
}

module supervisordContainerApp 'container-app-supervisord.bicep' = if (provisionSupervisordContainerApp) {
  name: 'supervisord-container-app'
  dependsOn: [containerAppsEnvironment]
  params: {
    location: location
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerAppName: supervisordContainerAppName
    imageName: supervisordContainerAppImageName
    environmentVariables: environmentVariables.outputs.envVars
    containerRegistryName: containerRegistryName
    cpuCores: supervisordContainerAppCpuCores
    memory: supervisordContainerAppMemory
    managedIdentityId: managedIdentity.id
    databasePasswordSecret: databasePasswordSecret
    storageAccountKeySecret: storageAccountKeySecret
    additionalSecrets: additionalSecretsModule.outputs.secrets
    additionalVolumesAndMounts: additionalVolumesAndMounts
  }
}

// Optional metric alerts
module alerts './alerts/container-app-alerts.bicep' = [for containerAppName in [phpContainerAppName, supervisordContainerAppName]: if (provisionMetricAlerts) {
  name: '${containerAppName}-alerts'
  dependsOn: [phpContainerApp, supervisordContainerApp]
  params: {
    containerAppName: containerAppName
    generalMetricAlertsActionGroupName: generalMetricAlertsActionGroupName
  }
}] 
