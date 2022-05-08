param environmentName string
param location string = resourceGroup().location
@allowed([
  'npd'
  'dev'
  'tst'
  'prd'
])
param environmentType string

var holdingStorageAccount = 'stfrsclab${environmentType}'
var toolingStorageAccount = 'stfltoolstore${environmentType}'
var diagStorageAccount = 'stfldiagstore${environmentType}'
var storageAccountSkuName = (environmentType == 'prd') ? 'Standard_LRS' : 'Standard_LRS' //udpate values should requirements change.

// Azure Storage Account - Immutable Holding Store
resource sandpitHoldingStorage 'Microsoft.Storage/storageAccounts@2021-02-01' ={
  name: holdingStorageAccount
  location: location
  tags:{
    'environment': environmentName
    'owner': 'Contoso-Cybersec'
  }
  sku:{
    name: storageAccountSkuName
  }
  kind: 'StorageV2'
  properties:{
    supportsHttpsTrafficOnly: true
    accessTier:'Hot'
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}
// Azure Storage Account - Immutable Holding Store
resource sandpitToolingStorage 'Microsoft.Storage/storageAccounts@2021-02-01' ={
  name: toolingStorageAccount
  location: location
  tags:{
    'environment': environmentName
    'owner': 'Contoso-Cybersec'
  }
  sku:{
    name: storageAccountSkuName
  }
  kind: 'StorageV2'
  properties:{
    supportsHttpsTrafficOnly: true
    accessTier:'Hot'
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}
// Azure Storage Account - Immutable Holding Store
resource diagnosticStorage 'Microsoft.Storage/storageAccounts@2021-02-01' ={
  name: diagStorageAccount
  location: location
  tags:{
    'environment': environmentName
    'owner': 'Contoso-Cybersec'
  }
  sku:{
    name: storageAccountSkuName
  }
  kind: 'StorageV2'
  properties:{
    supportsHttpsTrafficOnly: true
    accessTier:'Hot'
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource storageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${sandpitHoldingStorage.name}/default/${holdingStorageAccount}'
}

resource immutablePolicy 'Microsoft.Storage/storageAccounts/blobServices/containers/immutabilityPolicies@2021-08-01' = {
  name: 'default'
  parent: storageContainer
  properties: {
    allowProtectedAppendWrites: true
    immutabilityPeriodSinceCreationInDays: 7
  }
}

resource storageFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-08-01' = {
  name: '${sandpitToolingStorage.name}/default/toolingshare'
}
