param additionalVolumesAndMounts array

// Volumes
var defaultVolumes = [
  {
    storageType: 'AzureFile'
    name: 'uploads'
  }
  {
    storageType: 'AzureFile'
    name: 'logs'
  }
]
var secretsVolume = [{
  storageType: 'Secret'
  name: 'secrets'
}]
var additionalVolumes = [for volumeAndMount in additionalVolumesAndMounts: {
  name: volumeAndMount.volumeName
  storageName: volumeAndMount.volumeName
  storageType: volumeAndMount.?storageType ?? 'NfsAzureFile'
  mountOptions: volumeAndMount.?mountOptions ?? 'uid=1000,gid=1000'
}]
output volumes array = concat(defaultVolumes, secretsVolume, additionalVolumes)

// Volume mounts
var defaultVolumeMounts = [
  {
    volumeName: 'uploads'
    mountPath: '/var/www/html/uploads'
  }
  {
    volumeName: 'logs'
    mountPath: '/var/www/html/var/log'
  }
]
var secretsVolumeMount = [{
  volumeName: 'secrets'
  mountPath: '/run/secrets'
}]
var additionalVolumeMounts = [for volumeAndMount in additionalVolumesAndMounts: {
  volumeName: volumeAndMount.volumeName
  mountPath: volumeAndMount.mountPath
}]
output volumeMounts array = concat(defaultVolumeMounts, secretsVolumeMount, additionalVolumeMounts)
