param location string = resourceGroup().location

param containerAppsEnvironmentName string
param containerAppJobName string
param imageName string
param cpuCores string
param memory string
param replicaTimeoutSeconds int

param defaultEnvVars array

param additionalSecrets array

param additionalVolumesAndMounts array

param containerRegistryName string

param databaseServerName string
param databaseUser string
param databaseName string

param keyVaultName string

@secure()
param storageAccountKeySecret object

param databasePasswordSecret object

param managedIdentityId string

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2022-11-01-preview' existing = {
  name: containerAppsEnvironmentName
}

// Secrets
var defaultSecrets = [databasePasswordSecret, storageAccountKeySecret]
var secrets = concat(defaultSecrets, additionalSecrets)

module volumesModule './container-apps-volumes.bicep' = {
  name: 'container-app-job-init-volumes'
  params: {
    additionalVolumesAndMounts: additionalVolumesAndMounts
  }
}

var envVars = concat(defaultEnvVars)

resource containerAppJob 'Microsoft.App/jobs@2023-05-02-preview' = {
  location: location
  name: containerAppJobName
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      replicaTimeout: replicaTimeoutSeconds
      secrets: secrets
      triggerType: 'Manual'
      eventTriggerConfig: {
        scale: {
          minExecutions: 0
          maxExecutions: 1
        }
      }
      registries: [
        {
          identity: managedIdentityId
          server: '${containerRegistryName}.azurecr.io'
        }
      ]
    }
    template: {
      containers: [
        {
          image: '${containerRegistryName}.azurecr.io/${imageName}:latest'
          env: envVars
          name: imageName
          resources: {
            cpu: json(cpuCores)
            memory: memory
          }
          volumeMounts: volumesModule.outputs.volumeMounts
        }
      ]
      volumes: volumesModule.outputs.volumes
    }
  }
}
