param containerAppsEnvironmentName string
param storageAccountName string
@secure()
param storageAccountKey string
param additionalVolumesAndMounts array

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: containerAppsEnvironmentName
}
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: storageAccountName
}

var defaultVolumesAndMounts = [
  {
    mountName: 'logs'
    fileShareName: 'logs'
    accountName: storageAccountName
    accountKey: storageAccountKey
    accessMode: 'ReadWrite'
    mountAccessMode: 'ReadWrite'
    storageType: 'AzureFile'
  }
  {
    mountName: 'uploads'
    fileShareName: 'uploads'
    accountName: storageAccountName
    accountKey: storageAccountKey
    mountAccessMode: 'ReadWrite'
    storageType: 'AzureFile'
  }
]
var volumesAndMounts = concat(defaultVolumesAndMounts, additionalVolumesAndMounts)

resource mount 'Microsoft.App/managedEnvironments/storages@2024-10-02-preview' = [for volumeAndMount in volumesAndMounts: {
  parent: containerAppsEnvironment
  name: volumeAndMount.mountName
  properties: {
    nfsAzureFile: (volumeAndMount.storageType == 'NfsAzureFile') ? {
      server: '${storageAccountName}.file.${environment().suffixes.storage}'
      shareName: '/${storageAccountName}/${volumeAndMount.fileShareName}'
      accessMode: volumeAndMount.mountAccessMode
    } : null
    azureFile: (volumeAndMount.storageType == 'AzureFile') ? {
      accountName: storageAccountName
      accountKey: storageAccount.listKeys().keys[0].value
      accessMode: volumeAndMount.mountAccessMode
      shareName: volumeAndMount.fileShareName
    } : null
  }
}]
