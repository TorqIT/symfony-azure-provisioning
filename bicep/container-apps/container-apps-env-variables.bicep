param appDebug string
param appEnv string
param storageAccountName string
param storageAccountContainerName string
param storageAccountKeySecretRefName string
param databaseServerName string
param databaseServerVersion string
param databaseName string
param databaseUser string
param databasePasswordSecretRefName string
param redisDb string
param redisHost string
param redisSessionDb string
param additionalEnvVars array

var defaultEnvVars = [
  {
    name: 'APP_DEBUG'
    value: appDebug
  }
  {
    name: 'APP_ENV'
    value: appEnv
  }
  {
    name: 'AZURE_STORAGE_ACCOUNT_CONTAINER'
    value: storageAccountContainerName
  }
  {
    name: 'AZURE_STORAGE_ACCOUNT_KEY'
    secretRef: storageAccountKeySecretRefName
  }
  {
    name: 'AZURE_STORAGE_ACCOUNT_NAME'
    value: storageAccountName
  }
  {
    name: 'DATABASE_HOST'
    value: '${databaseServerName}.mysql.database.azure.com'
  }
  {
    name: 'DATABASE_NAME'
    value: databaseName
  }
  {
    name: 'DATABASE_USER'
    value: databaseUser
  }
  {
    name: 'DATABASE_PASSWORD'
    secretRef: databasePasswordSecretRefName
  }
  {
    name: 'DATABASE_SERVER_VERSION'
    value: databaseServerVersion
  }
  {
    name: 'REDIS_DB'
    value: redisDb
  }
  {
    name: 'REDIS_HOST'
    value: redisHost
  }
  {
    name: 'REDIS_SESSION_DB'
    value: redisSessionDb
  }
]

output envVars array = concat(defaultEnvVars, additionalEnvVars)
